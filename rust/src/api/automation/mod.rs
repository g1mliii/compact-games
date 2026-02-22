//! Automation API exposed to Flutter via FRB.
//!
//! Manages the auto-compression lifecycle: start/stop, watcher events,
//! scheduler state, and automation queue streaming to Flutter.

mod worker;

use std::sync::mpsc::{channel, Sender};
use std::sync::{Mutex, OnceLock};
use std::thread::{self, JoinHandle};

use flutter_rust_bridge::frb;

use super::automation_types::{
    FrbAutomationConfig, FrbAutomationError, FrbAutomationJob, FrbSchedulerState,
    FrbWatcherDiagnostics, FrbWatcherEvent,
};
use crate::frb_generated::StreamSink;

struct ActiveAutoCompression {
    stop_tx: Sender<()>,
    config_tx: Sender<FrbAutomationConfig>,
    handle: JoinHandle<()>,
}

/// Shared state snapshot updated by the auto_loop, read by sync getters.
pub(super) struct SharedAutoState {
    pub scheduler_state: FrbSchedulerState,
    pub queue: Vec<FrbAutomationJob>,
    pub watched_path_count: u32,
    pub queue_depth: u32,
    pub last_error: Option<String>,
}

impl Default for SharedAutoState {
    fn default() -> Self {
        Self {
            scheduler_state: FrbSchedulerState::Idle,
            queue: Vec::new(),
            watched_path_count: 0,
            queue_depth: 0,
            last_error: None,
        }
    }
}

static ACTIVE_AUTO: OnceLock<Mutex<Option<ActiveAutoCompression>>> = OnceLock::new();
static SHARED_STATE: OnceLock<Mutex<SharedAutoState>> = OnceLock::new();
static AUTO_STATUS_SINKS: OnceLock<Mutex<Vec<StreamSink<bool>>>> = OnceLock::new();
static WATCHER_EVENT_SINKS: OnceLock<Mutex<Vec<StreamSink<FrbWatcherEvent>>>> = OnceLock::new();
static SCHEDULER_STATE_SINKS: OnceLock<Mutex<Vec<StreamSink<FrbSchedulerState>>>> = OnceLock::new();
static AUTOMATION_QUEUE_SINKS: OnceLock<Mutex<Vec<StreamSink<Vec<FrbAutomationJob>>>>> =
    OnceLock::new();

const MAX_STREAM_SINKS: usize = 32;

fn active_auto_lock() -> &'static Mutex<Option<ActiveAutoCompression>> {
    ACTIVE_AUTO.get_or_init(|| Mutex::new(None))
}

pub(super) fn shared_state_lock() -> &'static Mutex<SharedAutoState> {
    SHARED_STATE.get_or_init(|| Mutex::new(SharedAutoState::default()))
}

pub(super) fn auto_status_sinks_lock() -> &'static Mutex<Vec<StreamSink<bool>>> {
    AUTO_STATUS_SINKS.get_or_init(|| Mutex::new(Vec::new()))
}

pub(super) fn watcher_event_sinks_lock() -> &'static Mutex<Vec<StreamSink<FrbWatcherEvent>>> {
    WATCHER_EVENT_SINKS.get_or_init(|| Mutex::new(Vec::new()))
}

pub(super) fn scheduler_state_sinks_lock() -> &'static Mutex<Vec<StreamSink<FrbSchedulerState>>> {
    SCHEDULER_STATE_SINKS.get_or_init(|| Mutex::new(Vec::new()))
}

pub(super) fn automation_queue_sinks_lock() -> &'static Mutex<Vec<StreamSink<Vec<FrbAutomationJob>>>>
{
    AUTOMATION_QUEUE_SINKS.get_or_init(|| Mutex::new(Vec::new()))
}

// ── Public FRB API ──────────────────────────────────────────────────

/// Start auto-compression background service.
pub fn start_auto_compression() -> Result<(), FrbAutomationError> {
    let mut guard = active_auto_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("AUTO compression lock poisoned during start; recovering");
        poisoned.into_inner()
    });

    if guard.is_some() {
        return Err(FrbAutomationError::AlreadyRunning);
    }

    let (stop_tx, stop_rx) = channel::<()>();
    let (config_tx, config_rx) = channel::<FrbAutomationConfig>();

    let handle = thread::Builder::new()
        .name("pressplay-auto-compression".to_owned())
        .spawn(move || {
            worker::auto_loop(stop_rx, config_rx);
        })
        .map_err(|e| FrbAutomationError::StartFailed {
            message: e.to_string(),
        })?;

    *guard = Some(ActiveAutoCompression {
        stop_tx,
        config_tx,
        handle,
    });
    drop(guard);
    worker::broadcast_auto_status(true);
    Ok(())
}

/// Stop auto-compression background service.
#[frb(sync)]
pub fn stop_auto_compression() -> Result<(), FrbAutomationError> {
    let active = {
        let mut guard = active_auto_lock().lock().unwrap_or_else(|poisoned| {
            log::warn!("AUTO compression lock poisoned during stop; recovering");
            poisoned.into_inner()
        });
        guard.take()
    };

    let Some(active) = active else {
        return Err(FrbAutomationError::NotRunning);
    };

    let _ = active.stop_tx.send(());
    let join_result = active.handle.join();
    worker::broadcast_auto_status(false);
    join_result.map_err(|_| FrbAutomationError::StopFailed {
        message: "auto-compression thread panicked during shutdown".to_owned(),
    })?;

    Ok(())
}

