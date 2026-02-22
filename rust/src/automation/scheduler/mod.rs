//! Automation scheduler state machine.
//!
//! Manages a queue of compression jobs, advancing through states
//! based on idle detection, safety checks, and watcher events.
//! Uses a single-owner model on the auto-compression thread.

mod types;
pub use types::*;

#[cfg(test)]
mod tests;

use std::collections::VecDeque;
use std::time::{Instant, SystemTime};

use super::journal::{JournalEntry, JournalEventKind, JournalWriter};
use super::watcher::WatchEvent;

/// The automation scheduler state machine.
///
/// Manages a bounded queue of jobs and advances through states
/// based on idle detection, process safety, and filesystem events.
pub struct AutoScheduler {
    state: SchedulerState,
    pub(crate) queue: VecDeque<AutomationJob>,
    config: SchedulerConfig,
    journal: JournalWriter,
    pub(crate) backoff_until: Option<Instant>,
    consecutive_failures: u32,
    settle_started: Option<Instant>,
    needs_persist: bool,
}

impl AutoScheduler {
    pub fn new(config: SchedulerConfig, journal: JournalWriter) -> Self {
        Self {
            state: SchedulerState::WaitingForEvents,
            queue: VecDeque::new(),
            config,
            journal,
            backoff_until: None,
            consecutive_failures: 0,
            settle_started: None,
            needs_persist: false,
        }
    }

    /// Restore from journal or create a fresh scheduler.
    pub fn restore_or_new(config: SchedulerConfig, journal: JournalWriter) -> Self {
        let mut scheduler = Self::new(config, journal);
        if let Ok(count) = scheduler.journal.load() {
            if count > 0 {
                log::info!("Restored {count} pending jobs from journal");
                let entries = scheduler.journal.snapshot();
                for entry in entries {
                    let job = AutomationJob {
                        game_path: entry.game_path,
                        game_name: entry.game_name,
                        kind: match entry.event_kind {
                            JournalEventKind::NewInstall => JobKind::NewInstall,
                            JournalEventKind::Reconcile => JobKind::Reconcile,
                            JournalEventKind::Opportunistic => JobKind::Opportunistic,
                        },
                        status: JobStatus::Pending,
                        idempotency_key: entry.idempotency_key,
                        queued_at: entry.queued_at,
                        started_at: None,
                        error: None,
                    };
                    scheduler.enqueue_job(job);
                }
                if !scheduler.queue.is_empty() {
                    scheduler.state = SchedulerState::WaitingForIdle;
                }
            }
        }
        scheduler
    }

    /// Handle an incoming watcher event.
    pub fn on_event(&mut self, event: WatchEvent) {
        let (path, game_name, kind) = match &event {
            WatchEvent::GameInstalled { path, game_name } => {
                (path.clone(), game_name.clone(), JobKind::NewInstall)
            }
            WatchEvent::GameModified { path, game_name } => {
                (path.clone(), game_name.clone(), JobKind::Reconcile)
            }
            WatchEvent::GameUninstalled { path, .. } => {
                self.queue.retain(|j| j.game_path != *path);
                let path_prefix =
                    format!("{}:", path.to_string_lossy().to_ascii_lowercase());
                self.journal.remove_by_prefix(&path_prefix);
                self.needs_persist = true;
                return;
            }
        };

        let path_str = path.to_string_lossy().to_ascii_lowercase();

        // Check exclusion list
        if self.config.excluded_paths.contains(&path_str)
            || self
                .config
                .excluded_paths
                .contains(&path.to_string_lossy().to_string())
        {
            log::debug!("Skipping excluded path: {}", path.display());
            return;
        }

        // Deduplicate: skip if already queued for this path
        if self.queue.iter().any(|j| {
            j.game_path == path
                && matches!(
                    j.status,
                    JobStatus::Pending | JobStatus::WaitingForSettle | JobStatus::WaitingForIdle
                )
        }) {
            log::debug!("Already queued for: {}", path.display());
            return;
        }

        let epoch = SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let idempotency_key = format!("{path_str}:{epoch}");

        let job = AutomationJob {
            game_path: path,
            game_name,
            kind,
            status: JobStatus::Pending,
            idempotency_key: idempotency_key.clone(),
            queued_at: SystemTime::now(),
            started_at: None,
            error: None,
        };

        self.enqueue_job(job);

        // Record in journal
        let entry = JournalEntry::with_idempotency_key(
            event.path().clone(),
            event.game_name().map(|s| s.to_string()),
            match kind {
                JobKind::NewInstall => JournalEventKind::NewInstall,
                JobKind::Reconcile => JournalEventKind::Reconcile,
                JobKind::Opportunistic => JournalEventKind::Opportunistic,
            },
            idempotency_key,
        );
        self.journal.insert(entry);
        self.needs_persist = true;

        // Advance state if we were waiting
        if self.state == SchedulerState::WaitingForEvents {
            self.state = SchedulerState::WaitingForSettle;
            self.settle_started = Some(Instant::now());
        }
    }

