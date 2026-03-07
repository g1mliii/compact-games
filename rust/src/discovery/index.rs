use crate::discovery::cache::{normalize_path_key, ChangeToken};
use crate::discovery::platform::GameInfo;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{LazyLock, RwLock};

const INDEX_FILE_NAME: &str = "discovery_index.json";
const INDEX_SCHEMA_VERSION: u32 = 1;
const MAX_INDEX_ENTRIES: usize = 16_384;
const MAX_INDEX_AGE_MS: u64 = 30 * 60 * 1000; // 30 minutes

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct IndexEntry {
    token: ChangeToken,
    game: GameInfo,
    updated_at_ms: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct IndexFile {
    schema_version: u32,
    #[serde(default)]
    last_successful_full_scan_ms: Option<u64>,
    #[serde(default)]
    entries: HashMap<String, IndexEntry>,
}

impl Default for IndexFile {
    fn default() -> Self {
        Self {
            schema_version: INDEX_SCHEMA_VERSION,
            last_successful_full_scan_ms: None,
            entries: HashMap::new(),
        }
    }
}

static INDEX_DIR_CREATED: AtomicBool = AtomicBool::new(false);
static INDEX_DIRTY: AtomicBool = AtomicBool::new(false);
static INDEX: LazyLock<RwLock<IndexFile>> = LazyLock::new(|| RwLock::new(load_index_file()));

/// Lookup an index entry by path+token.
///
/// This is an optimization layer only; callers must keep full-scan fallback
/// paths when this misses or returns stale entries.
pub fn lookup(path: &Path, token: &ChangeToken) -> Option<GameInfo> {
    let key = normalize_path_key(path);
    let now = unix_now_ms();
    with_index_read(|index| {
        let entry = index.entries.get(&key)?;
        if entry.token != *token {
            return None;
        }
        if now.saturating_sub(entry.updated_at_ms) > MAX_INDEX_AGE_MS {
            return None;
        }
        Some(entry.game.clone())
    })
}

/// Lookup by path only using age constraints.
///
/// Used by incremental scan planning where metadata fingerprint indicates an
/// unchanged path and a recent indexed entry can be reused directly.
pub fn lookup_recent(path: &Path) -> Option<GameInfo> {
    let key = normalize_path_key(path);
    let now = unix_now_ms();
    with_index_read(|index| {
        let entry = index.entries.get(&key)?;
        if now.saturating_sub(entry.updated_at_ms) > MAX_INDEX_AGE_MS {
            return None;
        }
        Some(entry.game.clone())
    })
}

pub fn upsert(path: &Path, token: ChangeToken, game: &GameInfo) {
    let key = normalize_path_key(path);
    with_index_write(|index| {
        prune_if_needed(index, &key);
        index.entries.insert(
            key,
            IndexEntry {
                token,
                game: game.clone(),
                updated_at_ms: unix_now_ms(),
            },
        );
    });
    INDEX_DIRTY.store(true, Ordering::Relaxed);
}

pub fn remove(path: &Path) {
    let key = normalize_path_key(path);
    let removed = with_index_write(|index| index.entries.remove(&key).is_some());
    if removed {
        INDEX_DIRTY.store(true, Ordering::Relaxed);
    }
}

pub fn mark_full_scan_success() {
    with_index_write(|index| {
        index.last_successful_full_scan_ms = Some(unix_now_ms());
    });
    INDEX_DIRTY.store(true, Ordering::Relaxed);
}

pub fn persist_if_dirty() {
    if !INDEX_DIRTY.swap(false, Ordering::Relaxed) {
        return;
    }

    let snapshot = with_index_read(Clone::clone);
    if let Err(e) = save_index_file(&snapshot) {
        log::warn!("Failed to persist discovery index: {e}");
        INDEX_DIRTY.store(true, Ordering::Relaxed);
    }
}

pub fn clear_all() {
    with_index_write(|index| {
        index.entries.clear();
        index.last_successful_full_scan_ms = None;
    });
    INDEX_DIRTY.store(false, Ordering::Relaxed);

    if let Ok(path) = index_path() {
        match fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => log::warn!("Failed to remove discovery index file: {e}"),
        }
    }
}

fn with_index_read<R>(f: impl FnOnce(&IndexFile) -> R) -> R {
    match INDEX.read() {
        Ok(guard) => f(&guard),
        Err(poisoned) => {
            log::warn!("Discovery index lock poisoned (read); recovering");
            let guard = poisoned.into_inner();
            f(&guard)
        }
    }
}

fn with_index_write<R>(f: impl FnOnce(&mut IndexFile) -> R) -> R {
    match INDEX.write() {
        Ok(mut guard) => f(&mut guard),
        Err(poisoned) => {
            log::warn!("Discovery index lock poisoned (write); recovering");
            let mut guard = poisoned.into_inner();
            f(&mut guard)
        }
    }
}

fn load_index_file() -> IndexFile {
    let Ok(path) = index_path() else {
        return IndexFile::default();
    };
    let Ok(contents) = fs::read_to_string(path) else {
        return IndexFile::default();
    };

    match serde_json::from_str::<IndexFile>(&contents) {
        Ok(index) if index.schema_version == INDEX_SCHEMA_VERSION => index,
        Ok(index) => {
            log::warn!(
                "Discovery index schema mismatch (found {}, expected {}); rebuilding index",
                index.schema_version,
                INDEX_SCHEMA_VERSION
            );
            IndexFile::default()
        }
        Err(e) => {
            log::warn!(
                "Failed to parse discovery index ({}); falling back to full rebuild",
                e
            );
            IndexFile::default()
        }
    }
}

fn save_index_file(index: &IndexFile) -> Result<(), Box<dyn std::error::Error>> {
    let path = index_path()?;
    let json = serde_json::to_string(index)?;
    fs::write(path, json)?;
    Ok(())
}

fn index_path() -> Result<PathBuf, std::io::Error> {
    let config_dir = dirs::config_dir()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
    let pressplay_dir = config_dir.join("pressplay");

    if !INDEX_DIR_CREATED.load(Ordering::Relaxed) {
        fs::create_dir_all(&pressplay_dir)?;
        INDEX_DIR_CREATED.store(true, Ordering::Relaxed);
    }

    Ok(pressplay_dir.join(INDEX_FILE_NAME))
}

fn prune_if_needed(index: &mut IndexFile, incoming_key: &str) {
    if index.entries.len() < MAX_INDEX_ENTRIES || index.entries.contains_key(incoming_key) {
        return;
    }

    let Some(evict_key) = index
        .entries
        .iter()
        .min_by_key(|(_, entry)| entry.updated_at_ms)
        .map(|(key, _)| key.clone())
    else {
        return;
    };

    index.entries.remove(&evict_key);
}

fn unix_now_ms() -> u64 {
    crate::utils::unix_now_ms()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::discovery::cache::compute_change_token;
    use crate::discovery::platform::Platform;

    #[test]
    fn upsert_lookup_roundtrip_with_token() {
        let dir = tempfile::TempDir::new().unwrap();
        let token = compute_change_token(dir.path(), false);
        let game = GameInfo {
            name: "Test".to_owned(),
            path: dir.path().to_path_buf(),
            platform: Platform::Custom,
            size_bytes: 1024,
            compressed_size: None,
            is_compressed: false,
            is_directstorage: false,
            excluded: false,
            last_played: None,
        };

        upsert(dir.path(), token.clone(), &game);
        let hit = lookup(dir.path(), &token).expect("index hit expected");
        assert_eq!(hit.name, game.name);
        assert_eq!(hit.path, game.path);
    }
}
