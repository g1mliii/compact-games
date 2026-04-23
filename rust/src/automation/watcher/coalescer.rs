//! Event coalescing and noise filtering for filesystem watch events.

use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use super::WatchEvent;

/// Event kind for coalescing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum WatchEventKind {
    Installed,
    Uninstalled,
    Modified,
}

/// Internal pending event for coalescing.
struct PendingEvent {
    path: PathBuf,
    kind: WatchEventKind,
    game_name: Option<String>,
    last_seen: Instant,
}

/// Coalesces rapid filesystem events into single events per path.
///
/// Pure logic component (no filesystem dependency), easily testable.
pub(crate) struct EventCoalescer {
    pending: HashMap<PathBuf, PendingEvent>,
    cooldown: Duration,
}

impl EventCoalescer {
    pub fn new(cooldown: Duration) -> Self {
        Self {
            pending: HashMap::new(),
            cooldown,
        }
    }

    /// Ingest a raw event. Inserts or updates the pending event for the path.
    pub fn ingest(&mut self, path: PathBuf, kind: WatchEventKind, game_name: Option<String>) {
        match self.pending.entry(path.clone()) {
            Entry::Occupied(mut e) => {
                let pending = e.get_mut();
                pending.last_seen = Instant::now();
                pending.kind = kind;
                if game_name.is_some() {
                    pending.game_name = game_name;
                }
            }
            Entry::Vacant(e) => {
                e.insert(PendingEvent {
                    path,
                    kind,
                    game_name,
                    last_seen: Instant::now(),
                });
            }
        }
    }

    /// Drain events whose cooldown has expired, returning settled events.
    pub fn drain_settled(&mut self) -> Vec<WatchEvent> {
        let now = Instant::now();
        let cooldown = self.cooldown;
        let mut settled = Vec::new();

        self.pending.retain(|_path, pending| {
            if now.duration_since(pending.last_seen) >= cooldown {
                // Take ownership of fields without cloning the whole PendingEvent
                settled.push(match pending.kind {
                    WatchEventKind::Installed => WatchEvent::GameInstalled {
                        path: std::mem::take(&mut pending.path),
                        game_name: pending.game_name.take(),
                    },
                    WatchEventKind::Uninstalled => WatchEvent::GameUninstalled {
                        path: std::mem::take(&mut pending.path),
                        game_name: pending.game_name.take(),
                    },
                    WatchEventKind::Modified => WatchEvent::GameModified {
                        path: std::mem::take(&mut pending.path),
                        game_name: pending.game_name.take(),
                    },
                });
                false // remove from map
            } else {
                true // keep
            }
        });

        settled
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub fn len(&self) -> usize {
        self.pending.len()
    }

    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.pending.is_empty()
    }
}

/// File extensions and names to ignore during watch events.
const NOISE_EXTENSIONS: &[&str] = &["tmp", "bak", "log", "crdownload", "partial"];
const NOISE_FILENAMES: &[&str] = &["desktop.ini", "thumbs.db", ".ds_store"];
const USER_STATE_DIR_NAMES: &[&str] = &[
    "save",
    "saves",
    "saved",
    "cfg",
    "config",
    "configs",
    "logs",
    "log",
    "cache",
    "shadercache",
];
const USER_STATE_EXTENSIONS: &[&str] = &["cfg", "vcfg", "ini", "sav", "save", "soc", "stats"];
const USER_STATE_SUFFIXES: &[&str] = &["_lastclouded"];

pub(crate) fn is_noise_path(path: &std::path::Path) -> bool {
    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
        let name_lower = name.to_ascii_lowercase();
        if NOISE_FILENAMES.iter().any(|n| name_lower == *n) {
            return true;
        }
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            if NOISE_EXTENSIONS.iter().any(|e| ext.eq_ignore_ascii_case(e)) {
                return true;
            }
        }
    }
    false
}

pub(crate) fn is_user_state_subpath(path: &std::path::Path) -> bool {
    if path.components().any(|component| {
        component
            .as_os_str()
            .to_str()
            .map(|segment| {
                let segment_lower = segment.to_ascii_lowercase();
                USER_STATE_DIR_NAMES
                    .iter()
                    .any(|name| segment_lower == *name)
            })
            .unwrap_or(false)
    }) {
        return true;
    }

    let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
        return false;
    };
    let name_lower = name.to_ascii_lowercase();

    if USER_STATE_SUFFIXES
        .iter()
        .any(|suffix| name_lower.ends_with(suffix))
    {
        return true;
    }

    path.extension()
        .and_then(|e| e.to_str())
        .map(|ext| {
            USER_STATE_EXTENSIONS
                .iter()
                .any(|allowed| ext.eq_ignore_ascii_case(allowed))
        })
        .unwrap_or(false)
}

/// Resolved game root for a filesystem event.
pub(crate) struct ResolvedGameFolder {
    pub path: PathBuf,
    pub matched_watch_root: PathBuf,
}

/// Given a filesystem event path and a set of watched directories,
/// determine the game folder.
pub(crate) fn resolve_game_folder(
    event_path: &Path,
    watch_paths: &[PathBuf],
) -> Option<ResolvedGameFolder> {
    for root in watch_paths {
        if let Ok(stripped) = event_path.strip_prefix(root) {
            if is_known_game_watch_root(root) {
                return Some(ResolvedGameFolder {
                    path: root.clone(),
                    matched_watch_root: root.clone(),
                });
            }
            if let Some(first_component) = stripped.components().next() {
                let game_folder = root.join(first_component);
                return Some(ResolvedGameFolder {
                    path: game_folder,
                    matched_watch_root: root.clone(),
                });
            }
            return Some(ResolvedGameFolder {
                path: root.clone(),
                matched_watch_root: root.clone(),
            });
        }
    }
    None
}

/// Extract a human-readable game name from a game folder path.
pub(crate) fn game_name_from_path(path: &Path) -> Option<String> {
    path.file_name()
        .and_then(|n| n.to_str())
        .map(|s| s.to_string())
}

fn is_known_game_watch_root(root: &Path) -> bool {
    crate::compression::history::latest_compression_timestamp_ms(root).is_some()
        || crate::discovery::cache::has_entry(root)
}
