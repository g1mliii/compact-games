//! FRB-compatible automation type wrappers.
//!
//! These thin wrappers use only primitive types that FRB can serialize
//! across the FFI boundary for automation-related data.

use std::time::UNIX_EPOCH;

use thiserror::Error;

use super::types::FrbCompressionAlgorithm;

// ── Automation errors ────────────────────────────────────────────────

/// FRB-compatible automation lifecycle errors.
#[derive(Debug, Error)]
pub enum FrbAutomationError {
    #[error("Auto-compression is already running")]
    AlreadyRunning,
    #[error("Auto-compression is not running")]
    NotRunning,
    #[error("Failed to start auto-compression: {message}")]
    StartFailed { message: String },
    #[error("Failed to stop auto-compression: {message}")]
    StopFailed { message: String },
    #[error("Failed to update automation config: {message}")]
    ConfigUpdateFailed { message: String },
}

// ── Watcher events ───────────────────────────────────────────────────

/// Watcher events sent to Flutter via stream.
#[derive(Debug, Clone)]
pub enum FrbWatcherEvent {
    GameInstalled {
        path: String,
        game_name: Option<String>,
    },
    GameModified {
        path: String,
        game_name: Option<String>,
    },
    GameUninstalled {
        path: String,
        game_name: Option<String>,
    },
}

impl From<crate::automation::watcher::WatchEvent> for FrbWatcherEvent {
    fn from(e: crate::automation::watcher::WatchEvent) -> Self {
        match e {
            crate::automation::watcher::WatchEvent::GameInstalled { path, game_name } => {
                Self::GameInstalled {
                    path: path.to_string_lossy().into_owned(),
                    game_name,
                }
            }
            crate::automation::watcher::WatchEvent::GameModified { path, game_name } => {
                Self::GameModified {
                    path: path.to_string_lossy().into_owned(),
                    game_name,
                }
            }
            crate::automation::watcher::WatchEvent::GameUninstalled { path, game_name } => {
                Self::GameUninstalled {
                    path: path.to_string_lossy().into_owned(),
                    game_name,
                }
            }
        }
    }
}

// ── Job types ────────────────────────────────────────────────────────

/// Automation job status for Flutter display.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrbAutomationJobStatus {
    Pending,
    WaitingForSettle,
    WaitingForIdle,
    Compressing,
    Completed,
    Failed,
    Skipped,
}

impl From<crate::automation::scheduler::JobStatus> for FrbAutomationJobStatus {
    fn from(s: crate::automation::scheduler::JobStatus) -> Self {
        match s {
            crate::automation::scheduler::JobStatus::Pending => Self::Pending,
            crate::automation::scheduler::JobStatus::WaitingForSettle => Self::WaitingForSettle,
            crate::automation::scheduler::JobStatus::WaitingForIdle => Self::WaitingForIdle,
            crate::automation::scheduler::JobStatus::Compressing => Self::Compressing,
            crate::automation::scheduler::JobStatus::Completed => Self::Completed,
            crate::automation::scheduler::JobStatus::Failed => Self::Failed,
            crate::automation::scheduler::JobStatus::Skipped => Self::Skipped,
        }
    }
}

/// Automation job kind for Flutter display.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrbAutomationJobKind {
    NewInstall,
    Reconcile,
    Opportunistic,
}

impl From<crate::automation::scheduler::JobKind> for FrbAutomationJobKind {
    fn from(k: crate::automation::scheduler::JobKind) -> Self {
        match k {
            crate::automation::scheduler::JobKind::NewInstall => Self::NewInstall,
            crate::automation::scheduler::JobKind::Reconcile => Self::Reconcile,
            crate::automation::scheduler::JobKind::Opportunistic => Self::Opportunistic,
        }
    }
}

/// A single automation job for Flutter display.
#[derive(Debug, Clone)]
pub struct FrbAutomationJob {
    pub game_path: String,
    pub game_name: Option<String>,
    pub kind: FrbAutomationJobKind,
    pub status: FrbAutomationJobStatus,
    pub queued_at_ms: i64,
    pub started_at_ms: Option<i64>,
    pub error: Option<String>,
}

impl From<crate::automation::scheduler::AutomationJob> for FrbAutomationJob {
    fn from(j: crate::automation::scheduler::AutomationJob) -> Self {
        Self {
            game_path: j.game_path.to_string_lossy().into_owned(),
            game_name: j.game_name,
            kind: j.kind.into(),
            status: j.status.into(),
            queued_at_ms: j
                .queued_at
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0),
            started_at_ms: j.started_at.and_then(|t| {
                t.duration_since(UNIX_EPOCH)
                    .ok()
                    .map(|d| d.as_millis() as i64)
            }),
            error: j.error,
        }
    }
}

// ── Scheduler state ──────────────────────────────────────────────────

/// Scheduler state for Flutter display.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrbSchedulerState {
    Idle,
    Settling,
    WaitingForIdle,
    SafetyCheck,
    Compressing,
    Paused,
    Backoff,
}

impl From<crate::automation::scheduler::SchedulerState> for FrbSchedulerState {
    fn from(s: crate::automation::scheduler::SchedulerState) -> Self {
        match s {
            crate::automation::scheduler::SchedulerState::WaitingForEvents => Self::Idle,
            crate::automation::scheduler::SchedulerState::WaitingForSettle => Self::Settling,
            crate::automation::scheduler::SchedulerState::WaitingForIdle => Self::WaitingForIdle,
            crate::automation::scheduler::SchedulerState::SafetyCheck => Self::SafetyCheck,
            crate::automation::scheduler::SchedulerState::Compressing => Self::Compressing,
            crate::automation::scheduler::SchedulerState::Paused => Self::Paused,
            crate::automation::scheduler::SchedulerState::Backoff => Self::Backoff,
        }
    }
}

// ── Configuration ────────────────────────────────────────────────────

/// Configuration pushed from Flutter settings to Rust automation.
#[derive(Debug, Clone)]
pub struct FrbAutomationConfig {
    pub cpu_threshold_percent: f32,
    pub idle_duration_seconds: u64,
    pub cooldown_seconds: u64,
    pub watch_paths: Vec<String>,
    pub excluded_paths: Vec<String>,
    pub algorithm: FrbCompressionAlgorithm,
}

/// Watcher diagnostics for Flutter display.
#[derive(Debug, Clone)]
pub struct FrbWatcherDiagnostics {
    pub is_watching: bool,
    pub watched_path_count: u32,
    pub queue_depth: u32,
    pub last_error: Option<String>,
}
