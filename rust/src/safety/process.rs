//! Running game detection via process enumeration.
//!
//! Thread-safe: all public methods take `&self` via interior `Mutex`.
//! Only requests executable-path information from the OS, skipping
//! CPU, memory, and disk I/O queries for maximum performance.

use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};

fn exe_only_refresh() -> ProcessRefreshKind {
    ProcessRefreshKind::nothing().with_exe(UpdateKind::OnlyIfNotSet)
}

pub struct ProcessChecker {
    inner: Mutex<ProcessCheckerInner>,
}

struct ProcessCheckerInner {
    system: System,
    last_refresh: Instant,
    refresh_interval: Duration,
}

impl ProcessChecker {
    /// Create a new checker with the default 5-second refresh interval.
    pub fn new() -> Self {
        Self::with_interval(Duration::from_secs(5))
    }

    pub fn with_interval(refresh_interval: Duration) -> Self {
        let mut system = System::new();
        system.refresh_processes_specifics(ProcessesToUpdate::All, true, exe_only_refresh());
        Self {
            inner: Mutex::new(ProcessCheckerInner {
                system,
                last_refresh: Instant::now(),
                refresh_interval,
            }),
        }
    }

    pub fn is_game_running(&self, game_path: &Path) -> bool {
        let mut inner = match self.inner.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                log::warn!("ProcessChecker lock poisoned; recovering");
                poisoned.into_inner()
            }
        };

        inner.maybe_refresh();

        for (_pid, process) in inner.system.processes() {
            if let Some(exe_path) = process.exe() {
                if exe_path.starts_with(game_path) {
                    log::debug!(
                        "Game process detected: {} (pid {})",
                        exe_path.display(),
                        _pid
                    );
                    return true;
                }
            }
        }

        false
    }
}

impl Default for ProcessChecker {
    fn default() -> Self {
        Self::new()
    }
}

impl ProcessCheckerInner {
    fn maybe_refresh(&mut self) {
        if self.last_refresh.elapsed() >= self.refresh_interval {
            self.system.refresh_processes_specifics(
                ProcessesToUpdate::All,
                true,
                exe_only_refresh(),
            );
            self.last_refresh = Instant::now();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn nonexistent_game_not_running() {
        let checker = ProcessChecker::new();
        assert!(!checker.is_game_running(Path::new(r"C:\__nonexistent_pressplay_test__")));
    }

    #[test]
    fn checker_is_send_and_sync() {
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<ProcessChecker>();
    }

    #[test]
    fn checker_shareable_via_arc() {
        let checker = Arc::new(ProcessChecker::new());
        let checker2 = checker.clone();
        let handle = std::thread::spawn(move || {
            checker2.is_game_running(Path::new(r"C:\__nonexistent_pressplay_test__"))
        });
        let r1 = checker.is_game_running(Path::new(r"C:\__nonexistent_pressplay_test__"));
        let r2 = handle.join().unwrap();
        assert!(!r1);
        assert!(!r2);
    }

    #[test]
    fn custom_interval_respected() {
        let checker = ProcessChecker::with_interval(Duration::from_millis(50));
        assert!(!checker.is_game_running(Path::new(r"C:\__nonexistent__")));
        std::thread::sleep(Duration::from_millis(60));
        // Should trigger refresh without panic
        assert!(!checker.is_game_running(Path::new(r"C:\__nonexistent__")));
    }

    #[test]
    fn detects_own_process() {
        let checker = ProcessChecker::new();
        let exe = std::env::current_exe().unwrap();
        let parent = exe.parent().unwrap();
        assert!(
            checker.is_game_running(parent),
            "should detect test runner as a running process in {}",
            parent.display()
        );
    }
}
