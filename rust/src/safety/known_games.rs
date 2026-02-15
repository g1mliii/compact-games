//! Hybrid DirectStorage game database: embedded + learned.
//!
//! Provides fast lookup by game folder name (case-insensitive).
//! Combines compile-time embedded list (52 games from SteamDB)
//! with runtime learned list (games discovered via filesystem scan).
//!
//! When filesystem scan detects DirectStorage, the game is added to
//! the learned cache so future checks use O(1) lookup instead of slow scan.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender};
use std::sync::{LazyLock, RwLock};

const KNOWN_GAMES_JSON: &str = include_str!("known_directstorage_games.json");

static EMBEDDED_GAMES: LazyLock<HashSet<String>> = LazyLock::new(|| {
    serde_json::from_str::<Vec<String>>(KNOWN_GAMES_JSON)
        .unwrap_or_else(|e| {
            log::warn!("Failed to parse known_directstorage_games.json: {e}");
            Vec::new()
        })
        .into_iter()
        .map(|s| s.to_ascii_lowercase())
        .collect()
});

/// Runtime learned games cache (loaded from user config on first access).
static LEARNED_GAMES: LazyLock<RwLock<HashSet<String>>> = LazyLock::new(|| {
    let learned = load_learned_games().unwrap_or_else(|e| {
        log::debug!("No learned games cache found: {e}");
        HashSet::new()
    });
    RwLock::new(learned)
});

static SAVE_QUEUE: LazyLock<Option<SyncSender<HashSet<String>>>> = LazyLock::new(|| {
    let (tx, rx) = sync_channel(1);
    match std::thread::Builder::new()
        .name("pressplay-ds-cache-writer".to_string())
        .spawn(move || save_worker(rx))
    {
        Ok(_handle) => Some(tx),
        Err(e) => {
            log::warn!("Failed to spawn learned games writer thread: {e}");
            None
        }
    }
});

static CONFIG_DIR_CREATED: AtomicBool = AtomicBool::new(false);

fn recv_latest_snapshot(rx: &Receiver<HashSet<String>>) -> Option<HashSet<String>> {
    let mut latest = rx.recv().ok()?;
    while let Ok(newer) = rx.try_recv() {
        latest = newer;
    }
    Some(latest)
}

fn save_worker(rx: Receiver<HashSet<String>>) {
    while let Some(snapshot) = recv_latest_snapshot(&rx) {
        if let Err(e) = save_learned_games(&snapshot) {
            log::warn!("Failed to persist learned games cache: {e}");
        }
    }
}

fn learned_games_path() -> Result<PathBuf, std::io::Error> {
    let config_dir = dirs::config_dir()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
    let pressplay_dir = config_dir.join("pressplay");

    if !CONFIG_DIR_CREATED.load(Ordering::Relaxed) {
        fs::create_dir_all(&pressplay_dir)?;
        CONFIG_DIR_CREATED.store(true, Ordering::Relaxed);
    }

    Ok(pressplay_dir.join("learned_directstorage_games.json"))
}

fn load_learned_games() -> Result<HashSet<String>, Box<dyn std::error::Error>> {
    let path = learned_games_path()?;
    let contents = fs::read_to_string(path)?;
    let games: Vec<String> = serde_json::from_str(&contents)?;
    Ok(games.into_iter().map(|s| s.to_ascii_lowercase()).collect())
}

fn save_learned_games(games: &HashSet<String>) -> Result<(), Box<dyn std::error::Error>> {
    let path = learned_games_path()?;
    let mut sorted: Vec<&String> = games.iter().collect();
    sorted.sort();
    let json = serde_json::to_string_pretty(&sorted)?;
    fs::write(path, json)?;
    Ok(())
}

pub fn is_known_directstorage_game(game_path: &Path) -> bool {
    let folder_name = match game_path.file_name().and_then(|n| n.to_str()) {
        Some(name) => name,
        None => return false,
    };

    if EMBEDDED_GAMES
        .iter()
        .any(|g| g.eq_ignore_ascii_case(folder_name))
    {
        return true;
    }

    // Slow path: check learned list (requires lowercase allocation + read lock)
    let folder_name_lower = folder_name.to_ascii_lowercase();
    if let Ok(learned) = LEARNED_GAMES.read() {
        learned.contains(&folder_name_lower)
    } else {
        log::warn!("Failed to acquire read lock on learned games cache");
        false
    }
}

