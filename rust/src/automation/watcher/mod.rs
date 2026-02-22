//! File system watcher for game directory changes.
//!
//! Uses `notify` crate for OS-level file system notifications.
//! Events are coalesced with a configurable cooldown to batch rapid
//! filesystem writes (e.g., during game updates) into single events.

pub(crate) mod coalescer;

#[cfg(test)]
mod tests;

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Duration;

use crossbeam_channel::{bounded, Receiver, Sender, TrySendError};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};

use coalescer::{game_name_from_path, is_noise_path, resolve_game_folder};
use coalescer::{EventCoalescer, WatchEventKind};

/// Events emitted by the game directory watcher.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WatchEvent {
    /// A new game folder was detected.
    GameInstalled {
        path: PathBuf,
        game_name: Option<String>,
    },
    /// A game folder was removed.
    GameUninstalled {
        path: PathBuf,
        game_name: Option<String>,
    },
    /// Files within a game folder changed (update/patch).
    GameModified {
        path: PathBuf,
        game_name: Option<String>,
    },
}

impl WatchEvent {
    pub fn path(&self) -> &PathBuf {
        match self {
            WatchEvent::GameInstalled { path, .. }
            | WatchEvent::GameUninstalled { path, .. }
            | WatchEvent::GameModified { path, .. } => path,
        }
    }

    pub fn game_name(&self) -> Option<&str> {
        match self {
            WatchEvent::GameInstalled { game_name, .. }
            | WatchEvent::GameUninstalled { game_name, .. }
            | WatchEvent::GameModified { game_name, .. } => game_name.as_deref(),
        }
    }
}

/// Configuration for the directory watcher.
pub struct WatcherConfig {
    /// Directories to monitor for game installations.
    pub watch_paths: Vec<PathBuf>,
    /// Cooldown after detecting a change before emitting the coalesced event.
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
/// Coalesces events and applies a cooldown period to allow installations
/// to complete before triggering compression.
pub struct GameWatcher {
    config: WatcherConfig,
    watcher: Option<RecommendedWatcher>,
    stop_flag: Arc<AtomicBool>,
    worker_handle: Option<JoinHandle<()>>,
    event_tx: Option<Sender<WatchEvent>>,
    event_rx: Option<Receiver<WatchEvent>>,
}

impl GameWatcher {
    pub fn new(config: WatcherConfig) -> Self {
        Self {
            config,
            watcher: None,
            stop_flag: Arc::new(AtomicBool::new(false)),
            worker_handle: None,
            event_tx: None,
            event_rx: None,
        }
    }

    pub fn event_channel(&self) -> Option<&Receiver<WatchEvent>> {
        self.event_rx.as_ref()
    }

    pub fn start(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        if self.worker_handle.is_some() {
            return Err("Watcher already running".into());
        }

        if self.config.watch_paths.is_empty() {
            log::info!("GameWatcher::start: no watch paths configured");
            return Ok(());
        }

        self.stop_flag.store(false, Ordering::Relaxed);

        let (notify_tx, notify_rx) = bounded::<notify::Result<notify::Event>>(256);

        let watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
            let _ = notify_tx.try_send(event);
        })?;

        let (event_tx, event_rx) = bounded::<WatchEvent>(256);

        self.watcher = Some(watcher);
        self.event_tx = Some(event_tx.clone());
        self.event_rx = Some(event_rx);

        if let Some(ref mut w) = self.watcher {
            for path in &self.config.watch_paths {
                if path.exists() {
                    match w.watch(path, RecursiveMode::Recursive) {
                        Ok(()) => log::info!("Watching: {}", path.display()),
                        Err(e) => log::warn!("Failed to watch {}: {e}", path.display()),
                    }
                } else {
                    log::warn!("Watch path does not exist: {}", path.display());
                }
            }
        }

        let stop_flag = self.stop_flag.clone();
        let cooldown = self.config.cooldown;
        let watch_paths = self.config.watch_paths.clone();

