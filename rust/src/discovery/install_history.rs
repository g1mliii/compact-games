use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
#[cfg(not(test))]
use std::sync::atomic::AtomicBool;
use std::sync::atomic::Ordering;
use std::sync::{LazyLock, RwLock};

const HISTORY_FILE_NAME: &str = "discovery_install_history.json";
const MAX_HISTORY_ENTRIES: usize = 16_384;
const MAX_HISTORY_AGE_MS: u64 = 90 * 24 * 60 * 60 * 1000;
/// Only run expiry pruning at most once per 5 minutes.
const PRUNE_INTERVAL_MS: u64 = 5 * 60 * 1000;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct HistoryEntry {
    max_logical_size: u64,
    updated_at_ms: u64,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
struct HistoryFile {
    #[serde(default)]
    entries: HashMap<String, HistoryEntry>,
}

#[cfg(not(test))]
static HISTORY_DIR_CREATED: AtomicBool = AtomicBool::new(false);
static HISTORY_DIRTY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static LAST_PRUNE_MS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
static HISTORY: LazyLock<RwLock<HistoryFile>> = LazyLock::new(|| RwLock::new(load_history_file()));

/// Return the largest logical size ever recorded for `path`, or `None` if no
/// history entry exists or the entry has expired.
pub fn max_observed_size(path: &Path) -> Option<u64> {
    let key = normalize_path_key(path);
    let now = unix_now_ms();
    with_history_read(|history| {
        history.entries.get(&key).and_then(|entry| {
            let age_ms = now.saturating_sub(entry.updated_at_ms);
            (age_ms <= MAX_HISTORY_AGE_MS).then_some(entry.max_logical_size)
        })
    })
}

/// Update the maximum observed logical size for `path`. The entry is only
/// written (and the dirty flag set) when `logical_size` exceeds the previously
/// recorded maximum.
pub fn record_authoritative_size(path: &Path, logical_size: u64) {
    if logical_size == 0 {
        return;
    }

    let key = normalize_path_key(path);
    let now = unix_now_ms();
    let changed = with_history_write(|history| {
        // Amortize expiry pruning: only run every PRUNE_INTERVAL_MS.
        let last_prune = LAST_PRUNE_MS.load(Ordering::Relaxed);
        if now.saturating_sub(last_prune) >= PRUNE_INTERVAL_MS {
            prune_expired_entries(history, now);
            LAST_PRUNE_MS.store(now, Ordering::Relaxed);
        }
        let existing = history.entries.get(&key).cloned();
        let next_max = existing.as_ref().map_or(logical_size, |entry| {
            entry.max_logical_size.max(logical_size)
        });
        let next_entry = HistoryEntry {
            max_logical_size: next_max,
            updated_at_ms: now,
        };

        // If the max size hasn't changed, skip the insert entirely: updating
        // updated_at_ms without setting the dirty flag would silently lose the
        // timestamp refresh on the next persist cycle.
        if existing
            .as_ref()
            .is_some_and(|entry| entry.max_logical_size == next_entry.max_logical_size)
        {
            return false;
        }

        prune_if_needed(history, &key);
        history.entries.insert(key, next_entry);
        true
    });

    if changed {
        HISTORY_DIRTY.store(true, Ordering::Relaxed);
    }
}

/// Remove the history entry for `path`, if present.
pub fn remove(path: &Path) {
    let key = normalize_path_key(path);
    let removed = with_history_write(|history| history.entries.remove(&key).is_some());
    if removed {
        HISTORY_DIRTY.store(true, Ordering::Relaxed);
    }
}

/// Flush the in-memory install history to disk if it has been modified. A
/// failed write re-sets the dirty flag so the next call will retry.
pub fn persist_if_dirty() {
    if !HISTORY_DIRTY.swap(false, Ordering::Relaxed) {
        return;
    }

    let snapshot = with_history_read(Clone::clone);
    if let Err(e) = save_history_file(&snapshot) {
        log::warn!("Failed to persist discovery install history: {e}");
        HISTORY_DIRTY.store(true, Ordering::Relaxed);
    }
}

/// Clear all in-memory install history and delete the on-disk file.
/// Primarily used in tests and for user-initiated resets.
pub fn clear_all() {
    with_history_write(|history| history.entries.clear());
    HISTORY_DIRTY.store(false, Ordering::Relaxed);
    LAST_PRUNE_MS.store(0, Ordering::Relaxed);

    if let Ok(path) = history_path() {
        match fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => log::warn!("Failed to remove discovery install-history file: {e}"),
        }
    }
}

