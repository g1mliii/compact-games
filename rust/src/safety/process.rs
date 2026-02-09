use std::path::Path;
use std::time::{Duration, Instant};

use sysinfo::System;

/// Checks whether any process from a game directory is currently running.
///
/// Scans the process list for executables whose path starts with `game_path`.
/// Uses a cached `System` snapshot to avoid excessive overhead; the caller
/// should refresh periodically (e.g. every 5 seconds).
pub struct ProcessChecker {
    system: System,
    last_refresh: Instant,
    refresh_interval: Duration,
}

impl ProcessChecker {
    pub fn new() -> Self {
        let mut system = System::new();
        system.refresh_processes(sysinfo::ProcessesToUpdate::All, true);
        Self {
            system,
            last_refresh: Instant::now(),
            refresh_interval: Duration::from_secs(5),
        }
    }

    /// Returns `true` if any running process has an executable path
    /// inside `game_path`.
    pub fn is_game_running(&mut self, game_path: &Path) -> bool {
        self.maybe_refresh();

        for (_pid, process) in self.system.processes() {
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

    fn maybe_refresh(&mut self) {
        if self.last_refresh.elapsed() >= self.refresh_interval {
            self.system
                .refresh_processes(sysinfo::ProcessesToUpdate::All, true);
            self.last_refresh = Instant::now();
        }
    }
}

impl Default for ProcessChecker {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nonexistent_game_not_running() {
        let mut checker = ProcessChecker::new();
        assert!(!checker.is_game_running(Path::new(r"C:\__nonexistent_pressplay_test__")));
    }
}