        let handle = std::thread::Builder::new()
            .name("pressplay-watcher".to_owned())
            .spawn(move || {
                watcher_worker(notify_rx, event_tx, stop_flag, cooldown, watch_paths);
            })?;

        self.worker_handle = Some(handle);
        log::info!("GameWatcher started");
        Ok(())
    }

    pub fn stop(&mut self) {
        self.stop_flag.store(true, Ordering::Relaxed);
        self.watcher.take();

        if let Some(handle) = self.worker_handle.take() {
            let _ = handle.join();
        }

        self.event_tx.take();
        self.event_rx.take();
        log::info!("GameWatcher stopped");
    }

    pub fn is_running(&self) -> bool {
        self.worker_handle.is_some() && !self.stop_flag.load(Ordering::Relaxed)
    }

    pub fn watched_path_count(&self) -> usize {
        self.config.watch_paths.len()
    }

    /// Update the watch paths. Requires stop/start cycle.
    pub fn update_config(&mut self, config: WatcherConfig) {
        let was_running = self.is_running();
        if was_running {
            self.stop();
        }
        self.config = config;
        if was_running {
            if let Err(e) = self.start() {
                log::error!("Failed to restart watcher with new config: {e}");
            }
        }
    }
}

impl Drop for GameWatcher {
    fn drop(&mut self) {
        if self.worker_handle.is_some() {
            self.stop();
        }
    }
}

// ── Worker thread ────────────────────────────────────────────────────

fn watcher_worker(
    notify_rx: Receiver<notify::Result<notify::Event>>,
    event_tx: Sender<WatchEvent>,
    stop_flag: Arc<AtomicBool>,
    cooldown: Duration,
    watch_paths: Vec<PathBuf>,
) {
    let mut coalescer = EventCoalescer::new(cooldown);

    loop {
        if stop_flag.load(Ordering::Relaxed) {
            break;
        }

        match notify_rx.recv_timeout(Duration::from_millis(500)) {
            Ok(Ok(event)) => {
                process_notify_event(&event, &watch_paths, &mut coalescer);
            }
            Ok(Err(e)) => {
                log::warn!("Watcher error: {e}");
            }
            Err(crossbeam_channel::RecvTimeoutError::Timeout) => {}
            Err(crossbeam_channel::RecvTimeoutError::Disconnected) => {
                break;
            }
        }

        // Drain any additional buffered events (non-blocking)
        loop {
            match notify_rx.try_recv() {
                Ok(Ok(event)) => {
                    process_notify_event(&event, &watch_paths, &mut coalescer);
                }
                Ok(Err(e)) => {
                    log::warn!("Watcher error: {e}");
                }
                Err(_) => break,
            }
        }

        // Emit settled events
        for settled in coalescer.drain_settled() {
            match event_tx.try_send(settled) {
                Ok(()) => {}
                Err(TrySendError::Full(event)) => {
                    log::warn!(
                        "Watcher output channel full, dropping event for: {}",
                        event.path().display()
                    );
                }
                Err(TrySendError::Disconnected(_)) => {
                    return;
                }
            }
        }
    }
}

fn process_notify_event(
    event: &notify::Event,
    watch_paths: &[PathBuf],
    coalescer: &mut EventCoalescer,
) {
    for path in &event.paths {
        if is_noise_path(path) {
            continue;
        }

        let game_folder = match resolve_game_folder(path, watch_paths) {
            Some(f) => f,
            None => continue,
        };

        let game_name = game_name_from_path(&game_folder);

        let kind = match event.kind {
            notify::EventKind::Create(_) => {
                if path == &game_folder || path.parent() == Some(game_folder.as_path()) {
                    WatchEventKind::Installed
                } else {
                    WatchEventKind::Modified
                }
            }
            notify::EventKind::Remove(_) => {
                if path == &game_folder || path.parent() == Some(game_folder.as_path()) {
                    WatchEventKind::Uninstalled
                } else {
                    WatchEventKind::Modified
                }
            }
            notify::EventKind::Modify(_) => WatchEventKind::Modified,
            _ => continue,
        };

        coalescer.ingest(game_folder, kind, game_name);
    }
}
