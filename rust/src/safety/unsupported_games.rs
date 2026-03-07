//! Unsupported games database: embedded + community + user-reported.
//!
//! Some games break after WOF compression but aren't DirectStorage games.
//! This module provides O(1) lookup by game folder name (case-insensitive)
//! across three merged sets:
//!   1. Embedded (compile-time, from `known_unsupported_games.json`)
//!   2. Community (fetched from GitHub, cached to disk with 24h cooldown)
//!   3. User-reported (local user additions)

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
#[cfg(not(test))]
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::{sync_channel, Receiver, SyncSender, TrySendError};
use std::sync::{LazyLock, RwLock};

const KNOWN_UNSUPPORTED_JSON: &str = include_str!("known_unsupported_games.json");
const MAX_ENTRIES: usize = 2048;

static EMBEDDED: LazyLock<HashSet<String>> = LazyLock::new(|| {
    serde_json::from_str::<Vec<String>>(KNOWN_UNSUPPORTED_JSON)
        .unwrap_or_else(|e| {
            log::warn!("Failed to parse known_unsupported_games.json: {e}");
            Vec::new()
        })
        .into_iter()
        .map(|s| s.to_ascii_lowercase())
        .collect()
});

static COMMUNITY: LazyLock<RwLock<HashSet<String>>> = LazyLock::new(|| {
    let set = load_json_set(&community_path().unwrap_or_default()).unwrap_or_default();
    RwLock::new(set)
});

static USER_REPORTED: LazyLock<RwLock<HashSet<String>>> = LazyLock::new(|| {
    let set = load_json_set(&user_reported_path().unwrap_or_default()).unwrap_or_default();
    RwLock::new(set)
});

/// Which set was modified and needs persisting.
#[derive(Clone, Copy)]
enum SaveTarget {
    Community,
    UserReported,
}

static SAVE_QUEUE: LazyLock<Option<SyncSender<SaveTarget>>> = LazyLock::new(|| {
    let (tx, rx) = sync_channel(2);
    match std::thread::Builder::new()
        .name("pressplay-unsupported-writer".to_string())
        .spawn(move || save_worker(rx))
    {
        Ok(_) => Some(tx),
        Err(e) => {
            log::warn!("Failed to spawn unsupported games writer thread: {e}");
            None
        }
    }
});

#[cfg(not(test))]
static CONFIG_DIR_CREATED: AtomicBool = AtomicBool::new(false);

fn normalize_folder_name(name: &str) -> Option<String> {
    let normalized = name.trim().to_ascii_lowercase();
    if normalized.is_empty() || normalized.starts_with('.') {
        return None;
    }
    Some(normalized)
}

fn config_dir() -> Result<PathBuf, std::io::Error> {
    #[cfg(test)]
    {
        use std::time::{SystemTime, UNIX_EPOCH};
        static TEST_DIR: LazyLock<PathBuf> = LazyLock::new(|| {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            std::env::temp_dir().join(format!(
                "pressplay-unsupported-tests-{}-{nanos}",
                std::process::id()
            ))
        });
        fs::create_dir_all(&*TEST_DIR)?;
        Ok(TEST_DIR.clone())
    }

    #[cfg(not(test))]
    {
        let dir = dirs::config_dir()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
        let pressplay_dir = dir.join("pressplay");
        if !CONFIG_DIR_CREATED.load(std::sync::atomic::Ordering::Relaxed) {
            fs::create_dir_all(&pressplay_dir)?;
            CONFIG_DIR_CREATED.store(true, std::sync::atomic::Ordering::Relaxed);
        }
        Ok(pressplay_dir)
    }
}

fn community_path() -> Result<PathBuf, std::io::Error> {
    Ok(config_dir()?.join("community_unsupported.json"))
}

fn user_reported_path() -> Result<PathBuf, std::io::Error> {
    Ok(config_dir()?.join("user_reported_unsupported.json"))
}

fn load_json_set(path: &Path) -> Result<HashSet<String>, Box<dyn std::error::Error>> {
    let contents = fs::read_to_string(path)?;
    let games: Vec<String> = serde_json::from_str(&contents)?;
    let mut set = HashSet::new();
    for game in games {
        if let Some(normalized) = normalize_folder_name(&game) {
            if set.len() >= MAX_ENTRIES {
                break;
            }
            set.insert(normalized);
        }
    }
    Ok(set)
}

fn save_set(set: &RwLock<HashSet<String>>, path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let snapshot: HashSet<String> = match set.read() {
        Ok(guard) => guard.clone(),
        Err(poisoned) => poisoned.into_inner().clone(),
    };
    let mut sorted: Vec<&String> = snapshot.iter().collect();
    sorted.sort();
    let json = serde_json::to_string_pretty(&sorted)?;
    crate::utils::atomic_write(path, json.as_bytes())?;
    Ok(())
}

fn save_worker(rx: Receiver<SaveTarget>) {
    while let Ok(target) = rx.recv() {
        let mut save_community = matches!(target, SaveTarget::Community);
        let mut save_user = matches!(target, SaveTarget::UserReported);
        // Coalesce: drain queued signals, collecting distinct variants
        while let Ok(t) = rx.try_recv() {
            match t {
                SaveTarget::Community => save_community = true,
                SaveTarget::UserReported => save_user = true,
            }
        }
        if save_community {
            if let Err(e) = community_path().map(|p| save_set(&COMMUNITY, &p)) {
                log::warn!("Failed to persist community unsupported list: {e}");
            }
        }
        if save_user {
            if let Err(e) = user_reported_path().map(|p| save_set(&USER_REPORTED, &p)) {
                log::warn!("Failed to persist user-reported unsupported list: {e}");
            }
        }
    }
}

