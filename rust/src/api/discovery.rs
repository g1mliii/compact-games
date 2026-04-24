//! Game discovery API exposed to Flutter via FRB.

use std::path::{Path, PathBuf};

use flutter_rust_bridge::frb;

use super::types::{FrbDiscoveryError, FrbGameInfo, FrbPlatform};
use crate::discovery::platform::{DiscoveryScanMode, Platform};
use crate::discovery::utils;

/// Scan all platforms and return discovered games.
///
/// Each scanner failure is logged but does not abort others,
/// so partial results are returned even if some platforms fail.
pub fn get_all_games() -> Result<Vec<FrbGameInfo>, FrbDiscoveryError> {
    let all_games = utils::scan_all_platforms_with_mode(DiscoveryScanMode::Full);
    let frb_games: Vec<FrbGameInfo> = all_games.into_iter().map(FrbGameInfo::from).collect();
    Ok(frb_games)
}

/// Fast scan optimized for responsiveness.
/// Uses cached or sampled metadata and may be less accurate than full scan.
pub fn get_all_games_quick() -> Result<Vec<FrbGameInfo>, FrbDiscoveryError> {
    let all_games = utils::scan_all_platforms_with_mode(DiscoveryScanMode::Quick);
    let frb_games: Vec<FrbGameInfo> = all_games.into_iter().map(FrbGameInfo::from).collect();
    Ok(frb_games)
}

/// Clear persisted and in-memory discovery cache.
#[frb(sync)]
pub fn clear_discovery_cache() {
    crate::discovery::cache::clear_all();
    crate::discovery::index::clear_all();
    crate::discovery::change_feed::clear_all();
    crate::discovery::hidden_paths::clear_all();
    crate::discovery::install_history::clear_all();
    log::info!("Discovery cache cleared");
}

/// Evict discovery cache for a single game path.
/// Clears stats cache, incremental index, and change feed so the path is
/// re-evaluated on the next scan.
#[frb(sync)]
pub fn clear_discovery_cache_entry(path: String) {
    if path.trim().is_empty() {
        return;
    }
    let path = PathBuf::from(path);
    clear_discovery_metadata_for_candidate_paths(&path);
    persist_discovery_metadata_if_dirty();
    log::info!("Discovery cache entry cleared: {}", path.display());
}

/// Evict all discovery caches for a path and hide the current on-disk install
/// snapshot until that directory changes.
///
/// Call this when the user explicitly removes a game from the library.
pub async fn remove_game_from_discovery(path: String, platform: FrbPlatform) {
    if path.trim().is_empty() {
        return;
    }
    let game_path = PathBuf::from(&path);
    remove_game_from_discovery_inner(&game_path, platform.into());
    persist_discovery_metadata_if_dirty();
    log::info!("Game removed from discovery: {}", path);
}

/// Scan a single custom folder for games.
pub fn scan_custom_folder(path: String) -> Result<Vec<FrbGameInfo>, FrbDiscoveryError> {
    if path.trim().is_empty() {
        return Err(FrbDiscoveryError::InvalidPath {
            message: "path cannot be empty".to_owned(),
        });
    }

    match utils::scan_custom_paths_with_mode(vec![PathBuf::from(&path)], DiscoveryScanMode::Full) {
        Ok(games) => {
            let frb_games: Vec<FrbGameInfo> = games.into_iter().map(FrbGameInfo::from).collect();
            Ok(frb_games)
        }
        Err(e) => Err(FrbDiscoveryError::CustomScanFailed {
            path,
            message: e.to_string(),
        }),
    }
}

/// Add an arbitrary application folder (not a game) for compression.
///
/// Unlike `scan_custom_folder`, this skips game-likeness heuristics and
/// accepts any directory. The returned `FrbGameInfo` has `Platform::Application`.
pub fn add_application_folder(
    path: String,
    name: Option<String>,
) -> Result<FrbGameInfo, FrbDiscoveryError> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err(FrbDiscoveryError::InvalidPath {
            message: "path cannot be empty".to_owned(),
        });
    }

    let mut folder = PathBuf::from(trimmed);

    // If the user picked an executable, resolve to its parent directory.
    if folder.is_file() {
        folder = folder.parent().map(|p| p.to_path_buf()).ok_or_else(|| {
            FrbDiscoveryError::InvalidPath {
                message: format!("cannot resolve parent of '{}'", folder.display()),
            }
        })?;
    }

    if !folder.is_dir() {
        return Err(FrbDiscoveryError::InvalidPath {
            message: format!("'{}' is not a directory", folder.display()),
        });
    }

    let display_name = name.unwrap_or_else(|| {
        folder
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "Application".to_owned())
    });

    let game = utils::build_game_info_with_mode(
        display_name,
        folder,
        Platform::Application,
        DiscoveryScanMode::Full,
    );

    match game {
        Some(info) => Ok(FrbGameInfo::from(info)),
        None => Err(FrbDiscoveryError::DiscoveryFailed {
            message: "Failed to build metadata for the application folder.".to_owned(),
        }),
    }
}

