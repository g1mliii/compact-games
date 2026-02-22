//! Type definitions for the automation scheduler.

use std::collections::HashSet;
use std::path::PathBuf;
use std::time::SystemTime;

use serde::{Deserialize, Serialize};

/// Maximum number of jobs in the queue. Oldest non-active dropped on overflow.
pub const MAX_QUEUE_SIZE: usize = 64;

/// Maximum finished jobs retained for UI display.
pub const MAX_FINISHED_JOBS: usize = 8;

/// Maximum backoff duration (30 minutes).
pub const MAX_BACKOFF: std::time::Duration = std::time::Duration::from_secs(30 * 60);

/// Initial backoff duration (1 minute).
pub const INITIAL_BACKOFF: std::time::Duration = std::time::Duration::from_secs(60);

/// Scheduler state machine states.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SchedulerState {
    WaitingForEvents,
    WaitingForSettle,
    WaitingForIdle,
    SafetyCheck,
    Compressing,
    Paused,
    Backoff,
}

/// What kind of automation job this is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum JobKind {
    NewInstall,
    Reconcile,
    Opportunistic,
}

/// Status of a single automation job.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum JobStatus {
    Pending,
    WaitingForSettle,
    WaitingForIdle,
    Compressing,
    Completed,
    Failed,
    Skipped,
}

/// A single automation compression job.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationJob {
    pub game_path: PathBuf,
    pub game_name: Option<String>,
    pub kind: JobKind,
    pub status: JobStatus,
    pub idempotency_key: String,
    pub queued_at: SystemTime,
    pub started_at: Option<SystemTime>,
    pub error: Option<String>,
}

/// Actions the scheduler wants the auto_loop to perform.
#[derive(Debug)]
pub enum SchedulerAction {
    /// Execute a compression job.
    Compress(AutomationJob),
    /// Persist the journal to disk.
    Persist,
}

/// Configuration for the scheduler.
pub struct SchedulerConfig {
    pub cooldown: std::time::Duration,
    pub excluded_paths: HashSet<String>,
    pub watch_paths: Vec<PathBuf>,
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        Self {
            cooldown: std::time::Duration::from_secs(300),
            excluded_paths: HashSet::new(),
            watch_paths: Vec::new(),
        }
    }
}