fn load_history_file() -> HistoryFile {
    let Ok(path) = history_path() else {
        return HistoryFile::default();
    };
    let Ok(contents) = fs::read_to_string(path) else {
        return HistoryFile::default();
    };

    serde_json::from_str::<HistoryFile>(&contents).unwrap_or_else(|e| {
        log::warn!("Failed to parse discovery install history: {e}");
        HistoryFile::default()
    })
}

fn save_history_file(history: &HistoryFile) -> Result<(), Box<dyn std::error::Error>> {
    let path = history_path()?;
    let json = serde_json::to_string(history)?;
    crate::utils::atomic_write(&path, json.as_bytes())?;
    Ok(())
}

fn history_path() -> Result<PathBuf, std::io::Error> {
    #[cfg(test)]
    {
        use std::time::{SystemTime, UNIX_EPOCH};

        static TEST_CONFIG_DIR: LazyLock<PathBuf> = LazyLock::new(|| {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            std::env::temp_dir().join(format!(
                "compact-games-discovery-history-tests-{}-{now}",
                std::process::id()
            ))
        });

        fs::create_dir_all(&*TEST_CONFIG_DIR)?;
        Ok(TEST_CONFIG_DIR.join(HISTORY_FILE_NAME))
    }

    #[cfg(not(test))]
    {
        let config_dir = dirs::config_dir()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
        let compact_games_dir = config_dir.join("compact_games");

        if !HISTORY_DIR_CREATED.load(Ordering::Relaxed) {
            fs::create_dir_all(&compact_games_dir)?;
            HISTORY_DIR_CREATED.store(true, Ordering::Relaxed);
        }

        Ok(compact_games_dir.join(HISTORY_FILE_NAME))
    }
}

fn prune_expired_entries(history: &mut HistoryFile, now: u64) {
    history
        .entries
        .retain(|_, entry| now.saturating_sub(entry.updated_at_ms) <= MAX_HISTORY_AGE_MS);
}

fn prune_if_needed(history: &mut HistoryFile, incoming_key: &str) {
    if history.entries.len() < MAX_HISTORY_ENTRIES || history.entries.contains_key(incoming_key) {
        return;
    }

    let Some(evict_key) = history
        .entries
        .iter()
        .min_by_key(|(_, entry)| entry.updated_at_ms)
        .map(|(key, _)| key.clone())
    else {
        return;
    };

    history.entries.remove(&evict_key);
}

fn with_history_read<R>(f: impl FnOnce(&HistoryFile) -> R) -> R {
    match HISTORY.read() {
        Ok(guard) => f(&guard),
        Err(poisoned) => {
            log::warn!("Discovery install history lock poisoned (read); recovering");
            let guard = poisoned.into_inner();
            f(&guard)
        }
    }
}

fn with_history_write<R>(f: impl FnOnce(&mut HistoryFile) -> R) -> R {
    match HISTORY.write() {
        Ok(mut guard) => f(&mut guard),
        Err(poisoned) => {
            log::warn!("Discovery install history lock poisoned (write); recovering");
            let mut guard = poisoned.into_inner();
            f(&mut guard)
        }
    }
}

fn normalize_path_key(path: &Path) -> String {
    crate::utils::normalize_path_key(path)
}

fn unix_now_ms() -> u64 {
    crate::utils::unix_now_ms()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::discovery::test_sync::lock_discovery_test;
    use std::path::Path;

    #[test]
    fn remove_clears_recorded_size_for_path() {
        let _guard = lock_discovery_test();
        let path = Path::new(r"C:\Games\remnant_test");

        record_authoritative_size(path, 5 * 1024 * 1024 * 1024);
        assert_eq!(max_observed_size(path), Some(5 * 1024 * 1024 * 1024));

        remove(path);

        assert_eq!(max_observed_size(path), None);
    }
}