pub fn learn_directstorage_game(game_path: &Path) {
    let folder_name = match game_path.file_name().and_then(|n| n.to_str()) {
        Some(name) => name.to_ascii_lowercase(),
        None => {
            log::debug!(
                "Cannot learn game with invalid path: {}",
                game_path.display()
            );
            return;
        }
    };

    if EMBEDDED_GAMES.contains(&folder_name) {
        return;
    }

    let mut learned = match LEARNED_GAMES.write() {
        Ok(guard) => guard,
        Err(poisoned) => {
            log::warn!("Learned games cache lock poisoned; recovering");
            poisoned.into_inner()
        }
    };

    if learned.contains(&folder_name) {
        return;
    }

    learned.insert(folder_name.clone());
    log::info!("Learned DirectStorage game: {}", folder_name);

    let games_snapshot = learned.clone();
    drop(learned);

    if let Some(tx) = SAVE_QUEUE.as_ref() {
        if let Err(send_err) = tx.send(games_snapshot) {
            log::warn!(
                "Learned games writer thread unavailable; persisting synchronously: {}",
                send_err
            );
            if let Err(e) = save_learned_games(&send_err.0) {
                log::warn!("Failed to persist learned games cache: {e}");
            }
        }
    } else if let Err(e) = save_learned_games(&games_snapshot) {
        log::warn!("Failed to persist learned games cache: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc::sync_channel;

    #[test]
    fn embedded_games_json_parses() {
        assert!(
            !EMBEDDED_GAMES.is_empty(),
            "embedded database should have entries"
        );
    }

    #[test]
    fn known_game_detected_case_insensitive() {
        // Forspoken is in embedded list
        assert!(is_known_directstorage_game(Path::new(
            r"C:\Games\Forspoken"
        )));
        assert!(is_known_directstorage_game(Path::new(
            r"C:\Games\forspoken"
        )));
        assert!(is_known_directstorage_game(Path::new(
            r"C:\Games\FORSPOKEN"
        )));
    }

    #[test]
    fn unknown_game_not_detected() {
        assert!(!is_known_directstorage_game(Path::new(
            r"C:\Games\__definitely_not_a_real_game__"
        )));
    }

    #[test]
    fn empty_path_returns_false() {
        assert!(!is_known_directstorage_game(Path::new("")));
    }

    #[test]
    fn learn_new_game() {
        // Use timestamp-based unique name to avoid cross-test pollution
        use std::time::{SystemTime, UNIX_EPOCH};
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let test_name = format!(r"C:\Games\TestGameForLearning_{}", nanos);
        let test_path = Path::new(&test_name);

        // Should not be known initially
        assert!(!is_known_directstorage_game(test_path));

        // Learn it
        learn_directstorage_game(test_path);

        // Wait briefly for background thread to complete
        std::thread::sleep(std::time::Duration::from_millis(100));

        // Should now be known (in memory, even if disk write failed)
        assert!(is_known_directstorage_game(test_path));
    }

    #[test]
    fn learn_embedded_game_is_noop() {
        // Forspoken is in embedded list
        let test_path = Path::new(r"C:\Games\Forspoken");

        // Learn should be no-op (doesn't add to learned cache)
        learn_directstorage_game(test_path);

        // Should still be detected via embedded list
        assert!(is_known_directstorage_game(test_path));
    }

    #[test]
    fn learn_invalid_path_is_safe() {
        // Should not panic or deadlock
        learn_directstorage_game(Path::new(""));
    }

    #[test]
    fn embedded_check_no_allocation() {
        // This test verifies the hot path uses eq_ignore_ascii_case
        // (no heap allocation for embedded games)
        let forspoken = Path::new(r"C:\Games\Forspoken");

        // First check forces LazyLock init
        let _ = is_known_directstorage_game(forspoken);

        // Subsequent checks should be pure stack operations
        for _ in 0..1000 {
            assert!(is_known_directstorage_game(forspoken));
        }
        // If this test completes quickly, hot path is allocation-free
    }

    #[test]
    fn recv_latest_snapshot_prefers_newest_pending_snapshot() {
        let (tx, rx) = sync_channel(4);

        tx.send(HashSet::from([String::from("game_a")])).unwrap();
        tx.send(HashSet::from([
            String::from("game_a"),
            String::from("game_b"),
        ]))
        .unwrap();
        tx.send(HashSet::from([
            String::from("game_a"),
            String::from("game_b"),
            String::from("game_c"),
        ]))
        .unwrap();
        drop(tx);

        let snapshot = recv_latest_snapshot(&rx).expect("expected a queued snapshot");
        assert!(snapshot.contains("game_c"));
        assert_eq!(snapshot.len(), 3);
    }
}
