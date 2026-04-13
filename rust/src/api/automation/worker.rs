//! Auto-compression worker thread implementation.
//!
//! Contains the main auto_loop, compression execution, and broadcast
//! functions that run on the background auto-compression thread.
//!
//! Compression runs on a dedicated spawned thread so the main auto_loop
//! can continue processing stop signals, config updates, watcher events,
//! and state broadcasts during long-running compression operations.

use std::collections::{HashSet, VecDeque};
use std::path::PathBuf;
use std::sync::mpsc::RecvTimeoutError;
use std::time::Duration;

use super::{
    shared_state_lock, worker_broadcast, worker_compression::join_compression_worker,
    worker_compression::spawn_compression_job, worker_compression::ActiveCompressionJob,
    worker_compression::CompressionResult, worker_reconcile,
};
use crate::api::automation_types::{FrbAutomationConfig, FrbSchedulerState};
use crate::automation::idle::{IdleConfig, IdleDetector};
use crate::automation::journal::JournalWriter;
use crate::automation::scheduler::{AutoScheduler, SchedulerAction, SchedulerConfig};
use crate::automation::watcher::{GameWatcher, WatchEvent, WatcherConfig};
use crate::compression::algorithm::CompressionAlgorithm;
use crate::safety::process::ProcessChecker;

const WATCHER_EVENT_COALESCE_DELAY: Duration = Duration::from_secs(1);

pub(super) fn broadcast_auto_status(is_running: bool) {
    worker_broadcast::broadcast_auto_status(is_running);
}