    /// Advance the state machine. Called periodically from auto_loop.
    pub fn tick(&mut self, is_idle: bool, _process_active: bool) -> Option<SchedulerAction> {
        if self.needs_persist {
            self.needs_persist = false;
            return Some(SchedulerAction::Persist);
        }

        match self.state {
            SchedulerState::WaitingForEvents => None,

            SchedulerState::WaitingForSettle => {
                if let Some(start) = self.settle_started {
                    if start.elapsed() >= self.config.cooldown {
                        self.state = SchedulerState::WaitingForIdle;
                        self.settle_started = None;
                        for job in &mut self.queue {
                            if job.status == JobStatus::Pending {
                                job.status = JobStatus::WaitingForIdle;
                            }
                        }
                    }
                } else {
                    self.state = SchedulerState::WaitingForIdle;
                }
                None
            }

            SchedulerState::WaitingForIdle => {
                if is_idle {
                    self.state = SchedulerState::SafetyCheck;
                }
                None
            }

            SchedulerState::SafetyCheck => {
                if let Some(job) = self.next_pending_job() {
                    let mut job = job.clone();
                    job.status = JobStatus::Compressing;
                    job.started_at = Some(SystemTime::now());

                    if let Some(q) = self
                        .queue
                        .iter_mut()
                        .find(|j| j.idempotency_key == job.idempotency_key)
                    {
                        q.status = JobStatus::Compressing;
                        q.started_at = job.started_at;
                    }

                    self.state = SchedulerState::Compressing;
                    Some(SchedulerAction::Compress(job))
                } else {
                    self.state = SchedulerState::WaitingForEvents;
                    None
                }
            }

            SchedulerState::Compressing => {
                if !is_idle {
                    self.state = SchedulerState::Paused;
                }
                None
            }

            SchedulerState::Paused => {
                if is_idle {
                    self.state = SchedulerState::Compressing;
                }
                None
            }

            SchedulerState::Backoff => {
                if let Some(until) = self.backoff_until {
                    if Instant::now() >= until {
                        self.backoff_until = None;
                        self.state = SchedulerState::WaitingForIdle;
                    }
                } else {
                    self.state = SchedulerState::WaitingForIdle;
                }
                None
            }
        }
    }

    /// Mark the current compression job as completed.
    pub fn job_completed(&mut self, idempotency_key: &str) {
        if let Some(job) = self
            .queue
            .iter_mut()
            .find(|j| j.idempotency_key == idempotency_key)
        {
            job.status = JobStatus::Completed;
        }
        self.journal.remove(idempotency_key);
        self.consecutive_failures = 0;
        self.needs_persist = true;
        self.prune_finished();

        if self.has_pending_jobs() {
            self.state = SchedulerState::WaitingForIdle;
        } else {
            self.state = SchedulerState::WaitingForEvents;
        }
    }

    /// Mark the current compression job as failed.
    pub fn job_failed(&mut self, idempotency_key: &str, error: String) {
        if let Some(job) = self
            .queue
            .iter_mut()
            .find(|j| j.idempotency_key == idempotency_key)
        {
            job.status = JobStatus::Failed;
            job.error = Some(error);
        }
        self.journal.remove(idempotency_key);
        self.consecutive_failures += 1;
        self.needs_persist = true;
        self.prune_finished();

        let backoff =
            INITIAL_BACKOFF * 2u32.saturating_pow(self.consecutive_failures.saturating_sub(1));
        let capped = backoff.min(MAX_BACKOFF);
        self.backoff_until = Some(Instant::now() + capped);

        if self.has_pending_jobs() {
            self.state = SchedulerState::Backoff;
        } else {
            self.state = SchedulerState::WaitingForEvents;
        }
    }

