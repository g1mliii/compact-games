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
        .join("compact_games")
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
    evict_stale_discovery_metadata(&entry.game_path);

    // Keep the latest-timestamp index fresh so read-path consumers
    // (discovery cache/index lookup, watcher classification) can skip
    // flushing pending writes to see this entry.
    ensure_loaded();
    {
        let mut index_guard = LATEST_TIMESTAMP_INDEX.write().unwrap();
        if let Some(index) = index_guard.as_mut() {
            let key = normalize_game_path(Path::new(&entry.game_path));
            index
                .entry(key)
                .and_modify(|current| {
                    if entry.timestamp_ms > *current {
                        *current = entry.timestamp_ms;
                    }
                })
                .or_insert(entry.timestamp_ms);
        }
    }

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
///
/// `record_compression` keeps the timestamp index fresh synchronously, so this
/// read path stays lock-light and safe to call from discovery/watcher hot paths.
pub fn latest_compression_timestamp_ms(game_path: &Path) -> Option<u64> {
    ensure_loaded();

    let target = normalize_game_path(game_path);
    let guard = LATEST_TIMESTAMP_INDEX.read().unwrap();
    guard.as_ref()?.get(&target).copied()
}

/// Return the latest compression timestamps keyed by normalized game path.
pub fn latest_compression_timestamps_by_path() -> HashMap<String, u64> {
    ensure_loaded();

    let guard = LATEST_TIMESTAMP_INDEX.read().unwrap();
    guard.as_ref().cloned().unwrap_or_default()
}

/// True when a compression record for `path` is newer than the given
/// metadata timestamp. Used by discovery cache/index lookups to drop
/// entries whose compression state is now out of date.
pub fn is_newer_than(path: &Path, metadata_updated_at_ms: u64) -> bool {
    latest_compression_timestamp_ms(path)
        .is_some_and(|last_compressed_ms| last_compressed_ms > metadata_updated_at_ms)
}

/// Borrow the latest compression timestamp index without cloning it.
pub fn with_latest_compression_timestamps_by_path<R>(
    f: impl FnOnce(&HashMap<String, u64>) -> R,
) -> R {
    ensure_loaded();

    let guard = LATEST_TIMESTAMP_INDEX.read().unwrap();
    let empty = HashMap::new();
    match guard.as_ref() {
        Some(index) => f(index),
        None => f(&empty),
    }
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
        if crate::utils::atomic_write(&path, json.as_bytes()).is_ok() {
            *CACHE_DIRTY.lock().unwrap() = false;
            persist_discovery_metadata_if_dirty();
        }
    }
}

fn evict_stale_discovery_metadata(game_path: &str) {
    let path = Path::new(game_path);
    evict_stale_discovery_metadata_for_path(path);

    let content_path = path.join("Content");
    if content_path.is_dir() {
        evict_stale_discovery_metadata_for_path(&content_path);
    }
}

fn evict_stale_discovery_metadata_for_path(path: &Path) {
    crate::discovery::cache::remove(path);
    crate::discovery::index::remove(path);
    crate::discovery::change_feed::remove(path);
}

fn persist_discovery_metadata_if_dirty() {
    crate::discovery::cache::persist_if_dirty();
    crate::discovery::index::persist_if_dirty();
    crate::discovery::change_feed::persist_if_dirty();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compression::algorithm::CompressionAlgorithm;
    use crate::compression::history::{ActualStats, EstimateSnapshot};
    use crate::discovery::cache::{self as discovery_cache, CachedGameStats};
    use crate::discovery::index as discovery_index;
    use crate::discovery::platform::{GameInfo, Platform};
    use crate::discovery::test_sync::lock_discovery_test;

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

    #[test]
    fn record_compression_evicts_stale_discovery_metadata_for_game_path() {
        let _guard = lock_discovery_test();
        discovery_cache::clear_all();
        discovery_index::clear_all();

        let dir = tempfile::TempDir::new().unwrap();
        let game_path = dir.path();
        let token = discovery_cache::compute_change_token(game_path, false);
        discovery_cache::upsert(
            game_path,
            token.clone(),
            CachedGameStats::from_parts(10_000, 8_000, true, false),
        );
        discovery_index::upsert(
            game_path,
            token.clone(),
            &GameInfo {
                name: "Cached Game".to_owned(),
                path: game_path.to_path_buf(),
                platform: Platform::Application,
                size_bytes: 10_000,
                compressed_size: Some(8_000),
                is_compressed: true,
                is_directstorage: false,
                is_unsupported: false,
                excluded: false,
                steam_app_id: None,
                last_played: None,
            },
        );

        record_compression(history_entry(game_path, 1_700_000_123_456));

        assert!(discovery_cache::lookup_stale(game_path).is_none());
        assert!(discovery_index::lookup(game_path, &token).is_none());
    }
}
