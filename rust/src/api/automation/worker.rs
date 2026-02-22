//! Auto-compression worker thread implementation.
//!
//! Contains the main auto_loop, compression execution, and broadcast
//! functions that run on the background auto-compression thread.
//!
//! Compression runs on a dedicated spawned thread so the main auto_loop
//! can continue processing stop signals, config updates, watcher events,
//! and state broadcasts during long-running compression operations.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::mpsc::RecvTimeoutError;
use std::time::Duration;

use super::{
    auto_status_sinks_lock, automation_queue_sinks_lock, scheduler_state_sinks_lock,
    shared_state_lock, watcher_event_sinks_lock,
};
use crate::api::automation_types::{
    FrbAutomationConfig, FrbAutomationJob, FrbSchedulerState, FrbWatcherEvent,
};
use crate::automation::idle::{IdleConfig, IdleDetector};
use crate::automation::journal::JournalWriter;
use crate::automation::scheduler::{AutoScheduler, SchedulerAction, SchedulerConfig};
use crate::automation::watcher::{GameWatcher, WatcherConfig};
use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::engine::{CancellationToken, CompressionEngine};
use crate::safety::directstorage::is_directstorage_game;
use crate::safety::process::ProcessChecker;


pub(super) fn broadcast_auto_status(is_running: bool) {
    let mut guard = auto_status_sinks_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("AUTO status sinks lock poisoned during broadcast; recovering");
        poisoned.into_inner()
    });
    guard.retain(|sink| sink.add(is_running).is_ok());
}

fn broadcast_watcher_event(event: &crate::automation::watcher::WatchEvent) {
    let frb_event: FrbWatcherEvent = event.clone().into();
    let mut guard = watcher_event_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Watcher event sinks lock poisoned; recovering");
            poisoned.into_inner()
        });
    guard.retain(|sink| sink.add(frb_event.clone()).is_ok());
}

fn broadcast_scheduler_state(state: crate::automation::scheduler::SchedulerState) {
    let frb_state: FrbSchedulerState = state.into();
    let mut guard = scheduler_state_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Scheduler state sinks lock poisoned; recovering");
            poisoned.into_inner()
        });
    guard.retain(|sink| sink.add(frb_state).is_ok());
}

fn broadcast_automation_queue(jobs: Vec<crate::automation::scheduler::AutomationJob>) {
    let frb_jobs: Vec<FrbAutomationJob> = jobs.into_iter().map(|j| j.into()).collect();
    let mut guard = automation_queue_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Automation queue sinks lock poisoned; recovering");
            poisoned.into_inner()
        });
    guard.retain(|sink| sink.add(frb_jobs.clone()).is_ok());
}

fn update_shared_state(scheduler: &AutoScheduler, watcher: &GameWatcher) {
    let mut guard = shared_state_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("Shared state lock poisoned during update; recovering");
        poisoned.into_inner()
    });
    guard.scheduler_state = scheduler.state().into();
    guard.queue = scheduler
        .queue_snapshot()
        .into_iter()
        .map(|j| j.into())
        .collect();
    guard.watched_path_count = watcher.watched_path_count() as u32;
    guard.queue_depth = scheduler.pending_queue_len() as u32;
}

enum CompressionResult {
    Success { idempotency_key: String },
    Failed { idempotency_key: String, error: String },
    Skipped { idempotency_key: String, reason: String },
}

struct ActiveCompressionJob {
    result_rx: crossbeam_channel::Receiver<CompressionResult>,
    cancel_token: CancellationToken,
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

    loop {
        match stop_rx.recv_timeout(Duration::from_secs(2)) {
            Ok(()) | Err(RecvTimeoutError::Disconnected) => {
                if let Some(ref job) = active_compression {
                    job.cancel_token.cancel();
                    let _ = job.result_rx.recv_timeout(Duration::from_secs(5));
                }
                break;
            }
            Err(RecvTimeoutError::Timeout) => {}
        }

        // Check config updates 
        while let Ok(new_config) = config_rx.try_recv() {
            log::info!("Received automation config update");
            current_algorithm = frb_algorithm_to_internal(&new_config.algorithm);
            apply_config(
                &new_config,
                &mut idle_detector,
                &mut scheduler,
                &mut watcher,
            );
        }

        if let Some(ref active_job) = active_compression {
            match active_job.result_rx.try_recv() {
                Ok(result) => {
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
                    active_compression = None;
                    broadcast_automation_queue(scheduler.queue_snapshot());
                }
                Err(crossbeam_channel::TryRecvError::Empty) => {
                }
                Err(crossbeam_channel::TryRecvError::Disconnected) => {
                    log::error!("Compression worker thread disconnected unexpectedly");
                    active_compression = None;
                }
            }
        }

        if let Some(rx) = watcher.event_channel() {
            while let Ok(event) = rx.try_recv() {
                broadcast_watcher_event(&event);
                scheduler.on_event(event);
            }
        }

        let is_idle = idle_detector.is_idle();

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
            broadcast_scheduler_state(current_state);
            broadcast_automation_queue(scheduler.queue_snapshot());
            last_state = current_state;
        }
        update_shared_state(&scheduler, &watcher);
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

