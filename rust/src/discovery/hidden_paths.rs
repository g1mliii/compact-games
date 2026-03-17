use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
#[cfg(not(test))]
use std::sync::atomic::AtomicBool;
use std::sync::atomic::Ordering;
use std::sync::{LazyLock, RwLock};

use crate::discovery::cache::{self, normalize_path_key, ChangeToken};

const HIDDEN_PATHS_FILE_NAME: &str = "discovery_hidden_paths.json";
const MAX_HIDDEN_PATHS: usize = 16_384;
const MAX_HIDDEN_AGE_MS: u64 = 90 * 24 * 60 * 60 * 1000;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
struct HiddenPathEntry {
    token: ChangeToken,
    #[serde(default)]
    probe_token: Option<ChangeToken>,
    updated_at_ms: u64,
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
struct HiddenPathsFile {
    #[serde(default)]
    entries: HashMap<String, HiddenPathEntry>,
}

#[cfg(not(test))]
static HIDDEN_PATHS_DIR_CREATED: AtomicBool = AtomicBool::new(false);
static HIDDEN_PATHS_DIRTY: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);
static HIDDEN_PATHS: LazyLock<RwLock<HiddenPathsFile>> =
    LazyLock::new(|| RwLock::new(load_hidden_paths_file()));

/// Mark `path` as hidden by the user. The path will be suppressed from
/// discovery results until its filesystem fingerprint changes (e.g. an update
/// is installed).
pub fn hide_path(path: &Path) {
    let key = normalize_path_key(path);
    let now = unix_now_ms();
    with_hidden_paths_write(|hidden_paths| {
        prune_expired_entries(hidden_paths, now);
        prune_if_needed(hidden_paths, &key);
        hidden_paths.entries.insert(
            key,
            HiddenPathEntry {
                token: cache::compute_change_token(path, false),
                probe_token: Some(cache::compute_change_token(path, true)),
                updated_at_ms: now,
            },
        );
    });
    HIDDEN_PATHS_DIRTY.store(true, Ordering::Relaxed);
}

/// Return `true` if `path` should be suppressed from discovery results.
/// Automatically removes the hidden-path entry when the path's change token or
/// probe token no longer matches the stored values (i.e. the install changed).
pub fn should_hide(path: &Path, current_token: &ChangeToken) -> bool {
    let key = normalize_path_key(path);
    let now = unix_now_ms();
    let Some(entry) =
        with_hidden_paths_read(|hidden_paths| hidden_paths.entries.get(&key).cloned())
    else {
        return false;
    };

    if now.saturating_sub(entry.updated_at_ms) > MAX_HIDDEN_AGE_MS {
        remove_entry_if_unchanged(&key, &entry);
        return false;
    }

    if entry.token != *current_token {
        remove_entry_if_unchanged(&key, &entry);
        return false;
    }

    if let Some(expected_probe_token) = &entry.probe_token {
        let current_probe_token = cache::compute_change_token(path, true);
        if *expected_probe_token != current_probe_token {
            remove_entry_if_unchanged(&key, &entry);
            return false;
        }
    }

    true
}

/// Remove the hidden-path entry for `path`, making it visible in discovery
/// results again on the next scan.
pub fn remove(path: &Path) {
    let key = normalize_path_key(path);
    let removed =
        with_hidden_paths_write(|hidden_paths| hidden_paths.entries.remove(&key).is_some());
    if removed {
        HIDDEN_PATHS_DIRTY.store(true, Ordering::Relaxed);
    }
}

/// Flush the in-memory hidden-paths state to disk if it has been modified. A
/// failed write re-sets the dirty flag so the next call will retry.
pub fn persist_if_dirty() {
    if !HIDDEN_PATHS_DIRTY.swap(false, Ordering::Relaxed) {
        return;
    }

    let snapshot = with_hidden_paths_read(Clone::clone);
    if let Err(e) = save_hidden_paths_file(&snapshot) {
        log::warn!("Failed to persist discovery hidden paths: {e}");
        HIDDEN_PATHS_DIRTY.store(true, Ordering::Relaxed);
    }
}

