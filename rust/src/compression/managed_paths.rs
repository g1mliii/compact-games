//! Durable ownership ledger for folders compressed by Compact Games.
//!
//! Compression history is useful for analytics, but it is not an ownership
//! record: it never records decompression and it may outlive the filesystem
//! state it describes. This ledger is updated only after successful native
//! operations and is revalidated against the filesystem before restore.

use std::collections::HashMap;
use std::path::{Component, Path, PathBuf};
use std::sync::{LazyLock, RwLock};

use serde::{Deserialize, Serialize};

use crate::compression::error::CompressionError;
use crate::compression::history::{get_historical_stats, CompressionHistoryEntry};
use crate::discovery::utils::dir_stats_authoritative;

const LEDGER_VERSION: u32 = 1;
const LEDGER_FILE_NAME: &str = "managed_paths.json";
const PRESENT_MARKER_FILE_NAME: &str = "managed_compressed_games.present";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManagedPathEntry {
    pub game_path: String,
    pub game_name: String,
    pub recorded_at_ms: u64,
    pub original_bytes: u64,
    pub compressed_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ManagedPathLedger {
    #[serde(default = "ledger_version")]
    version: u32,
    #[serde(default)]
    migrated_from_history: bool,
    #[serde(default)]
    entries: Vec<ManagedPathEntry>,
}

#[derive(Debug, Clone)]
pub struct ManagedRestoreGame {
    pub game_path: String,
    pub game_name: String,
    pub drive: String,
    pub required_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct ManagedRestoreDrive {
    pub drive: String,
    pub required_bytes: u64,
    pub available_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct ManagedRestorePlan {
    pub games: Vec<ManagedRestoreGame>,
    pub drives: Vec<ManagedRestoreDrive>,
}

static LEDGER: LazyLock<RwLock<Option<ManagedPathLedger>>> = LazyLock::new(|| RwLock::new(None));

fn ledger_version() -> u32 {
    LEDGER_VERSION
}

fn default_ledger() -> ManagedPathLedger {
    ManagedPathLedger {
        version: LEDGER_VERSION,
        migrated_from_history: false,
        entries: Vec::new(),
    }
}

fn config_dir() -> PathBuf {
    dirs::config_dir()
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."))
        .join("compact_games")
}

fn ledger_path() -> PathBuf {
    config_dir().join(LEDGER_FILE_NAME)
}

fn marker_path() -> PathBuf {
    config_dir().join(PRESENT_MARKER_FILE_NAME)
}

/// Initialize the ledger and perform the one-time history migration.
///
/// Migration intentionally does not walk game folders during app startup.
/// `build_restore_plan` performs the authoritative filesystem recheck before
/// any restore is offered or started.
pub fn initialize() {
    ensure_loaded();
}

fn ensure_loaded() {
    {
        let guard = LEDGER
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if guard.is_some() {
            return;
        }
    }

    let mut guard = LEDGER
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if guard.is_some() {
        return;
    }

    let path = ledger_path();
    let mut ledger = if path.exists() {
        match std::fs::read_to_string(&path)
            .ok()
            .and_then(|contents| serde_json::from_str(&contents).ok())
        {
            Some(ledger) => ledger,
            None => {
                log::warn!("Managed-path ledger could not be read; starting with a new ledger");
                default_ledger()
            }
        }
    } else {
        default_ledger()
    };

    let mut changed = false;
    if !ledger.migrated_from_history {
        merge_history_entries(&mut ledger, get_historical_stats());
        ledger.migrated_from_history = true;
        changed = true;
    }
    if ledger.version != LEDGER_VERSION {
        ledger.version = LEDGER_VERSION;
        changed = true;
    }

    if changed || !path.exists() {
        if let Err(error) = persist_ledger(&ledger) {
            log::warn!("Failed to persist managed-path migration: {error}");
        }
    } else if let Err(error) = sync_present_marker(&ledger) {
        log::warn!("Failed to sync managed-path marker: {error}");
    }

    *guard = Some(ledger);
}

fn merge_history_entries(ledger: &mut ManagedPathLedger, history: Vec<CompressionHistoryEntry>) {
    let mut latest_by_path = HashMap::<String, CompressionHistoryEntry>::new();
    for entry in history {
        let key = crate::utils::normalize_path_key(Path::new(&entry.game_path));
        latest_by_path
            .entry(key)
            .and_modify(|current| {
                if entry.timestamp_ms > current.timestamp_ms {
                    *current = entry.clone();
                }
            })
            .or_insert(entry);
    }

    let mut known_paths: HashMap<String, usize> = ledger
        .entries
        .iter()
        .enumerate()
        .map(|(index, entry)| {
            (
                crate::utils::normalize_path_key(Path::new(&entry.game_path)),
                index,
            )
        })
        .collect();

    for (key, entry) in latest_by_path {
        if known_paths.contains_key(&key) {
            continue;
        }
        known_paths.insert(key, ledger.entries.len());
        ledger.entries.push(ManagedPathEntry {
            game_path: entry.game_path,
            game_name: entry.game_name,
            recorded_at_ms: entry.timestamp_ms,
            original_bytes: entry.actual_stats.original_bytes,
            compressed_bytes: entry.actual_stats.compressed_bytes,
        });
    }
}

/// Add or update an owned path after compression succeeds.
pub fn record_managed_compression(
    game_path: String,
    game_name: String,
    original_bytes: u64,
    compressed_bytes: u64,
) -> std::io::Result<()> {
    ensure_loaded();
    let mut guard = LEDGER
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(ledger) = guard.as_mut() else {
        return Err(std::io::Error::other(
            "managed-path ledger was not initialized",
        ));
    };

    let mut next_ledger = ledger.clone();
    let key = crate::utils::normalize_path_key(Path::new(&game_path));
    let next = ManagedPathEntry {
        game_path,
        game_name,
        recorded_at_ms: crate::utils::unix_now_ms(),
        original_bytes,
        compressed_bytes,
    };
    if let Some(existing) = next_ledger
        .entries
        .iter_mut()
        .find(|entry| crate::utils::normalize_path_key(Path::new(&entry.game_path)) == key)
    {
        *existing = next;
    } else {
        next_ledger.entries.push(next);
    }

    commit_ledger(ledger, next_ledger)
}

/// Remove an owned path after decompression succeeds.
pub fn remove_managed_path(game_path: &Path) -> std::io::Result<()> {
    ensure_loaded();
    let mut guard = LEDGER
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(ledger) = guard.as_mut() else {
        return Err(std::io::Error::other(
            "managed-path ledger was not initialized",
        ));
    };
    let mut next_ledger = ledger.clone();
    let key = crate::utils::normalize_path_key(game_path);
    let previous_len = next_ledger.entries.len();
    next_ledger
        .entries
        .retain(|entry| crate::utils::normalize_path_key(Path::new(&entry.game_path)) != key);
    if next_ledger.entries.len() == previous_len {
        return Ok(());
    }

    commit_ledger(ledger, next_ledger)
}

/// Recheck every owned path and build a restore preflight plan.
///
/// Missing or no-longer-compressed paths are removed from the ledger. This is
/// the ownership boundary that prevents history or third-party compression
/// detection from being treated as permission to decompress.
pub fn build_restore_plan() -> Result<ManagedRestorePlan, CompressionError> {
    ensure_loaded();
    let entries = {
        let guard = LEDGER
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        guard
            .as_ref()
            .map(|ledger| ledger.entries.clone())
            .unwrap_or_default()
    };

    let mut games = Vec::new();
    let mut stale_keys = Vec::new();
    let mut required_by_drive = HashMap::<String, u64>::new();
    let mut representative_path_by_drive = HashMap::<String, PathBuf>::new();

    for entry in entries {
        let path = PathBuf::from(&entry.game_path);
        let key = crate::utils::normalize_path_key(&path);
        if !path.is_dir() {
            stale_keys.push(key);
            continue;
        }

        let stats = match dir_stats_authoritative(&path) {
            Ok(stats) => stats,
            Err(error) => {
                // One unreadable file (permission-denied ACL, broken junction,
                // over-length path, file removed mid-walk) must not abort the
                // whole plan and block restore for every other game. Skip this
                // game and keep it in the ledger so it can be retried later.
                log::warn!(
                    "Restore preflight could not read \"{}\": {error}; skipping (kept in ledger)",
                    path.display()
                );
                continue;
            }
        };
        if !stats.is_compressed {
            stale_keys.push(key);
            continue;
        }

        let required_bytes = stats.logical_size.saturating_sub(stats.physical_size);
        let drive = volume_label(&path);
        required_by_drive
            .entry(drive.clone())
            .and_modify(|required| *required = required.saturating_add(required_bytes))
            .or_insert(required_bytes);
        representative_path_by_drive
            .entry(drive.clone())
            .or_insert_with(|| path.clone());
        games.push(ManagedRestoreGame {
            game_path: entry.game_path,
            game_name: entry.game_name,
            drive,
            required_bytes,
        });
    }

    if !stale_keys.is_empty() {
        remove_stale_entries(&stale_keys)?;
    }

    games.sort_by(|left, right| {
        left.game_name
            .to_lowercase()
            .cmp(&right.game_name.to_lowercase())
            .then_with(|| left.game_path.cmp(&right.game_path))
    });
    let mut drives: Vec<_> = required_by_drive
        .into_iter()
        .map(|(drive, required_bytes)| {
            let available_bytes = representative_path_by_drive
                .get(&drive)
                .and_then(|path| available_space(path))
                .unwrap_or(0);
            ManagedRestoreDrive {
                drive,
                required_bytes,
                available_bytes,
            }
        })
        .collect();
    drives.sort_by(|left, right| left.drive.cmp(&right.drive));

    sync_current_marker()?;
    Ok(ManagedRestorePlan { games, drives })
}

fn remove_stale_entries(stale_keys: &[String]) -> std::io::Result<()> {
    let mut guard = LEDGER
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(ledger) = guard.as_mut() else {
        return Err(std::io::Error::other(
            "managed-path ledger was not initialized",
        ));
    };
    let mut next_ledger = ledger.clone();
    next_ledger.entries.retain(|entry| {
        let key = crate::utils::normalize_path_key(Path::new(&entry.game_path));
        !stale_keys.contains(&key)
    });
    commit_ledger(ledger, next_ledger)
}

fn persist_ledger(ledger: &ManagedPathLedger) -> std::io::Result<()> {
    write_ledger_file(ledger)?;
    sync_present_marker(ledger)
}

fn commit_ledger(
    ledger: &mut ManagedPathLedger,
    next_ledger: ManagedPathLedger,
) -> std::io::Result<()> {
    write_ledger_file(&next_ledger)?;
    *ledger = next_ledger;
    sync_present_marker(ledger)
}

fn write_ledger_file(ledger: &ManagedPathLedger) -> std::io::Result<()> {
    let json = serde_json::to_vec_pretty(ledger).map_err(std::io::Error::other)?;
    crate::utils::atomic_write(&ledger_path(), &json)
}

fn sync_current_marker() -> std::io::Result<()> {
    let guard = LEDGER
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(ledger) = guard.as_ref() else {
        return Err(std::io::Error::other(
            "managed-path ledger was not initialized",
        ));
    };
    sync_present_marker(ledger)
}

fn sync_present_marker(ledger: &ManagedPathLedger) -> std::io::Result<()> {
    let marker = marker_path();
    if ledger.entries.is_empty() {
        match std::fs::remove_file(marker) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    } else {
        crate::utils::atomic_write(&marker, b"managed compressed games remain\n")
    }
}

fn volume_label(path: &Path) -> String {
    match path.components().next() {
        Some(Component::Prefix(prefix)) => {
            let mut label = prefix.as_os_str().to_string_lossy().into_owned();
            if !label.ends_with('\\') {
                label.push('\\');
            }
            label
        }
        _ => path
            .ancestors()
            .last()
            .unwrap_or(path)
            .to_string_lossy()
            .into_owned(),
    }
}

#[cfg(windows)]
fn available_space(path: &Path) -> Option<u64> {
    use std::os::windows::ffi::OsStrExt;

    use windows::core::PCWSTR;
    use windows::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;

    let wide: Vec<u16> = path
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let mut available = 0_u64;
    unsafe {
        GetDiskFreeSpaceExW(PCWSTR(wide.as_ptr()), Some(&mut available), None, None)
            .ok()
            .map(|_| available)
    }
}

#[cfg(not(windows))]
fn available_space(_path: &Path) -> Option<u64> {
    Some(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compression::algorithm::CompressionAlgorithm;
    use crate::compression::history::{ActualStats, EstimateSnapshot};

    fn history_entry(path: &str, timestamp_ms: u64) -> CompressionHistoryEntry {
        CompressionHistoryEntry {
            game_path: path.to_owned(),
            game_name: format!("Game {timestamp_ms}"),
            timestamp_ms,
            estimate: EstimateSnapshot {
                scanned_files: 0,
                sampled_bytes: 0,
                estimated_saved_bytes: 0,
            },
            actual_stats: ActualStats {
                original_bytes: 10_000,
                compressed_bytes: 7_500,
                actual_saved_bytes: 2_500,
                files_processed: 10,
            },
            algorithm: CompressionAlgorithm::Xpress8K,
            duration_ms: 100,
        }
    }

    #[test]
    fn history_migration_keeps_latest_entry_per_normalized_path() {
        let mut ledger = default_ledger();
        merge_history_entries(
            &mut ledger,
            vec![
                history_entry(r"C:\Games\Example", 100),
                history_entry(r"c:/games/example/", 200),
            ],
        );

        assert_eq!(ledger.entries.len(), 1);
        assert_eq!(ledger.entries[0].recorded_at_ms, 200);
        assert_eq!(ledger.entries[0].game_name, "Game 200");
    }

    #[test]
    fn history_migration_does_not_overwrite_an_existing_owned_entry() {
        let mut ledger = default_ledger();
        ledger.entries.push(ManagedPathEntry {
            game_path: r"C:\Games\Example".to_owned(),
            game_name: "Owned Name".to_owned(),
            recorded_at_ms: 300,
            original_bytes: 20,
            compressed_bytes: 10,
        });

        merge_history_entries(&mut ledger, vec![history_entry(r"c:\games\example", 500)]);

        assert_eq!(ledger.entries.len(), 1);
        assert_eq!(ledger.entries[0].game_name, "Owned Name");
    }
}