fn queue_save(target: SaveTarget) {
    if let Some(tx) = SAVE_QUEUE.as_ref() {
        match tx.try_send(target) {
            Ok(()) | Err(TrySendError::Full(_)) => {}
            Err(TrySendError::Disconnected(_)) => {
                log::warn!("Unsupported games writer thread unavailable; persisting synchronously");
                let _ = match target {
                    SaveTarget::Community => community_path().map(|p| save_set(&COMMUNITY, &p)),
                    SaveTarget::UserReported => {
                        user_reported_path().map(|p| save_set(&USER_REPORTED, &p))
                    }
                };
            }
        }
    }
}

// ── Public API ────────────────────────────────────────────────────────

/// Check if a game at `game_path` is in any unsupported list (O(1) lookup).
pub fn is_unsupported_game(game_path: &Path) -> bool {
    let folder_name = match game_path.file_name().and_then(|n| n.to_str()) {
        Some(name) => name,
        None => return false,
    };
    let key = folder_name.to_ascii_lowercase();

    if EMBEDDED.contains(&key) {
        return true;
    }
    if let Ok(set) = COMMUNITY.read() {
        if set.contains(&key) {
            return true;
        }
    }
    if let Ok(set) = USER_REPORTED.read() {
        if set.contains(&key) {
            return true;
        }
    }
    false
}

/// Add a game to the user-reported unsupported list.
pub fn report_unsupported_game(game_path: &Path) {
    let folder_name = match game_path.file_name().and_then(|n| n.to_str()) {
        Some(name) => name,
        None => return,
    };
    let key = match normalize_folder_name(folder_name) {
        Some(k) => k,
        None => return,
    };

    // Already in embedded or community — no need to user-report
    if EMBEDDED.contains(&key) {
        return;
    }
    if let Ok(set) = COMMUNITY.read() {
        if set.contains(&key) {
            return;
        }
    }

    let mut set = match USER_REPORTED.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if set.contains(&key) || set.len() >= MAX_ENTRIES {
        return;
    }
    set.insert(key.clone());
    drop(set);

    log::info!("User reported unsupported game: {key}");
    queue_save(SaveTarget::UserReported);
}

/// Remove a game from the user-reported unsupported list.
pub fn unreport_unsupported_game(game_path: &Path) {
    let folder_name = match game_path.file_name().and_then(|n| n.to_str()) {
        Some(name) => name,
        None => return,
    };
    let key = match normalize_folder_name(folder_name) {
        Some(k) => k,
        None => return,
    };

    let mut set = match USER_REPORTED.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if !set.remove(&key) {
        return;
    }
    drop(set);

    log::info!("Removed user-reported unsupported game: {key}");
    queue_save(SaveTarget::UserReported);
}

/// Replace the community unsupported list from raw JSON bytes.
/// Called after fetching from GitHub.
pub fn update_community_list(games: Vec<String>) -> Result<(), String> {
    let mut new_set = HashSet::new();
    for game in games {
        if let Some(normalized) = normalize_folder_name(&game) {
            if new_set.len() >= MAX_ENTRIES {
                break;
            }
            new_set.insert(normalized);
        }
    }

    let mut set = match COMMUNITY.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    *set = new_set;
    drop(set);

    log::info!("Updated community unsupported list");
    queue_save(SaveTarget::Community);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_json_parses() {
        assert!(
            !EMBEDDED.is_empty(),
            "embedded unsupported database should have entries"
        );
    }

    #[test]
    fn known_unsupported_game_detected() {
        assert!(is_unsupported_game(Path::new(
            r"C:\Games\Tom Clancy's Rainbow Six Siege"
        )));
        assert!(is_unsupported_game(Path::new(
            r"C:\Games\tom clancy's rainbow six siege"
        )));
    }

    #[test]
    fn unknown_game_not_detected() {
        assert!(!is_unsupported_game(Path::new(
            r"C:\Games\__definitely_not_unsupported__"
        )));
    }

    #[test]
    fn report_and_unreport() {
        use std::time::{SystemTime, UNIX_EPOCH};
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let name = format!(r"C:\Games\TestUnsupported_{nanos}");
        let path = Path::new(&name);

        assert!(!is_unsupported_game(path));
        report_unsupported_game(path);
        std::thread::sleep(std::time::Duration::from_millis(50));
        assert!(is_unsupported_game(path));

        unreport_unsupported_game(path);
        std::thread::sleep(std::time::Duration::from_millis(50));
        assert!(!is_unsupported_game(path));
    }

    #[test]
    fn update_community_list_works() {
        update_community_list(vec!["community_test_game_abc123".to_string()]).unwrap();
        assert!(is_unsupported_game(Path::new(
            r"C:\Games\community_test_game_abc123"
        )));
    }

    #[test]
    fn normalize_rejects_empty_and_dot_prefix() {
        assert_eq!(normalize_folder_name(""), None);
        assert_eq!(normalize_folder_name(".hidden"), None);
        assert_eq!(
            normalize_folder_name(" My Game "),
            Some("my game".to_string())
        );
    }
}