/// Clear all in-memory hidden-path state and delete the on-disk file.
/// Primarily used in tests and for user-initiated resets.
pub fn clear_all() {
    with_hidden_paths_write(|hidden_paths| hidden_paths.entries.clear());
    HIDDEN_PATHS_DIRTY.store(false, Ordering::Relaxed);

    if let Ok(path) = hidden_paths_path() {
        match fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => log::warn!("Failed to remove discovery hidden-paths file: {e}"),
        }
    }
}

fn load_hidden_paths_file() -> HiddenPathsFile {
    let Ok(path) = hidden_paths_path() else {
        return HiddenPathsFile::default();
    };
    let Ok(contents) = fs::read_to_string(path) else {
        return HiddenPathsFile::default();
    };

    serde_json::from_str::<HiddenPathsFile>(&contents).unwrap_or_else(|e| {
        log::warn!("Failed to parse discovery hidden paths: {e}");
        HiddenPathsFile::default()
    })
}

fn save_hidden_paths_file(
    hidden_paths: &HiddenPathsFile,
) -> Result<(), Box<dyn std::error::Error>> {
    let path = hidden_paths_path()?;
    let json = serde_json::to_string(hidden_paths)?;
    crate::utils::atomic_write(&path, json.as_bytes())?;
    Ok(())
}

fn hidden_paths_path() -> Result<PathBuf, std::io::Error> {
    #[cfg(test)]
    {
        use std::time::{SystemTime, UNIX_EPOCH};

        static TEST_CONFIG_DIR: LazyLock<PathBuf> = LazyLock::new(|| {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            std::env::temp_dir().join(format!(
                "pressplay-discovery-hidden-path-tests-{}-{now}",
                std::process::id()
            ))
        });

        fs::create_dir_all(&*TEST_CONFIG_DIR)?;
        Ok(TEST_CONFIG_DIR.join(HIDDEN_PATHS_FILE_NAME))
    }

    #[cfg(not(test))]
    {
        let config_dir = dirs::config_dir()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
        let pressplay_dir = config_dir.join("pressplay");

        if !HIDDEN_PATHS_DIR_CREATED.load(Ordering::Relaxed) {
            fs::create_dir_all(&pressplay_dir)?;
            HIDDEN_PATHS_DIR_CREATED.store(true, Ordering::Relaxed);
        }

        Ok(pressplay_dir.join(HIDDEN_PATHS_FILE_NAME))
    }
}

fn prune_expired_entries(hidden_paths: &mut HiddenPathsFile, now: u64) {
    hidden_paths
        .entries
        .retain(|_, entry| now.saturating_sub(entry.updated_at_ms) <= MAX_HIDDEN_AGE_MS);
}

fn prune_if_needed(hidden_paths: &mut HiddenPathsFile, incoming_key: &str) {
    if hidden_paths.entries.len() < MAX_HIDDEN_PATHS
        || hidden_paths.entries.contains_key(incoming_key)
    {
        return;
    }

    let Some(evict_key) = hidden_paths
        .entries
        .iter()
        .min_by_key(|(_, entry)| entry.updated_at_ms)
        .map(|(key, _)| key.clone())
    else {
        return;
    };

    hidden_paths.entries.remove(&evict_key);
}

fn with_hidden_paths_read<R>(f: impl FnOnce(&HiddenPathsFile) -> R) -> R {
    match HIDDEN_PATHS.read() {
        Ok(guard) => f(&guard),
        Err(poisoned) => {
            log::warn!("Discovery hidden-paths lock poisoned (read); recovering");
            let guard = poisoned.into_inner();
            f(&guard)
        }
    }
}

fn remove_entry_if_unchanged(key: &str, expected_entry: &HiddenPathEntry) {
    let removed = with_hidden_paths_write(|hidden_paths| match hidden_paths.entries.get(key) {
        Some(current_entry) if current_entry == expected_entry => {
            hidden_paths.entries.remove(key).is_some()
        }
        Some(_) | None => false,
    });

    if removed {
        HIDDEN_PATHS_DIRTY.store(true, Ordering::Relaxed);
    }
}

