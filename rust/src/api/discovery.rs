//! Game discovery API exposed to Flutter via FRB.

use std::path::PathBuf;

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

    let stats_path = if platform == Platform::XboxGamePass && game_path.join("Content").is_dir() {
        game_path.join("Content")
    } else {
        game_path.clone()
    };

    let game = utils::build_game_info_with_mode_and_stats_path(
        name,
        game_path,
        stats_path,
        platform,
        DiscoveryScanMode::Full,
    );

    Ok(game.map(FrbGameInfo::from))
}
