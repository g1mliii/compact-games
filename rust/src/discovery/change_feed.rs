use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{LazyLock, RwLock};
use std::time::UNIX_EPOCH;

use crate::discovery::cache::normalize_path_key;
use crate::discovery::platform::DiscoveryScanMode;

const CHANGE_FEED_FILE_NAME: &str = "discovery_change_feed.json";
const CHANGE_FEED_SCHEMA_VERSION: u32 = 1;
const MAX_TRACKED_ROOT_ENTRIES: usize = 32_768;
const MAX_TRACKED_ROOTS: usize = 256;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PathFingerprint {
    pub root_mtime_ms: Option<u64>,
    pub child_count: u32,
    pub child_max_mtime_ms: Option<u64>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct TrackedPath {
    path: String,
    fingerprint: PathFingerprint,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
struct RootState {
    #[serde(default)]
    entries: HashMap<String, TrackedPath>,
    #[serde(default)]
    cursor_watermark: Option<String>,
    #[serde(default)]
    updated_at_ms: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct ChangeFeedFile {
    schema_version: u32,
    #[serde(default)]
    last_successful_full_scan_ms: Option<u64>,
    #[serde(default)]
    roots: HashMap<String, RootState>,
}

impl Default for ChangeFeedFile {
    fn default() -> Self {
        Self {
            schema_version: CHANGE_FEED_SCHEMA_VERSION,
            last_successful_full_scan_ms: None,
            roots: HashMap::new(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScanPath {
    Incremental,
    PartialRebuild,
    FullRebuild,
}

impl ScanPath {
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Incremental => "incremental",
            Self::PartialRebuild => "partial-rebuild",
            Self::FullRebuild => "full-rebuild",
        }
    }
}

#[derive(Debug, Clone)]
pub struct CandidatePlan {
    pub changed: Vec<(String, PathBuf)>,
    pub unchanged: Vec<(String, PathBuf)>,
    pub deleted: Vec<PathBuf>,
    pub scan_path: ScanPath,
    pub reason: &'static str,
    root_key: String,
    snapshot_entries: HashMap<String, TrackedPath>,
}

impl CandidatePlan {
    pub fn commit(self) {
        let Self {
            scan_path,
            root_key,
            snapshot_entries,
            ..
        } = self;
        let now = unix_now_ms();
        with_change_feed_write(|feed| {
            prune_roots_if_needed(feed, &root_key);
            let root = feed
                .roots
                .entry(root_key)
                .or_insert_with(RootState::default);
            root.cursor_watermark = Some(now.to_string());
            root.updated_at_ms = now;
            root.entries = snapshot_entries;
        });
        CHANGE_FEED_DIRTY.store(true, Ordering::Relaxed);
        if scan_path == ScanPath::FullRebuild {
            FORCE_FULL_REBUILD.store(false, Ordering::Relaxed);
        }
    }
}

static CHANGE_FEED_DIR_CREATED: AtomicBool = AtomicBool::new(false);
static CHANGE_FEED_DIRTY: AtomicBool = AtomicBool::new(false);
static FORCE_FULL_REBUILD: AtomicBool = AtomicBool::new(false);
static CHANGE_FEED: LazyLock<RwLock<ChangeFeedFile>> =
    LazyLock::new(|| RwLock::new(load_change_feed_file()));

pub fn plan_subdir_scan(
    scan_root: &Path,
    candidates: &[(String, PathBuf)],
    mode: DiscoveryScanMode,
) -> CandidatePlan {
    let root_key = normalize_path_key(scan_root);
    let snapshot_entries = build_snapshot_entries(candidates);

    if mode != DiscoveryScanMode::Full {
        return CandidatePlan {
            changed: candidates.to_vec(),
            unchanged: Vec::new(),
            deleted: Vec::new(),
            scan_path: ScanPath::FullRebuild,
            reason: "quick-mode",
            root_key,
            snapshot_entries,
        };
    }

    let previous_entries = with_change_feed_read(|feed| {
        feed.roots
            .get(&root_key)
            .map(|root| root.entries.clone())
            .unwrap_or_default()
    });

    if FORCE_FULL_REBUILD.load(Ordering::Relaxed) {
        return CandidatePlan {
            changed: candidates.to_vec(),
            unchanged: Vec::new(),
            deleted: previous_entries
                .values()
                .map(|entry| PathBuf::from(&entry.path))
                .collect(),
            scan_path: ScanPath::FullRebuild,
            reason: "state-recovery",
            root_key,
            snapshot_entries,
        };
    }

    if previous_entries.is_empty() {
        return CandidatePlan {
            changed: candidates.to_vec(),
            unchanged: Vec::new(),
            deleted: Vec::new(),
            scan_path: ScanPath::FullRebuild,
            reason: "no-baseline",
            root_key,
            snapshot_entries,
        };
    }

    let mut changed = Vec::new();
    let mut unchanged = Vec::new();
    let mut seen_keys = HashSet::with_capacity(candidates.len());

    for (name, path) in candidates {
        let key = normalize_path_key(path);
        seen_keys.insert(key.clone());
        let current = snapshot_entries.get(&key).map(|entry| &entry.fingerprint);
        let previous = previous_entries.get(&key).map(|entry| &entry.fingerprint);

        if current.is_some() && previous == current {
            unchanged.push((name.clone(), path.clone()));
        } else {
            changed.push((name.clone(), path.clone()));
        }
    }

    let deleted = previous_entries
        .into_iter()
        .filter_map(|(key, entry)| {
            if seen_keys.contains(&key) {
                None
            } else {
                Some(PathBuf::from(entry.path))
            }
        })
        .collect::<Vec<_>>();

    let (scan_path, reason) = if changed.is_empty() && deleted.is_empty() {
        (ScanPath::Incremental, "metadata-match")
    } else if unchanged.is_empty() {
        (ScanPath::FullRebuild, "all-paths-changed")
    } else {
        (ScanPath::PartialRebuild, "metadata-diff")
    };

    CandidatePlan {
        changed,
        unchanged,
        deleted,
        scan_path,
        reason,
        root_key,
        snapshot_entries,
    }
}

pub fn remove(path: &Path) {
    let key = normalize_path_key(path);
    let removed = with_change_feed_write(|feed| {
        let mut removed = false;
        for root in feed.roots.values_mut() {
            removed |= root.entries.remove(&key).is_some();
        }
        removed
    });
    if removed {
        CHANGE_FEED_DIRTY.store(true, Ordering::Relaxed);
    }
}

pub fn mark_full_scan_success() {
    with_change_feed_write(|feed| {
        feed.last_successful_full_scan_ms = Some(unix_now_ms());
    });
    CHANGE_FEED_DIRTY.store(true, Ordering::Relaxed);
}

pub fn persist_if_dirty() {
    if !CHANGE_FEED_DIRTY.swap(false, Ordering::Relaxed) {
        return;
    }

    let serialized = with_change_feed_read(serde_json::to_string);
    let persist_result = serialized
        .map_err(|e| -> Box<dyn std::error::Error> { Box::new(e) })
        .and_then(|json| save_change_feed_json(&json));
    if let Err(e) = persist_result {
        log::warn!("Failed to persist discovery change feed: {e}");
        CHANGE_FEED_DIRTY.store(true, Ordering::Relaxed);
    }
}

pub fn clear_all() {
    with_change_feed_write(|feed| {
        feed.roots.clear();
        feed.last_successful_full_scan_ms = None;
    });
    CHANGE_FEED_DIRTY.store(false, Ordering::Relaxed);
    FORCE_FULL_REBUILD.store(false, Ordering::Relaxed);

    if let Ok(path) = change_feed_path() {
        match fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => log::warn!("Failed to remove discovery change-feed file: {e}"),
        }
    }
}

fn build_snapshot_entries(candidates: &[(String, PathBuf)]) -> HashMap<String, TrackedPath> {
    let mut entries = HashMap::with_capacity(candidates.len());
    for (_, path) in candidates {
        let key = normalize_path_key(path);
        entries.insert(
            key,
            TrackedPath {
                path: path.to_string_lossy().into_owned(),
                fingerprint: fingerprint_path(path),
            },
        );
    }
    trim_snapshot_entries(&mut entries);
    entries
}

fn trim_snapshot_entries(entries: &mut HashMap<String, TrackedPath>) {
    if entries.len() <= MAX_TRACKED_ROOT_ENTRIES {
        return;
    }

    let mut keys = entries.keys().cloned().collect::<Vec<_>>();
    keys.sort_unstable();
    for key in keys.into_iter().skip(MAX_TRACKED_ROOT_ENTRIES) {
        entries.remove(&key);
    }
}

fn prune_roots_if_needed(feed: &mut ChangeFeedFile, incoming_root_key: &str) {
    if feed.roots.len() < MAX_TRACKED_ROOTS {
        return;
    }

    let incoming_exists = feed.roots.contains_key(incoming_root_key);
    let target_len = if incoming_exists {
        MAX_TRACKED_ROOTS
    } else {
        MAX_TRACKED_ROOTS.saturating_sub(1)
    };

    while feed.roots.len() > target_len {
        let Some(evict_key) = feed
            .roots
            .iter()
            .filter(|(key, _)| !incoming_exists || key.as_str() != incoming_root_key)
            .min_by_key(|(_, root)| root.updated_at_ms)
            .map(|(key, _)| key.clone())
        else {
            break;
        };

        feed.roots.remove(&evict_key);
    }
}

fn fingerprint_path(path: &Path) -> PathFingerprint {
    let root_mtime_ms = fs::metadata(path)
        .ok()
        .and_then(|metadata| metadata_modified_ms(&metadata));

    let mut child_count = 0_u32;
    let mut child_max_mtime_ms = None;

    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            child_count = child_count.saturating_add(1);
            let child_mtime = entry
                .metadata()
                .ok()
                .and_then(|metadata| metadata_modified_ms(&metadata));
            child_max_mtime_ms = max_optional_u64(child_max_mtime_ms, child_mtime);
        }
    }

    PathFingerprint {
        root_mtime_ms,
        child_count,
        child_max_mtime_ms,
    }
}

fn with_change_feed_read<R>(f: impl FnOnce(&ChangeFeedFile) -> R) -> R {
    match CHANGE_FEED.read() {
        Ok(guard) => f(&guard),
        Err(poisoned) => {
            log::warn!("Discovery change-feed lock poisoned (read); recovering");
            let guard = poisoned.into_inner();
            f(&guard)
        }
    }
}

fn with_change_feed_write<R>(f: impl FnOnce(&mut ChangeFeedFile) -> R) -> R {
    match CHANGE_FEED.write() {
        Ok(mut guard) => f(&mut guard),
        Err(poisoned) => {
            log::warn!("Discovery change-feed lock poisoned (write); recovering");
            let mut guard = poisoned.into_inner();
            f(&mut guard)
        }
    }
}

fn load_change_feed_file() -> ChangeFeedFile {
    let Ok(path) = change_feed_path() else {
        return ChangeFeedFile::default();
    };
    let Ok(contents) = fs::read_to_string(path) else {
        return ChangeFeedFile::default();
    };

    match serde_json::from_str::<ChangeFeedFile>(&contents) {
        Ok(feed) if feed.schema_version == CHANGE_FEED_SCHEMA_VERSION => feed,
        Ok(feed) => {
            log::warn!(
                "Discovery change-feed schema mismatch (found {}, expected {}); forcing full rebuild",
                feed.schema_version,
                CHANGE_FEED_SCHEMA_VERSION
            );
            FORCE_FULL_REBUILD.store(true, Ordering::Relaxed);
            ChangeFeedFile::default()
        }
        Err(e) => {
            log::warn!(
                "Failed to parse discovery change feed ({}); forcing full rebuild fallback",
                e
            );
            FORCE_FULL_REBUILD.store(true, Ordering::Relaxed);
            ChangeFeedFile::default()
        }
    }
}

fn save_change_feed_json(json: &str) -> Result<(), Box<dyn std::error::Error>> {
    let path = change_feed_path()?;
    fs::write(path, json)?;
    Ok(())
}

fn change_feed_path() -> Result<PathBuf, std::io::Error> {
    let config_dir = dirs::config_dir()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
    let pressplay_dir = config_dir.join("pressplay");

    if !CHANGE_FEED_DIR_CREATED.load(Ordering::Relaxed) {
        fs::create_dir_all(&pressplay_dir)?;
        CHANGE_FEED_DIR_CREATED.store(true, Ordering::Relaxed);
    }

    Ok(pressplay_dir.join(CHANGE_FEED_FILE_NAME))
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

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::*;

    static TEST_MUTEX: Mutex<()> = Mutex::new(());

    #[test]
    fn incremental_plan_after_full_baseline() {
        let _guard = TEST_MUTEX.lock().unwrap();
        clear_all();

        let root = tempfile::TempDir::new().unwrap();
        let game = root.path().join("GameA");
        fs::create_dir_all(&game).unwrap();
        fs::write(game.join("game.exe"), vec![1_u8; 64]).unwrap();
        let candidates = vec![("GameA".to_owned(), game.clone())];

        let first = plan_subdir_scan(root.path(), &candidates, DiscoveryScanMode::Full);
        assert_eq!(first.scan_path, ScanPath::FullRebuild);
        assert_eq!(first.reason, "no-baseline");
        assert_eq!(first.changed.len(), 1);
        first.commit();

        let second = plan_subdir_scan(root.path(), &candidates, DiscoveryScanMode::Full);
        assert_eq!(second.scan_path, ScanPath::Incremental);
        assert_eq!(second.changed.len(), 0);
        assert_eq!(second.unchanged.len(), 1);

        clear_all();
    }

    #[test]
    fn plan_marks_deleted_paths() {
        let _guard = TEST_MUTEX.lock().unwrap();
        clear_all();

        let root = tempfile::TempDir::new().unwrap();
        let game_a = root.path().join("GameA");
        let game_b = root.path().join("GameB");
        fs::create_dir_all(&game_a).unwrap();
        fs::create_dir_all(&game_b).unwrap();
        let baseline = vec![
            ("GameA".to_owned(), game_a.clone()),
            ("GameB".to_owned(), game_b.clone()),
        ];

        let first = plan_subdir_scan(root.path(), &baseline, DiscoveryScanMode::Full);
        first.commit();

        fs::remove_dir_all(&game_b).unwrap();
        let next = vec![("GameA".to_owned(), game_a)];
        let second = plan_subdir_scan(root.path(), &next, DiscoveryScanMode::Full);
        assert_eq!(second.deleted.len(), 1);

        clear_all();
    }

    #[test]
    fn root_tracking_is_bounded() {
        let _guard = TEST_MUTEX.lock().unwrap();
        clear_all();

        let base = tempfile::TempDir::new().unwrap();
        for i in 0..(MAX_TRACKED_ROOTS + 8) {
            let root = base.path().join(format!("root-{i}"));
            let game = root.join("GameA");
            fs::create_dir_all(&game).unwrap();
            let candidates = vec![("GameA".to_owned(), game)];
            let plan = plan_subdir_scan(&root, &candidates, DiscoveryScanMode::Full);
            plan.commit();
        }

        let root_count = with_change_feed_read(|feed| feed.roots.len());
        assert!(
            root_count <= MAX_TRACKED_ROOTS,
            "expected at most {MAX_TRACKED_ROOTS} roots, got {root_count}"
        );

        clear_all();
    }
}