fn with_hidden_paths_write<R>(f: impl FnOnce(&mut HiddenPathsFile) -> R) -> R {
    match HIDDEN_PATHS.write() {
        Ok(mut guard) => f(&mut guard),
        Err(poisoned) => {
            log::warn!("Discovery hidden-paths lock poisoned (write); recovering");
            let mut guard = poisoned.into_inner();
            f(&mut guard)
        }
    }
}

fn unix_now_ms() -> u64 {
    crate::utils::unix_now_ms()
}

#[cfg(test)]
mod tests {
    use std::fs::File;

    use super::*;
    use crate::discovery::cache;
    use crate::discovery::test_sync::lock_discovery_test;

    #[test]
    fn hidden_path_stays_suppressed_until_install_changes() {
        let _guard = lock_discovery_test();
        clear_all();

        let temp = tempfile::TempDir::new().unwrap();
        let game_dir = temp.path().join("HiddenGame");
        fs::create_dir_all(&game_dir).unwrap();
        File::create(game_dir.join("game.exe"))
            .unwrap()
            .set_len(3 * 1024 * 1024)
            .unwrap();

        let initial_token = cache::compute_change_token(&game_dir, false);
        hide_path(&game_dir);
        assert!(should_hide(&game_dir, &initial_token));

        fs::write(game_dir.join("patch.bin"), vec![1_u8; 128]).unwrap();
        let changed_token = cache::compute_change_token(&game_dir, false);

        assert!(
            !should_hide(&game_dir, &changed_token),
            "changed installs should automatically unhide"
        );
        assert!(
            !should_hide(&game_dir, &changed_token),
            "changed install should stay unhidden after cleanup"
        );
    }

    #[test]
    fn remove_clears_hidden_path_for_path() {
        let _guard = lock_discovery_test();
        clear_all();

        let path = Path::new(r"C:\Games\hidden_remove_test");
        with_hidden_paths_write(|hidden_paths| {
            hidden_paths.entries.insert(
                normalize_path_key(path),
                HiddenPathEntry {
                    token: ChangeToken {
                        root_mtime_ms: Some(1),
                        child_count: 1,
                        child_max_mtime_ms: Some(1),
                        probe_file_count: None,
                        probe_total_size: None,
                        probe_max_mtime_ms: None,
                    },
                    probe_token: None,
                    updated_at_ms: unix_now_ms(),
                },
            );
        });
        HIDDEN_PATHS_DIRTY.store(true, Ordering::Relaxed);

        remove(path);
        assert!(!should_hide(
            path,
            &ChangeToken {
                root_mtime_ms: Some(1),
                child_count: 1,
                child_max_mtime_ms: Some(1),
                probe_file_count: None,
                probe_total_size: None,
                probe_max_mtime_ms: None,
            },
        ));
    }

    #[test]
    fn probe_token_mismatch_unhides_when_shallow_token_still_matches() {
        let _guard = lock_discovery_test();
        clear_all();

        let temp = tempfile::TempDir::new().unwrap();
        let game_dir = temp.path().join("NestedHiddenGame");
        let nested_dir = game_dir.join("Content").join("Paks");
        fs::create_dir_all(&nested_dir).unwrap();
        File::create(nested_dir.join("base.pak"))
            .unwrap()
            .set_len(128 * 1024 * 1024)
            .unwrap();

        let shallow_token = cache::compute_change_token(&game_dir, false);
        let mut stale_probe_token = cache::compute_change_token(&game_dir, true);
        stale_probe_token.probe_total_size = stale_probe_token
            .probe_total_size
            .map(|size| size.saturating_sub(1));

        with_hidden_paths_write(|hidden_paths| {
            hidden_paths.entries.insert(
                normalize_path_key(&game_dir),
                HiddenPathEntry {
                    token: shallow_token.clone(),
                    probe_token: Some(stale_probe_token),
                    updated_at_ms: unix_now_ms(),
                },
            );
        });
        HIDDEN_PATHS_DIRTY.store(true, Ordering::Relaxed);

        assert!(
            !should_hide(&game_dir, &shallow_token),
            "probe token mismatch should clear a hidden path even when the shallow token still matches",
        );
        assert!(
            !should_hide(&game_dir, &shallow_token),
            "probe mismatch should remove the tombstone after unhide",
        );
    }
}