    watcher.update_config(WatcherConfig {
        watch_paths,
        cooldown: Duration::from_secs(config.cooldown_seconds),
    });
}

/// Spawn compression on a dedicated thread so auto_loop stays responsive.
fn spawn_compression_job(
    job: &crate::automation::scheduler::AutomationJob,
    process_checker: &ProcessChecker,
    algorithm: CompressionAlgorithm,
) -> ActiveCompressionJob {
    let game_path = job.game_path.clone();
    let game_name = job.game_name.clone();
    let idempotency_key = job.idempotency_key.clone();
    let (result_tx, result_rx) = crossbeam_channel::bounded::<CompressionResult>(1);
    let cancel_token = CancellationToken::new();

    if is_directstorage_game(&game_path) {
        log::info!("Skipping DirectStorage game: {}", game_path.display());
        let _ = result_tx.send(CompressionResult::Skipped {
            idempotency_key,
            reason: "DirectStorage detected".to_string(),
        });
        return ActiveCompressionJob {
            result_rx,
            cancel_token,
        };
    }

    if process_checker.is_game_running(&game_path) {
        log::info!("Game is running, deferring: {}", game_path.display());
        let _ = result_tx.send(CompressionResult::Failed {
            idempotency_key,
            error: "Game is currently running".to_string(),
        });
        return ActiveCompressionJob {
            result_rx,
            cancel_token,
        };
    }

    if !game_path.is_dir() {
        log::warn!("Game path no longer exists: {}", game_path.display());
        let _ = result_tx.send(CompressionResult::Skipped {
            idempotency_key,
            reason: "Path not found".to_string(),
        });
        return ActiveCompressionJob {
            result_rx,
            cancel_token,
        };
    }

    let token = cancel_token.clone();
    let _ = std::thread::Builder::new()
        .name("pressplay-auto-compress".to_owned())
        .spawn(move || {
            let engine = CompressionEngine::new(algorithm);
            let engine_token = engine.cancel_token();
            let cancel_watcher_token = token.clone();
            let cancel_watcher_engine_token = engine_token.clone();
            let cancel_watcher = std::thread::Builder::new()
                .name("pressplay-cancel-watcher".to_owned())
                .spawn(move || {
                    while !cancel_watcher_token.is_cancelled()
                        && !cancel_watcher_engine_token.is_cancelled()
                    {
                        std::thread::sleep(Duration::from_millis(250));
                    }
                    if cancel_watcher_token.is_cancelled() {
                        cancel_watcher_engine_token.cancel();
                    }
                });

            log::info!(
                "Auto-compressing: {} ({}) with {:?}",
                game_name.as_deref().unwrap_or("unknown"),
                game_path.display(),
                algorithm,
            );

            let result = engine.compress_folder(&game_path);
            engine_token.cancel();
            if let Ok(handle) = cancel_watcher {
                let _ = handle.join();
            }

            let compression_result = match result {
                Ok(stats) => {
                    log::info!(
                        "Auto-compression complete: {} saved {:.1}% ({} bytes)",
                        game_path.display(),
                        stats.savings_ratio() * 100.0,
                        stats.bytes_saved()
                    );
                    CompressionResult::Success { idempotency_key }
                }
                Err(crate::compression::error::CompressionError::Cancelled) => {
                    log::info!(
                        "Auto-compression cancelled for: {}",
                        game_path.display()
                    );
                    CompressionResult::Failed {
                        idempotency_key,
                        error: "Cancelled due to user activity".to_string(),
                    }
                }
                Err(e) => {
                    log::error!(
                        "Auto-compression failed for {}: {e}",
                        game_path.display()
                    );
                    CompressionResult::Failed {
                        idempotency_key,
                        error: e.to_string(),
                    }
                }
            };

            let _ = result_tx.send(compression_result);
        });

    ActiveCompressionJob {
        result_rx,
        cancel_token,
    }
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
