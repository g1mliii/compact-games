//! Automation API exposed to Flutter via FRB.
//!
//! Phase 5 exposes start/stop lifecycle entry points with bounded,
//! stoppable background work. Full compression orchestration remains
//! a Phase 7 concern.

use std::sync::mpsc::{channel, RecvTimeoutError, Sender};
use std::sync::{Mutex, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use flutter_rust_bridge::frb;

use super::types::FrbAutomationError;
use crate::automation::idle::IdleDetector;

struct ActiveAutoCompression {
    stop_tx: Sender<()>,
    handle: JoinHandle<()>,
}

static ACTIVE_AUTO: OnceLock<Mutex<Option<ActiveAutoCompression>>> = OnceLock::new();

fn active_auto_lock() -> &'static Mutex<Option<ActiveAutoCompression>> {
    ACTIVE_AUTO.get_or_init(|| Mutex::new(None))
}

/// Start auto-compression background service.
///
/// The worker is single-instance and can be stopped via `stop_auto_compression`.
pub fn start_auto_compression() -> Result<(), FrbAutomationError> {
    let mut guard = active_auto_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("AUTO compression lock poisoned during start; recovering");
        poisoned.into_inner()
    });

    if guard.is_some() {
        return Err(FrbAutomationError::AlreadyRunning);
    }

    let (stop_tx, stop_rx) = channel::<()>();
    let handle = thread::Builder::new()
        .name("pressplay-auto-compression".to_owned())
        .spawn(move || {
            auto_loop(stop_rx);
        })
        .map_err(|e| FrbAutomationError::StartFailed {
            message: e.to_string(),
        })?;

    *guard = Some(ActiveAutoCompression { stop_tx, handle });
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
    active
        .handle
        .join()
        .map_err(|_| FrbAutomationError::StopFailed {
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

fn auto_loop(stop_rx: std::sync::mpsc::Receiver<()>) {
    let mut idle_detector = IdleDetector::default();

    loop {
        match stop_rx.recv_timeout(Duration::from_secs(2)) {
            Ok(()) | Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {
                if idle_detector.is_idle() {
                    log::debug!(
                        "Auto-compression worker: idle detected; scheduler is pending Phase 7"
                    );
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stop_if_running() {
        if is_auto_compression_running() {
            let _ = stop_auto_compression();
        }
    }

    #[test]
    fn auto_compression_start_stop_roundtrip() {
        stop_if_running();
        start_auto_compression().expect("start should succeed");
        assert!(is_auto_compression_running());
        stop_auto_compression().expect("stop should succeed");
        assert!(!is_auto_compression_running());
    }

    #[test]
    fn auto_compression_rejects_double_start() {
        stop_if_running();
        start_auto_compression().expect("first start should succeed");
        let second = start_auto_compression();
        assert!(matches!(second, Err(FrbAutomationError::AlreadyRunning)));
        stop_auto_compression().expect("stop should succeed");
    }
}
