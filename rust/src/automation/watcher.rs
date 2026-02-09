use std::path::PathBuf;
use std::time::Duration;

/// Events emitted by the game directory watcher.
#[derive(Debug, Clone)]
pub enum WatchEvent {
    /// A new game folder was detected.
    GameInstalled { path: PathBuf },
    /// A game folder was removed.
    GameUninstalled { path: PathBuf },
    /// Files within a game folder changed (update/patch).
    GameModified { path: PathBuf },
}

/// Configuration for the directory watcher.
pub struct WatcherConfig {
    /// Directories to monitor for game installations.
    pub watch_paths: Vec<PathBuf>,
    /// Cooldown after detecting a new installation before compressing.
    pub cooldown: Duration,
}

impl Default for WatcherConfig {
    fn default() -> Self {
        Self {
            watch_paths: Vec::new(),
            cooldown: Duration::from_secs(300), // 5 minutes
        }
    }
}

/// Watches game directories for installation/removal events.
///
/// Uses the `notify` crate for cross-platform file system notifications.
/// Debounces events and applies a cooldown period to allow installations
/// to complete before triggering compression.
pub struct GameWatcher {
    _config: WatcherConfig,
    // TODO: Phase 7 implementation
    // - notify::RecommendedWatcher instance
    // - crossbeam_channel sender/receiver for events
    // - debounce timer
}

impl GameWatcher {
    pub fn new(config: WatcherConfig) -> Self {
        Self { _config: config }
    }

    /// Start watching configured directories.
    pub fn start(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        // TODO: Phase 7 implementation
        // 1. Create notify watcher
        // 2. Add watch_paths
        // 3. Spawn event processing loop
        log::info!("GameWatcher::start (not yet implemented)");
        Ok(())
    }

    /// Stop watching.
    pub fn stop(&mut self) {
        // TODO: Phase 7 implementation
        log::info!("GameWatcher::stop (not yet implemented)");
    }
}