pub(super) fn auto_loop(
    stop_rx: std::sync::mpsc::Receiver<()>,
    config_rx: std::sync::mpsc::Receiver<FrbAutomationConfig>,
) {
    let mut idle_detector = IdleDetector::default();
    let process_checker = ProcessChecker::new();

    let journal = match JournalWriter::default_path() {
        Ok(j) => j,
        Err(e) => {
            log::error!("Failed to initialize automation journal: {e}");
            JournalWriter::new(PathBuf::from("automation_journal.json"))
        }
    };

    let scheduler_config = SchedulerConfig::default();
    let mut scheduler = AutoScheduler::restore_or_new(scheduler_config, journal);

    let mut watcher = GameWatcher::new(WatcherConfig::default());
    if let Err(e) = watcher.start() {
        log::warn!("Watcher start failed (will retry on config update): {e}");
    }

    let mut last_state = scheduler.state();
    let mut active_compression: Option<ActiveCompressionJob> = None;
    let mut current_algorithm = CompressionAlgorithm::Xpress8K;
    let mut current_allow_directstorage_override = false;
    let mut current_io_parallelism_override: Option<usize> = None;
    let mut last_startup_reconcile_watch_paths: Vec<String> = Vec::new();
    let mut startup_reconcile_pending_watch_paths: Option<Vec<String>> = None;
    let mut startup_reconcile_pending_normalized_watch_paths: Vec<String> = Vec::new();
    let mut startup_reconcile_pending_candidates: Option<
        VecDeque<worker_reconcile::ReconcileCandidate>,
    > = None;
    let mut startup_reconcile_attempted_paths: HashSet<String> = HashSet::new();

    loop {
        match stop_rx.recv_timeout(Duration::from_secs(2)) {
            Ok(()) | Err(RecvTimeoutError::Disconnected) => {
                if let Some(mut job) = active_compression.take() {
                    job.cancel_token.cancel();
                    if job.result_rx.recv_timeout(Duration::from_secs(5)).is_err() {
                        log::warn!(
                            "Timed out waiting for auto-compression cancellation result; waiting for worker thread join"
                        );
                    }
                    join_compression_worker(&mut job, "shutdown");
                }
                break;
            }
            Err(RecvTimeoutError::Timeout) => {}
        }

        // Check config updates (coalesce bursts to keep loop responsive).
        let mut newest_config: Option<FrbAutomationConfig> = None;
        let mut drained_updates = 0_usize;
        while let Ok(config) = config_rx.try_recv() {
            newest_config = Some(config);
            drained_updates = drained_updates.saturating_add(1);
        }
        if let Some(new_config) = newest_config {
            if drained_updates > 1 {
                log::debug!(
                    "Coalesced {} pending automation config updates into latest snapshot",
                    drained_updates
                );
            }
            log::info!("Received automation config update");
            current_algorithm = frb_algorithm_to_internal(&new_config.algorithm);
            current_allow_directstorage_override = new_config.allow_directstorage_override;
            current_io_parallelism_override =
                io_parallelism_override_to_usize(new_config.io_parallelism_override);
            let normalized_watch_paths =
                worker_reconcile::normalize_watch_paths(&new_config.watch_paths);
            apply_config(
                &new_config,
                &mut idle_detector,
                &mut scheduler,
                &mut watcher,
            );
            worker_broadcast::update_shared_state(&scheduler, &watcher);
            let has_pending_startup_reconcile = startup_reconcile_pending_watch_paths.is_some();
            let pending_paths_changed = has_pending_startup_reconcile
                && normalized_watch_paths != startup_reconcile_pending_normalized_watch_paths;
            let completed_paths_changed =
                normalized_watch_paths != last_startup_reconcile_watch_paths;

            // Avoid restarting a pending reconcile cycle on repeated config updates
            // unless the watched-path target actually changed.
            if pending_paths_changed && !completed_paths_changed {
                startup_reconcile_pending_watch_paths = None;
                startup_reconcile_pending_normalized_watch_paths.clear();
                startup_reconcile_pending_candidates = None;
                startup_reconcile_attempted_paths.clear();
            } else if completed_paths_changed
                && (!has_pending_startup_reconcile || pending_paths_changed)
            {
                startup_reconcile_pending_watch_paths = Some(new_config.watch_paths.clone());
                startup_reconcile_pending_normalized_watch_paths = normalized_watch_paths;
                startup_reconcile_pending_candidates = None;
                startup_reconcile_attempted_paths.clear();
            }
        }

        let mut finished_result: Option<CompressionResult> = None;
        let mut worker_disconnected = false;
        if let Some(active_job) = active_compression.as_mut() {
            match active_job.result_rx.try_recv() {
                Ok(result) => finished_result = Some(result),
                Err(crossbeam_channel::TryRecvError::Empty) => {}
                Err(crossbeam_channel::TryRecvError::Disconnected) => worker_disconnected = true,
            }
        }

        if let Some(result) = finished_result {
            if let Some(mut finished_job) = active_compression.take() {
                join_compression_worker(&mut finished_job, "completion");
            }
            match result {
                CompressionResult::Success { idempotency_key } => {
                    scheduler.job_completed(&idempotency_key);
                }
                CompressionResult::Failed {
                    idempotency_key,
                    error,
                } => {
                    scheduler.job_failed(&idempotency_key, error);
                }
                CompressionResult::Skipped {
                    idempotency_key,
                    reason,
                } => {
                    scheduler.job_skipped(&idempotency_key, reason);
                }
            }
            worker_broadcast::broadcast_automation_queue(scheduler.queue_snapshot());
        } else if worker_disconnected {
            log::error!("Compression worker thread disconnected unexpectedly");
            if let Some(mut disconnected_job) = active_compression.take() {
                join_compression_worker(&mut disconnected_job, "disconnect");
            }
        }

        if let Some(rx) = watcher.event_channel() {
            while let Ok(event) = rx.try_recv() {
                on_watcher_event(&event);
                worker_broadcast::broadcast_watcher_event(&event);
                scheduler.on_event(event);
            }
        }

        maybe_run_startup_reconcile(
            &mut scheduler,
            &active_compression,
            &mut startup_reconcile_pending_watch_paths,
            &mut startup_reconcile_pending_normalized_watch_paths,
            &mut startup_reconcile_pending_candidates,
            &mut last_startup_reconcile_watch_paths,
            &mut startup_reconcile_attempted_paths,
        );

        let is_idle = idle_detector.is_idle();
        let cpu_usage_percent = idle_detector.cpu_usage();

        if !is_idle {
            if let Some(ref job) = active_compression {
                job.cancel_token.cancel();
            }
        }

        if let Some(action) = scheduler.tick(is_idle, false) {
            match action {
                SchedulerAction::Compress(job) => {
                    active_compression = Some(spawn_compression_job(
                        &job,
                        &process_checker,
                        current_algorithm,
                        current_allow_directstorage_override,
                        cpu_usage_percent,
                        current_io_parallelism_override,
                    ));
                }
                SchedulerAction::Persist => {
                    if let Err(e) = scheduler.persist() {
                        log::error!("Failed to persist automation journal: {e}");
                    }
                }
            }
        }

        let current_state = scheduler.state();
        if current_state != last_state {
            worker_broadcast::broadcast_scheduler_state(current_state);
            worker_broadcast::broadcast_automation_queue(scheduler.queue_snapshot());
            last_state = current_state;
        }
        worker_broadcast::update_shared_state(&scheduler, &watcher);
    }

    watcher.stop();
    if let Err(e) = scheduler.persist() {
        log::error!("Failed to persist journal during shutdown: {e}");
    }

    {
        let mut guard = shared_state_lock().lock().unwrap_or_else(|poisoned| {
            log::warn!("Shared state lock poisoned during shutdown; recovering");
            poisoned.into_inner()
        });
        guard.scheduler_state = FrbSchedulerState::Idle;
        guard.queue.clear();
        guard.watched_path_count = 0;
        guard.queue_depth = 0;
    }

    broadcast_auto_status(false);
}

