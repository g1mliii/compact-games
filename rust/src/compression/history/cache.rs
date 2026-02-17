use super::CompressionHistoryEntry;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
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

/// Load cache from disk (lazy, on first access).
fn ensure_loaded() {
    let guard = HISTORY_CACHE.read().unwrap();
    if guard.is_some() {
        return;
    }
    drop(guard);

    let path = cache_path();
    let cache = if path.exists() {
        std::fs::read_to_string(&path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_else(default_cache)
    } else {
        default_cache()
    };

    *HISTORY_CACHE.write().unwrap() = Some(cache);
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
