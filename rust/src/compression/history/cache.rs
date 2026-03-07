use super::CompressionHistoryEntry;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex, RwLock};

const MAX_HISTORY_ENTRIES: usize = 1000;
const PENDING_FLUSH_THRESHOLD: usize = 32;
const CACHE_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryCache {
    pub entries: Vec<CompressionHistoryEntry>,
    pub version: u32,
}

static HISTORY_CACHE: LazyLock<RwLock<Option<HistoryCache>>> = LazyLock::new(|| RwLock::new(None));
static LATEST_TIMESTAMP_INDEX: LazyLock<RwLock<Option<HashMap<String, u64>>>> =
    LazyLock::new(|| RwLock::new(None));
static PENDING_UPDATES: LazyLock<Mutex<Vec<CompressionHistoryEntry>>> =
    LazyLock::new(|| Mutex::new(Vec::new()));
static CACHE_DIRTY: LazyLock<Mutex<bool>> = LazyLock::new(|| Mutex::new(false));

fn default_cache() -> HistoryCache {
    HistoryCache {
        entries: Vec::new(),
        version: CACHE_VERSION,
    }
}

fn cache_path() -> PathBuf {
    let config_dir = dirs::config_dir()
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."));
    config_dir
        .join("pressplay")
        .join("compression_history.json")
}

fn normalize_game_path(path: &Path) -> String {
    crate::utils::normalize_path_key(path)
}

fn build_latest_timestamp_index(entries: &[CompressionHistoryEntry]) -> HashMap<String, u64> {
    let mut latest_by_path = HashMap::with_capacity(entries.len());
    for entry in entries {
        let key = normalize_game_path(Path::new(&entry.game_path));
        latest_by_path
            .entry(key)
            .and_modify(|current| {
                if entry.timestamp_ms > *current {
                    *current = entry.timestamp_ms;
                }
            })
            .or_insert(entry.timestamp_ms);
    }
    latest_by_path
}

/// Load cache from disk (lazy, on first access).
/// Uses double-checked locking to avoid TOCTOU race between read and write.
fn ensure_loaded() {
    {
        let guard = HISTORY_CACHE.read().unwrap();
        if guard.is_some() {
            return;
        }
    }

    // Acquire write lock and re-check to avoid double-load race.
    let mut cache_guard = HISTORY_CACHE.write().unwrap();
    if cache_guard.is_some() {
        return;
    }

    let path = cache_path();
    let cache = if path.exists() {
        std::fs::read_to_string(&path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_else(default_cache)
    } else {
        default_cache()
    };

    let latest_by_path = build_latest_timestamp_index(&cache.entries);
    *cache_guard = Some(cache);
    *LATEST_TIMESTAMP_INDEX.write().unwrap() = Some(latest_by_path);
}

/// Record a compression result.
pub fn record_compression(entry: CompressionHistoryEntry) {
    let mut pending = PENDING_UPDATES.lock().unwrap();
    pending.push(entry);

    if pending.len() >= PENDING_FLUSH_THRESHOLD {
        drop(pending);
        flush_pending();
    }
}

/// Flush pending entries into the in-memory cache.
fn flush_pending() {
    let mut pending = PENDING_UPDATES.lock().unwrap();
    if pending.is_empty() {
        return;
    }

    ensure_loaded();
    let mut cache_guard = HISTORY_CACHE.write().unwrap();
    let Some(cache) = cache_guard.as_mut() else {
        return;
    };

    cache.entries.extend(pending.drain(..));

    // Keep only newest entries by timestamp.
    if cache.entries.len() > MAX_HISTORY_ENTRIES {
        cache
            .entries
            .sort_by_key(|entry| std::cmp::Reverse(entry.timestamp_ms));
        cache.entries.truncate(MAX_HISTORY_ENTRIES);
    }

    *LATEST_TIMESTAMP_INDEX.write().unwrap() = Some(build_latest_timestamp_index(&cache.entries));
    *CACHE_DIRTY.lock().unwrap() = true;
}

/// Get historical compression statistics.
pub fn get_historical_stats() -> Vec<CompressionHistoryEntry> {
    flush_pending();
    ensure_loaded();

    let guard = HISTORY_CACHE.read().unwrap();
    guard
        .as_ref()
        .map(|cache| cache.entries.clone())
        .unwrap_or_default()
}

/// Return the most recent compression timestamp (milliseconds since Unix epoch)
/// for a specific game path, if available.
pub fn latest_compression_timestamp_ms(game_path: &Path) -> Option<u64> {
    flush_pending();
    ensure_loaded();

    let target = normalize_game_path(game_path);
    let guard = LATEST_TIMESTAMP_INDEX.read().unwrap();
    guard.as_ref()?.get(&target).copied()
}

/// Return the latest compression timestamps keyed by normalized game path.
pub fn latest_compression_timestamps_by_path() -> HashMap<String, u64> {
    flush_pending();
    ensure_loaded();

    let guard = LATEST_TIMESTAMP_INDEX.read().unwrap();
    guard.as_ref().cloned().unwrap_or_default()
}

/// Persist cache to disk.
pub fn persist_if_dirty() {
    // Pending entries can exist below threshold; flush first to avoid data loss.
    flush_pending();
    if !*CACHE_DIRTY.lock().unwrap() {
        return;
    }

    ensure_loaded();
    let guard = HISTORY_CACHE.read().unwrap();
    let Some(cache) = guard.as_ref() else {
        return;
    };

    let path = cache_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    if let Ok(json) = serde_json::to_string_pretty(cache) {
        if std::fs::write(&path, json).is_ok() {
            *CACHE_DIRTY.lock().unwrap() = false;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compression::algorithm::CompressionAlgorithm;
    use crate::compression::history::{ActualStats, EstimateSnapshot};

    fn unique_test_path(prefix: &str) -> PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        PathBuf::from(format!(r"C:\Games\{prefix}_{nanos}"))
    }

    fn history_entry(game_path: &Path, timestamp_ms: u64) -> CompressionHistoryEntry {
        CompressionHistoryEntry {
            game_path: game_path.to_string_lossy().into_owned(),
            game_name: "Test Game".to_string(),
            timestamp_ms,
            estimate: EstimateSnapshot {
                scanned_files: 0,
                sampled_bytes: 0,
                estimated_saved_bytes: 0,
            },
            actual_stats: ActualStats {
                original_bytes: 10_000,
                compressed_bytes: 8_000,
                actual_saved_bytes: 2_000,
                files_processed: 10,
            },
            algorithm: CompressionAlgorithm::Xpress8K,
            duration_ms: 100,
        }
    }

    #[test]
    fn latest_compression_timestamp_returns_none_for_unknown_path() {
        let path = unique_test_path("NoHistory");
        assert_eq!(
            latest_compression_timestamp_ms(&path),
            None,
            "unknown path should not produce timestamp"
        );
    }

    #[test]
    fn latest_compression_timestamp_returns_most_recent_match() {
        let path = unique_test_path("HistoryMatch");
        record_compression(history_entry(&path, 1000));
        record_compression(history_entry(&path, 2000));

        assert_eq!(latest_compression_timestamp_ms(&path), Some(2000));
    }

    #[test]
    fn latest_compression_timestamps_map_tracks_latest_value_by_normalized_path() {
        let path = unique_test_path("HistoryMap");
        record_compression(history_entry(&path, 1500));
        record_compression(history_entry(&path, 2500));

        let key = normalize_game_path(&path);
        let map = latest_compression_timestamps_by_path();
        assert_eq!(map.get(&key), Some(&2500));
    }
}