/// Hydrate full metadata for a single discovered game.
///
/// Intended for lazy on-demand UI hydration after quick discovery.
pub fn hydrate_game(
    path: String,
    name: String,
    platform: FrbPlatform,
) -> Result<Option<FrbGameInfo>, FrbDiscoveryError> {
    if path.trim().is_empty() {
        return Err(FrbDiscoveryError::InvalidPath {
            message: "path cannot be empty".to_owned(),
        });
    }

    let game_path = PathBuf::from(&path);
    let platform: Platform = platform.into();

    let stats_path = discovery_stats_path(&game_path, platform);

    let mut game = utils::build_game_info_with_mode_and_stats_path(
        name,
        game_path,
        stats_path,
        platform,
        DiscoveryScanMode::Full,
    );

    // The shared builder doesn't know about Steam manifests, so backfill the
    // app id here so hydrated games keep the primary key used by the
    // community compression DB lookup.
    if let Some(info) = game.as_mut() {
        if info.platform == Platform::Steam && info.steam_app_id.is_none() {
            info.steam_app_id =
                crate::discovery::steam::lookup_steam_app_id_for_path(&info.path);
        }
    }

    // Hydration upserts to the in-memory cache; flush to disk so
    // the work survives abnormal exits and doesn't have to be redone.
    crate::discovery::cache::persist_if_dirty();

    Ok(game.map(FrbGameInfo::from))
}

fn persist_discovery_metadata_if_dirty() {
    crate::discovery::cache::persist_if_dirty();
    crate::discovery::index::persist_if_dirty();
    crate::discovery::change_feed::persist_if_dirty();
    crate::discovery::hidden_paths::persist_if_dirty();
    crate::discovery::install_history::persist_if_dirty();
}

fn clear_discovery_metadata_for_path(path: &Path) {
    crate::discovery::cache::remove(path);
    crate::discovery::index::remove(path);
    crate::discovery::change_feed::remove(path);
    crate::discovery::hidden_paths::remove(path);
    crate::discovery::install_history::remove(path);
}

fn clear_discovery_metadata_for_candidate_paths(path: &Path) {
    clear_discovery_metadata_for_path(path);

    let content_path = path.join("Content");
    if content_path.is_dir() {
        clear_discovery_metadata_for_path(&content_path);
    }
}

fn remove_game_from_discovery_inner(game_path: &Path, platform: Platform) {
    let stats_path = discovery_stats_path(game_path, platform);
    clear_discovery_metadata_for_path(&stats_path);
    crate::discovery::hidden_paths::hide_path(&stats_path);
}

fn discovery_stats_path(game_path: &Path, platform: Platform) -> PathBuf {
    if platform == Platform::XboxGamePass && game_path.join("Content").is_dir() {
        game_path.join("Content")
    } else {
        game_path.to_path_buf()
    }
}

#[cfg(test)]
mod tests {
    use std::fs::{self, File};

    use super::*;
    use crate::discovery::cache;
    use crate::discovery::hidden_paths;
    use crate::discovery::index;
    use crate::discovery::install_history;
    use crate::discovery::platform::{DiscoveryScanMode, Platform};
    use crate::discovery::test_sync::lock_discovery_test;
    use crate::discovery::utils;

    #[test]
    fn remove_game_from_discovery_targets_xbox_content_stats_path() {
        let _guard = lock_discovery_test();
        cache::clear_all();
        index::clear_all();
        hidden_paths::clear_all();

        let temp = tempfile::TempDir::new().unwrap();
        let game_dir = temp.path().join("Microsoft.HaloInfinite");
        let content_dir = game_dir.join("Content");
        fs::create_dir_all(&content_dir).unwrap();
        File::create(content_dir.join("content.bin"))
            .unwrap()
            .set_len(700 * 1024 * 1024)
            .unwrap();

        let discovered = utils::build_game_info_with_mode_and_stats_path(
            "Halo Infinite".to_owned(),
            game_dir.clone(),
            content_dir.clone(),
            Platform::XboxGamePass,
            DiscoveryScanMode::Full,
        );
        assert!(discovered.is_some());
        assert!(cache::lookup_stale(&content_dir).is_some());
        assert_eq!(
            install_history::max_observed_size(&content_dir),
            Some(700 * 1024 * 1024),
        );

        remove_game_from_discovery_inner(&game_dir, Platform::XboxGamePass);

        assert!(cache::lookup_stale(&content_dir).is_none());
        assert!(install_history::max_observed_size(&content_dir).is_none());
        let hidden_token = cache::compute_change_token(&content_dir, false);
        assert!(hidden_paths::should_hide(&content_dir, &hidden_token));
    }