/// Returns whether the auto-compression service is currently running.
#[frb(sync)]
pub fn is_auto_compression_running() -> bool {
    let guard = active_auto_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("AUTO compression lock poisoned during status check; recovering");
        poisoned.into_inner()
    });
    guard.is_some()
}

/// Subscribe to auto-compression running-state changes.
pub fn watch_auto_compression_status(sink: StreamSink<bool>) -> Result<(), FrbAutomationError> {
    let running = is_auto_compression_running();
    if sink.add(running).is_err() {
        return Ok(());
    }

    let mut guard = auto_status_sinks_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("AUTO status sinks lock poisoned during subscribe; recovering");
        poisoned.into_inner()
    });

    if guard.len() >= MAX_STREAM_SINKS {
        guard.remove(0);
    }
    guard.push(sink);
    Ok(())
}

/// Subscribe to watcher events.
pub fn watch_watcher_events(sink: StreamSink<FrbWatcherEvent>) -> Result<(), FrbAutomationError> {
    let mut guard = watcher_event_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Watcher event sinks lock poisoned during subscribe; recovering");
            poisoned.into_inner()
        });

    if guard.len() >= MAX_STREAM_SINKS {
        guard.remove(0);
    }
    guard.push(sink);
    Ok(())
}

/// Subscribe to scheduler state changes.
pub fn watch_scheduler_state(
    sink: StreamSink<FrbSchedulerState>,
) -> Result<(), FrbAutomationError> {
    let mut guard = scheduler_state_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Scheduler state sinks lock poisoned during subscribe; recovering");
            poisoned.into_inner()
        });

    if guard.len() >= MAX_STREAM_SINKS {
        guard.remove(0);
    }
    guard.push(sink);
    Ok(())
}

/// Subscribe to automation queue changes.
pub fn watch_automation_queue(
    sink: StreamSink<Vec<FrbAutomationJob>>,
) -> Result<(), FrbAutomationError> {
    let mut guard = automation_queue_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Automation queue sinks lock poisoned during subscribe; recovering");
            poisoned.into_inner()
        });

    if guard.len() >= MAX_STREAM_SINKS {
        guard.remove(0);
    }
    guard.push(sink);
    Ok(())
}

/// Get current automation queue snapshot from shared state.
#[frb(sync)]
pub fn get_automation_queue() -> Vec<FrbAutomationJob> {
    let guard = shared_state_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("Shared state lock poisoned during queue read; recovering");
        poisoned.into_inner()
    });
    guard.queue.clone()
}

/// Get current scheduler state from shared state.
#[frb(sync)]
pub fn get_scheduler_state() -> FrbSchedulerState {
    let guard = shared_state_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("Shared state lock poisoned during state read; recovering");
        poisoned.into_inner()
    });
    guard.scheduler_state
}

/// Push updated automation config to the running auto-compression service.
pub fn update_automation_config(config: FrbAutomationConfig) -> Result<(), FrbAutomationError> {
    let guard = active_auto_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("AUTO compression lock poisoned during config update; recovering");
        poisoned.into_inner()
    });

    if let Some(ref active) = *guard {
        active
            .config_tx
            .send(config)
            .map_err(|_| FrbAutomationError::ConfigUpdateFailed {
                message: "auto-compression thread is not receiving config updates".to_owned(),
            })?;
    }
    Ok(())
}

/// Get watcher diagnostics from shared state.
#[frb(sync)]
pub fn get_watcher_diagnostics() -> FrbWatcherDiagnostics {
    let guard = shared_state_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("Shared state lock poisoned during diagnostics read; recovering");
        poisoned.into_inner()
    });
    FrbWatcherDiagnostics {
        is_watching: is_auto_compression_running(),
        watched_path_count: guard.watched_path_count,
        queue_depth: guard.queue_depth,
        last_error: guard.last_error.clone(),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{LazyLock, Mutex};

    use super::*;

    static TEST_MUTEX: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

    fn stop_if_running() {
        if is_auto_compression_running() {
            let _ = stop_auto_compression();
        }
    }

    #[test]
    fn auto_compression_start_stop_roundtrip() {
        let _guard = TEST_MUTEX.lock().unwrap();
        stop_if_running();
        start_auto_compression().expect("start should succeed");
        assert!(is_auto_compression_running());
        stop_auto_compression().expect("stop should succeed");
        assert!(!is_auto_compression_running());
    }

    #[test]
    fn auto_compression_rejects_double_start() {
        let _guard = TEST_MUTEX.lock().unwrap();
        stop_if_running();
        start_auto_compression().expect("first start should succeed");
        let second = start_auto_compression();
        assert!(matches!(second, Err(FrbAutomationError::AlreadyRunning)));
        stop_auto_compression().expect("stop should succeed");
    }

    #[test]
    fn config_update_while_not_running_is_ok() {
        let _guard = TEST_MUTEX.lock().unwrap();
        stop_if_running();
        let result = update_automation_config(FrbAutomationConfig {
            cpu_threshold_percent: 15.0,
            idle_duration_seconds: 180,
            cooldown_seconds: 300,
            watch_paths: vec![],
            excluded_paths: vec![],
            algorithm: super::super::types::FrbCompressionAlgorithm::Xpress8K,
        });
        assert!(result.is_ok());
    }

    #[test]
    fn get_scheduler_state_returns_idle_when_not_running() {
        let _guard = TEST_MUTEX.lock().unwrap();
        stop_if_running();
        assert_eq!(get_scheduler_state(), FrbSchedulerState::Idle);
    }

    #[test]
    fn get_automation_queue_returns_empty_when_not_running() {
        let _guard = TEST_MUTEX.lock().unwrap();
        stop_if_running();
        assert!(get_automation_queue().is_empty());
    }
}