fn apply_config(
    config: &FrbAutomationConfig,
    idle_detector: &mut IdleDetector,
    scheduler: &mut AutoScheduler,
    watcher: &mut GameWatcher,
) {
    idle_detector.update_config(IdleConfig {
        cpu_threshold_percent: config.cpu_threshold_percent,
        idle_duration: Duration::from_secs(config.idle_duration_seconds),
    });

    let excluded: HashSet<String> = config
        .excluded_paths
        .iter()
        .map(|p| p.to_ascii_lowercase())
        .collect();
    let watch_paths: Vec<PathBuf> = config.watch_paths.iter().map(PathBuf::from).collect();

    scheduler.update_config(SchedulerConfig {
        cooldown: Duration::from_secs(config.cooldown_seconds),
        excluded_paths: excluded,
        watch_paths: watch_paths.clone(),
    });

    log::info!(
        "[automation][config] watch_paths={} scheduler_cooldown_seconds={} idle_duration_seconds={} watcher_event_delay_seconds={}",
        watch_paths.len(),
        config.cooldown_seconds,
        config.idle_duration_seconds,
        WATCHER_EVENT_COALESCE_DELAY.as_secs()
    );
    for path in &watch_paths {
        log::debug!("[automation][config] watching path=\"{}\"", path.display());
    }

    watcher.update_config(WatcherConfig {
        watch_paths,
        cooldown: WATCHER_EVENT_COALESCE_DELAY,
    });
}

fn maybe_run_startup_reconcile(
    scheduler: &mut AutoScheduler,
    active_compression: &Option<ActiveCompressionJob>,
    pending_watch_paths: &mut Option<Vec<String>>,
    pending_normalized_watch_paths: &mut Vec<String>,
    pending_candidates: &mut Option<VecDeque<worker_reconcile::ReconcileCandidate>>,
    last_completed_normalized_watch_paths: &mut Vec<String>,
    attempted_paths: &mut HashSet<String>,
) {
    if pending_watch_paths.is_none() {
        return;
    }

    // Keep startup reconcile lightweight: only scan when no compression is active
    // and the scheduler queue has drained from prior reconcile batches.
    if active_compression.is_some() || scheduler.pending_queue_len() > 0 {
        return;
    }

    if pending_candidates.is_none() {
        let Some(watch_paths) = pending_watch_paths.as_ref() else {
            return;
        };
        *pending_candidates = Some(worker_reconcile::build_startup_reconcile_candidates(
            watch_paths,
        ));
    }

    let result = {
        let Some(candidates) = pending_candidates.as_mut() else {
            return;
        };
        worker_reconcile::enqueue_startup_reconcile_candidate_batch(
            scheduler,
            candidates,
            attempted_paths,
        )
    };

    if result.queued > 0 {
        log::info!(
            "Queued {} startup reconcile job(s) for changes detected while app was closed",
            result.queued
        );
        worker_broadcast::broadcast_automation_queue(scheduler.queue_snapshot());
    }

    if result.hit_cap {
        log::debug!(
            "Startup reconcile hit per-pass cap; remaining candidates will be queued in next drain cycle"
        );
        return;
    }

    *last_completed_normalized_watch_paths = std::mem::take(pending_normalized_watch_paths);
    *pending_watch_paths = None;
    *pending_candidates = None;
    attempted_paths.clear();
}

fn frb_algorithm_to_internal(
    algo: &crate::api::types::FrbCompressionAlgorithm,
) -> CompressionAlgorithm {
    use crate::api::types::FrbCompressionAlgorithm;
    match algo {
        FrbCompressionAlgorithm::Xpress4K => CompressionAlgorithm::Xpress4K,
        FrbCompressionAlgorithm::Xpress8K => CompressionAlgorithm::Xpress8K,
        FrbCompressionAlgorithm::Xpress16K => CompressionAlgorithm::Xpress16K,
        FrbCompressionAlgorithm::Lzx => CompressionAlgorithm::Lzx,
    }
}

fn io_parallelism_override_to_usize(io_parallelism_override: Option<u64>) -> Option<usize> {
    crate::utils::io_parallelism_override_to_usize(io_parallelism_override)
}

fn on_watcher_event(event: &WatchEvent) {
    if let WatchEvent::GameUninstalled { path, .. } = event {
        crate::discovery::utils::evict_discovery_entry(path);
        crate::discovery::cache::persist_if_dirty();
        crate::discovery::index::persist_if_dirty();
        crate::discovery::change_feed::persist_if_dirty();
        crate::discovery::install_history::persist_if_dirty();
    }
}