    /// Mark a job as skipped (e.g., DirectStorage detected).
    pub fn job_skipped(&mut self, idempotency_key: &str, reason: String) {
        if let Some(job) = self
            .queue
            .iter_mut()
            .find(|j| j.idempotency_key == idempotency_key)
        {
            job.status = JobStatus::Skipped;
            job.error = Some(reason);
        }
        self.journal.remove(idempotency_key);
        self.needs_persist = true;
        self.prune_finished();

        if self.has_pending_jobs() {
            self.state = SchedulerState::WaitingForIdle;
        } else {
            self.state = SchedulerState::WaitingForEvents;
        }
    }

    /// Pause the scheduler (external control).
    pub fn pause(&mut self) {
        if self.state != SchedulerState::Paused {
            self.state = SchedulerState::Paused;
        }
    }

    /// Resume the scheduler from pause.
    pub fn resume(&mut self) {
        if self.state == SchedulerState::Paused {
            if self.has_pending_jobs() || self.has_active_job() {
                self.state = SchedulerState::WaitingForIdle;
            } else {
                self.state = SchedulerState::WaitingForEvents;
            }
        }
    }

    /// Persist the journal to disk.
    pub fn persist(&self) -> Result<(), std::io::Error> {
        self.journal.flush()
    }

    pub fn state(&self) -> SchedulerState {
        self.state
    }

    pub fn pending_queue_len(&self) -> usize {
        self.queue
            .iter()
            .filter(|j| {
                matches!(
                    j.status,
                    JobStatus::Pending | JobStatus::WaitingForSettle | JobStatus::WaitingForIdle
                )
            })
            .count()
    }

    pub fn active_job(&self) -> Option<&AutomationJob> {
        self.queue
            .iter()
            .find(|j| j.status == JobStatus::Compressing)
    }

    pub fn queue_snapshot(&self) -> Vec<AutomationJob> {
        self.queue.iter().cloned().collect()
    }

    pub fn update_config(&mut self, config: SchedulerConfig) {
        self.config = config;
    }

    fn enqueue_job(&mut self, job: AutomationJob) {
        if self.queue.len() >= MAX_QUEUE_SIZE {
            if let Some(idx) = self
                .queue
                .iter()
                .position(|j| !matches!(j.status, JobStatus::Compressing))
            {
                let dropped = self.queue.remove(idx);
                if let Some(dropped) = dropped {
                    log::warn!(
                        "Queue overflow ({}): dropped job for {}",
                        MAX_QUEUE_SIZE,
                        dropped.game_path.display()
                    );
                }
            }
        }
        self.queue.push_back(job);
    }

    /// Get the next job to process, prioritizing Reconcile > NewInstall > Opportunistic.
    fn next_pending_job(&self) -> Option<&AutomationJob> {
        let is_ready =
            |j: &&AutomationJob| matches!(j.status, JobStatus::Pending | JobStatus::WaitingForIdle);

        // Reconcile jobs first (post-update recompression)
        if let Some(job) = self.queue.iter().find(|j| is_ready(j) && j.kind == JobKind::Reconcile) {
            return Some(job);
        }
        // Then new installs
        if let Some(job) =
            self.queue.iter().find(|j| is_ready(j) && j.kind == JobKind::NewInstall)
        {
            return Some(job);
        }
        // Finally opportunistic
        self.queue.iter().find(|j| is_ready(j))
    }

    fn has_pending_jobs(&self) -> bool {
        self.queue.iter().any(|j| {
            matches!(
                j.status,
                JobStatus::Pending | JobStatus::WaitingForSettle | JobStatus::WaitingForIdle
            )
        })
    }

    fn has_active_job(&self) -> bool {
        self.queue
            .iter()
            .any(|j| j.status == JobStatus::Compressing)
    }

    /// Remove finished jobs exceeding the retention limit.
    fn prune_finished(&mut self) {
        let finished: usize = self
            .queue
            .iter()
            .filter(|j| {
                matches!(
                    j.status,
                    JobStatus::Completed | JobStatus::Failed | JobStatus::Skipped
                )
            })
            .count();

        if finished <= MAX_FINISHED_JOBS {
            return;
        }

        let mut to_remove = finished - MAX_FINISHED_JOBS;
        self.queue.retain(|j| {
            if to_remove == 0 {
                return true;
            }
            if matches!(
                j.status,
                JobStatus::Completed | JobStatus::Failed | JobStatus::Skipped
            ) {
                to_remove -= 1;
                false
            } else {
                true
            }
        });
    }
}
