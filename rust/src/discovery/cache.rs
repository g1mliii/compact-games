use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{LazyLock, Mutex, RwLock};
use std::time::UNIX_EPOCH;

use walkdir::WalkDir;

const CACHE_FILE_NAME: &str = "discovery_stats_cache.json";
const MAX_CACHE_ENTRIES: usize = 8_192;
const FLUSH_PENDING_THRESHOLD: usize = 256;
const TOKEN_PROBE_MAX_DEPTH: usize = 6;
const TOKEN_PROBE_MAX_FILES: usize = 96;
/// Maximum age (in ms) for a cache entry before it's considered stale
/// even when the change token matches. Forces periodic re-verification.
const MAX_CACHE_AGE_MS: u64 = 10 * 60 * 1000; // 10 minutes

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ChangeToken {
    pub root_mtime_ms: Option<u64>,
    pub child_count: u32,
    pub child_max_mtime_ms: Option<u64>,
    #[serde(default)]
    pub probe_file_count: Option<u32>,
    #[serde(default)]
    pub probe_total_size: Option<u64>,
    #[serde(default)]
    pub probe_max_mtime_ms: Option<u64>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CachedGameStats {
    pub logical_size: u64,
    pub physical_size: u64,
    pub is_compressed: bool,
    pub is_directstorage: bool,
    pub updated_at_ms: u64,
}

impl CachedGameStats {
    pub fn from_parts(
        logical_size: u64,
        physical_size: u64,
        is_compressed: bool,
        is_directstorage: bool,
    ) -> Self {
        Self {
            logical_size,
            physical_size,
            is_compressed,
            is_directstorage,
            updated_at_ms: unix_now_ms(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct CacheEntry {
    token: ChangeToken,
    stats: CachedGameStats,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
struct CacheFile {
    #[serde(default)]
    entries: HashMap<String, CacheEntry>,
}

#[derive(Debug, Default)]
struct PendingUpdates {
    entries: HashMap<String, CacheEntry>,
}

static CACHE_DIR_CREATED: AtomicBool = AtomicBool::new(false);
static CACHE_DIRTY: AtomicBool = AtomicBool::new(false);
static CACHE: LazyLock<RwLock<CacheFile>> = LazyLock::new(|| RwLock::new(load_cache_file()));
static PENDING_UPDATES: LazyLock<Mutex<PendingUpdates>> =
    LazyLock::new(|| Mutex::new(PendingUpdates::default()));

pub fn compute_change_token(path: &Path, include_probe: bool) -> ChangeToken {
    let root_mtime_ms = fs::metadata(path)
        .ok()
        .and_then(|m| metadata_modified_ms(&m));

    let mut child_count: u32 = 0;
    let mut child_max_mtime_ms: Option<u64> = None;

    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            child_count = child_count.saturating_add(1);
            let child_mtime = entry.metadata().ok().and_then(|m| metadata_modified_ms(&m));
            child_max_mtime_ms = max_optional_u64(child_max_mtime_ms, child_mtime);
        }
    }

    let (probe_file_count, probe_total_size, probe_max_mtime_ms) = if include_probe {
        let mut files_seen: u32 = 0;
        let mut total_size: u64 = 0;
        let mut max_mtime: Option<u64> = None;

        for entry in WalkDir::new(path)
            .max_depth(TOKEN_PROBE_MAX_DEPTH)
            .follow_links(false)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file())
        {
            if files_seen as usize >= TOKEN_PROBE_MAX_FILES {
                break;
            }
            if let Ok(metadata) = entry.metadata() {
                files_seen = files_seen.saturating_add(1);
                total_size = total_size.saturating_add(metadata.len());
                let mtime = metadata_modified_ms(&metadata);
                max_mtime = max_optional_u64(max_mtime, mtime);
            }
        }

        (Some(files_seen), Some(total_size), max_mtime)
    } else {
        (None, None, None)
    };

    ChangeToken {
        root_mtime_ms,
        child_count,
        child_max_mtime_ms,
        probe_file_count,
        probe_total_size,
        probe_max_mtime_ms,
    }
}

pub fn has_entry(path: &Path) -> bool {
    let key = normalize_path_key(path);
    if with_pending_read(|pending| pending.entries.contains_key(&key)) {
        return true;
    }
    with_cache_read(|cache| cache.entries.contains_key(&key))
}

pub fn lookup(path: &Path, token: &ChangeToken) -> Option<CachedGameStats> {
    lookup_inner(path, token, None)
}

/// Lookup with TTL enforcement. Returns `None` if the entry is older than
/// `max_age_ms`, forcing a re-scan even when the change token still matches.
pub fn lookup_with_ttl(
    path: &Path,
    token: &ChangeToken,
    max_age_ms: u64,
) -> Option<CachedGameStats> {
    lookup_inner(path, token, Some(max_age_ms))
}

/// Default TTL-aware lookup (10-minute max cache age).
pub fn lookup_fresh(path: &Path, token: &ChangeToken) -> Option<CachedGameStats> {
    lookup_with_ttl(path, token, MAX_CACHE_AGE_MS)
}

fn lookup_inner(
    path: &Path,
    token: &ChangeToken,
    max_age_ms: Option<u64>,
) -> Option<CachedGameStats> {
    let key = normalize_path_key(path);
    let now = unix_now_ms();

    let filter_entry = |entry: &&CacheEntry| -> bool {
        if entry.token != *token {
            return false;
        }
        if compression_history_is_newer(path, entry.stats.updated_at_ms) {
            return false;
        }
        if let Some(max_age) = max_age_ms {
            if now.saturating_sub(entry.stats.updated_at_ms) > max_age {
                return false;
            }
        }
        true
    };

    if let Some(stats) = with_pending_read(|pending| {
        pending
            .entries
            .get(&key)
            .filter(filter_entry)
            .map(|entry| entry.stats.clone())
    }) {
        return Some(stats);
    }

    with_cache_read(|cache| {
        cache
            .entries
            .get(&key)
            .filter(filter_entry)
            .map(|entry| entry.stats.clone())
    })
}

pub fn lookup_stale(path: &Path) -> Option<CachedGameStats> {
    let key = normalize_path_key(path);
    if let Some(stats) = with_pending_read(|pending| {
        pending.entries.get(&key).and_then(|entry| {
            (!compression_history_is_newer(path, entry.stats.updated_at_ms))
                .then(|| entry.stats.clone())
        })
    }) {
        return Some(stats);
    }
    with_cache_read(|cache| {
        cache.entries.get(&key).and_then(|entry| {
            (!compression_history_is_newer(path, entry.stats.updated_at_ms))
                .then(|| entry.stats.clone())
        })
    })
}

pub fn remove(path: &Path) {
    let key = normalize_path_key(path);
    let removed_pending = with_pending_write(|pending| pending.entries.remove(&key).is_some());
    let removed_cache = with_cache_write(|cache| cache.entries.remove(&key).is_some());
    if removed_pending || removed_cache {
        CACHE_DIRTY.store(true, Ordering::Relaxed);
    }
}

pub fn upsert(path: &Path, token: ChangeToken, stats: CachedGameStats) {
    let key = normalize_path_key(path);
    let should_flush = with_pending_write(|pending| {
        pending.entries.insert(key, CacheEntry { token, stats });
        pending.entries.len() >= FLUSH_PENDING_THRESHOLD
    });

    CACHE_DIRTY.store(true, Ordering::Relaxed);
    if should_flush {
        flush_pending_updates();
    }
}

pub fn persist_if_dirty() {
    // Best-effort persistence: concurrent `upsert` calls can set `CACHE_DIRTY = true`
    // after this swap and miss the current flush/save cycle. Those updates remain in
    // memory and are picked up by the next `persist_if_dirty` invocation.
    if !CACHE_DIRTY.swap(false, Ordering::Relaxed) {
        return;
    }

    flush_pending_updates();

    let snapshot = with_cache_read(Clone::clone);
    if let Err(e) = save_cache_file(&snapshot) {
        log::warn!("Failed to persist discovery stats cache: {e}");
        CACHE_DIRTY.store(true, Ordering::Relaxed);
    }
}

pub fn clear_all() {
    with_pending_write(|pending| pending.entries.clear());
    with_cache_write(|cache| cache.entries.clear());
    CACHE_DIRTY.store(false, Ordering::Relaxed);

    if let Ok(path) = cache_path() {
        match fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => log::warn!("Failed to remove discovery cache file: {e}"),
        }
    }
}

fn flush_pending_updates() {
    let updates = with_pending_write(|pending| std::mem::take(&mut pending.entries));
    if updates.is_empty() {
        return;
    }

    with_cache_write(|cache| {
        for (key, entry) in updates {
            prune_if_needed(cache, &key);
            cache.entries.insert(key, entry);
        }
    });
}

fn prune_if_needed(cache: &mut CacheFile, incoming_key: &str) {
    if cache.entries.len() < MAX_CACHE_ENTRIES || cache.entries.contains_key(incoming_key) {
        return;
    }

    let Some(evict_key) = cache
        .entries
        .iter()
        .min_by_key(|(_, entry)| entry.stats.updated_at_ms)
        .map(|(key, _)| key.clone())
    else {
        return;
    };

    cache.entries.remove(&evict_key);
}

fn with_cache_read<R>(f: impl FnOnce(&CacheFile) -> R) -> R {
    match CACHE.read() {
        Ok(guard) => f(&guard),
        Err(poisoned) => {
            log::warn!("Discovery cache lock poisoned (read); recovering");
            let guard = poisoned.into_inner();
            f(&guard)
        }
    }
}

fn with_cache_write<R>(f: impl FnOnce(&mut CacheFile) -> R) -> R {
    match CACHE.write() {
        Ok(mut guard) => f(&mut guard),
        Err(poisoned) => {
            log::warn!("Discovery cache lock poisoned (write); recovering");
            let mut guard = poisoned.into_inner();
            f(&mut guard)
        }
    }
}

fn with_pending_read<R>(f: impl FnOnce(&PendingUpdates) -> R) -> R {
    match PENDING_UPDATES.lock() {
        Ok(guard) => f(&guard),
        Err(poisoned) => {
            log::warn!("Discovery pending-updates lock poisoned (read); recovering");
            let guard = poisoned.into_inner();
            f(&guard)
        }
    }
}

fn with_pending_write<R>(f: impl FnOnce(&mut PendingUpdates) -> R) -> R {
    match PENDING_UPDATES.lock() {
        Ok(mut guard) => f(&mut guard),
        Err(poisoned) => {
            log::warn!("Discovery pending-updates lock poisoned (write); recovering");
            let mut guard = poisoned.into_inner();
            f(&mut guard)
        }
    }
}

fn load_cache_file() -> CacheFile {
    let Ok(path) = cache_path() else {
        return CacheFile::default();
    };

    let Ok(contents) = fs::read_to_string(path) else {
        return CacheFile::default();
    };

    serde_json::from_str::<CacheFile>(&contents).unwrap_or_else(|e| {
        log::warn!("Failed to parse discovery stats cache: {e}");
        CacheFile::default()
    })
}

fn save_cache_file(cache: &CacheFile) -> Result<(), Box<dyn std::error::Error>> {
    let path = cache_path()?;
    let json = serde_json::to_string(cache)?;
    crate::utils::atomic_write(&path, json.as_bytes())?;
    Ok(())
}

fn cache_path() -> Result<PathBuf, std::io::Error> {
    let config_dir = dirs::config_dir()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
    let compact_games_dir = config_dir.join("compact_games");

    if !CACHE_DIR_CREATED.load(Ordering::Relaxed) {
        fs::create_dir_all(&compact_games_dir)?;
        CACHE_DIR_CREATED.store(true, Ordering::Relaxed);
    }

    Ok(compact_games_dir.join(CACHE_FILE_NAME))
}

fn metadata_modified_ms(metadata: &fs::Metadata) -> Option<u64> {
    metadata
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
}

fn max_optional_u64(lhs: Option<u64>, rhs: Option<u64>) -> Option<u64> {
    match (lhs, rhs) {
        (Some(a), Some(b)) => Some(a.max(b)),
        (Some(a), None) => Some(a),
        (None, Some(b)) => Some(b),
        (None, None) => None,
    }
}

fn unix_now_ms() -> u64 {
    crate::utils::unix_now_ms()
}

fn compression_history_is_newer(path: &Path, metadata_updated_at_ms: u64) -> bool {
    crate::compression::history::is_newer_than(path, metadata_updated_at_ms)
}

pub fn normalize_path_key(path: &Path) -> String {
    crate::utils::normalize_path_key(path)
}

#[cfg(test)]
mod tests;