    #[test]
    fn clear_discovery_cache_clears_hidden_paths_and_install_history() {
        let _guard = lock_discovery_test();
        clear_discovery_cache();

        let temp = tempfile::TempDir::new().unwrap();
        let game_dir = temp.path().join("DiscoveryResetGame");
        fs::create_dir_all(&game_dir).unwrap();
        File::create(game_dir.join("content.bin"))
            .unwrap()
            .set_len(700 * 1024 * 1024)
            .unwrap();

        hidden_paths::hide_path(&game_dir);
        install_history::record_authoritative_size(&game_dir, 6 * 1024 * 1024 * 1024);

        clear_discovery_cache();

        let hidden_token = cache::compute_change_token(&game_dir, false);
        assert!(!hidden_paths::should_hide(&game_dir, &hidden_token));
        assert!(install_history::max_observed_size(&game_dir).is_none());
    }

    #[test]
    fn clear_discovery_cache_entry_clears_xbox_content_hidden_state() {
        let _guard = lock_discovery_test();
        clear_discovery_cache();

        let temp = tempfile::TempDir::new().unwrap();
        let game_dir = temp.path().join("XboxResetGame");
        let content_dir = game_dir.join("Content");
        fs::create_dir_all(&content_dir).unwrap();
        File::create(content_dir.join("content.bin"))
            .unwrap()
            .set_len(700 * 1024 * 1024)
            .unwrap();

        hidden_paths::hide_path(&content_dir);
        install_history::record_authoritative_size(&content_dir, 6 * 1024 * 1024 * 1024);

        clear_discovery_cache_entry(game_dir.to_string_lossy().into_owned());

        let hidden_token = cache::compute_change_token(&content_dir, false);
        assert!(!hidden_paths::should_hide(&content_dir, &hidden_token));
        assert!(install_history::max_observed_size(&content_dir).is_none());
    }

    #[test]
    fn scan_custom_folder_returns_custom_platform_for_detected_install() {
        let _guard = lock_discovery_test();
        clear_discovery_cache();

        let temp = tempfile::TempDir::new().unwrap();
        let root = temp.path().join("Cairn");
        let data = root.join("Cairn_Data");
        fs::create_dir_all(&data).unwrap();
        File::create(root.join("Cairn.exe"))
            .unwrap()
            .set_len(512 * 1024)
            .unwrap();
        File::create(data.join("globalgamemanagers"))
            .unwrap()
            .set_len(2 * 1024 * 1024)
            .unwrap();

        let games = scan_custom_folder(root.to_string_lossy().into_owned()).unwrap();
        assert_eq!(games.len(), 1);
        let game = &games[0];
        assert_eq!(game.platform, FrbPlatform::Custom);
        assert_eq!(PathBuf::from(&game.path), root);
        assert_eq!(game.name, "Cairn");
        assert!(game.size_bytes > 0);
    }

    #[test]
    fn add_application_folder_returns_application_platform_for_exe_parent() {
        let _guard = lock_discovery_test();
        clear_discovery_cache();

        let temp = tempfile::TempDir::new().unwrap();
        let app_dir = temp.path().join("Toolbox");
        fs::create_dir_all(&app_dir).unwrap();
        File::create(app_dir.join("toolbox.exe"))
            .unwrap()
            .set_len(128 * 1024)
            .unwrap();
        File::create(app_dir.join("payload.bin"))
            .unwrap()
            .set_len(4 * 1024 * 1024)
            .unwrap();

        let app = add_application_folder(
            app_dir.join("toolbox.exe").to_string_lossy().into_owned(),
            Some("Toolbox".to_owned()),
        )
        .unwrap();

        assert_eq!(app.platform, FrbPlatform::Application);
        assert_eq!(PathBuf::from(&app.path), app_dir);
        assert_eq!(app.name, "Toolbox");
        assert!(app.size_bytes > 0);
    }

    #[test]
    fn hydrate_game_preserves_xbox_platform_and_root_path() {
        let _guard = lock_discovery_test();
        clear_discovery_cache();

        let temp = tempfile::TempDir::new().unwrap();
        let game_dir = temp.path().join("Microsoft.HaloInfinite");
        let content_dir = game_dir.join("Content");
        fs::create_dir_all(&content_dir).unwrap();
        File::create(content_dir.join("content.bin"))
            .unwrap()
            .set_len(700 * 1024 * 1024)
            .unwrap();

        let hydrated = hydrate_game(
            game_dir.to_string_lossy().into_owned(),
            "Halo Infinite".to_owned(),
            FrbPlatform::XboxGamePass,
        )
        .unwrap()
        .expect("xbox install should hydrate successfully");

        assert_eq!(hydrated.platform, FrbPlatform::XboxGamePass);
        assert_eq!(PathBuf::from(&hydrated.path), game_dir);
        assert_eq!(hydrated.name, "Halo Infinite");
        assert!(hydrated.size_bytes >= 700 * 1024 * 1024);
    }
}
