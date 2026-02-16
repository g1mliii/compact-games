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
    let key = normalize_path_key(path);
    if let Some(stats) = with_pending_read(|pending| {
        pending
            .entries
            .get(&key)
            .filter(|entry| entry.token == *token)
            .map(|entry| entry.stats.clone())
    }) {
        return Some(stats);
    }

    with_cache_read(|cache| {
        cache
            .entries
            .get(&key)
            .filter(|entry| entry.token == *token)
            .map(|entry| entry.stats.clone())
    })
}

pub fn lookup_stale(path: &Path) -> Option<CachedGameStats> {
    let key = normalize_path_key(path);
    if let Some(stats) =
        with_pending_read(|pending| pending.entries.get(&key).map(|entry| entry.stats.clone()))
    {
        return Some(stats);
    }
    with_cache_read(|cache| cache.entries.get(&key).map(|entry| entry.stats.clone()))
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
    fs::write(path, json)?;
    Ok(())
}

fn cache_path() -> Result<PathBuf, std::io::Error> {
    let config_dir = dirs::config_dir()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
    let pressplay_dir = config_dir.join("pressplay");

    if !CACHE_DIR_CREATED.load(Ordering::Relaxed) {
        fs::create_dir_all(&pressplay_dir)?;
        CACHE_DIR_CREATED.store(true, Ordering::Relaxed);
    }

    Ok(pressplay_dir.join(CACHE_FILE_NAME))
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
    std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn normalize_path_key(path: &Path) -> String {
    #[cfg(windows)]
    {
        let mut normalized = path.as_os_str().to_string_lossy().replace('/', "\\");
        while normalized.len() > 3 && normalized.ends_with('\\') {
            normalized.pop();
        }
        normalized.to_ascii_lowercase()
    }

    #[cfg(not(windows))]
    {
        path.to_string_lossy().into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn change_token_detects_child_count_changes() {
        let dir = tempfile::TempDir::new().unwrap();
        let token_before = compute_change_token(dir.path(), true);
        std::fs::write(dir.path().join("test.bin"), b"data").unwrap();
        let token_after = compute_change_token(dir.path(), true);
        assert_ne!(token_before.child_count, token_after.child_count);
    }

    #[test]
    fn change_token_probe_detects_nested_file_changes() {
        let dir = tempfile::TempDir::new().unwrap();
        let nested = dir.path().join("a").join("b");
        std::fs::create_dir_all(&nested).unwrap();
        let file = nested.join("probe.bin");
        std::fs::write(&file, b"v1").unwrap();

        let before = compute_change_token(dir.path(), true);
        std::fs::write(&file, b"v2-more-data").unwrap();
        let after = compute_change_token(dir.path(), true);
        assert_ne!(before.probe_total_size, after.probe_total_size);
    }

    #[test]
    fn upsert_is_visible_before_persist_via_pending_map() {
        let dir = tempfile::TempDir::new().unwrap();
        let token = compute_change_token(dir.path(), false);
        upsert(
            dir.path(),
            token.clone(),
            CachedGameStats::from_parts(10, 10, false, false),
        );
        let hit = lookup(dir.path(), &token);
        assert!(hit.is_some());
    }

    #[cfg(windows)]
    #[test]
    fn normalize_path_key_windows_is_case_insensitive() {
        let a = normalize_path_key(Path::new(r"C:\Games\Test\"));
        let b = normalize_path_key(Path::new(r"c:/games/test"));
        assert_eq!(a, b);
    }
}
