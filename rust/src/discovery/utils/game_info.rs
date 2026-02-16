use std::path::PathBuf;

use crate::discovery::cache::{self, CachedGameStats};
use crate::discovery::platform::{DiscoveryScanMode, GameInfo, Platform};

use super::stats::{dir_stats, dir_stats_quick};

/// Build a GameInfo from a name, path, and platform.
/// Returns None if the directory is empty.
pub fn build_game_info(name: String, game_path: PathBuf, platform: Platform) -> Option<GameInfo> {
    build_game_info_with_mode(name, game_path, platform, DiscoveryScanMode::Full)
}

pub fn build_game_info_with_mode(
    name: String,
    game_path: PathBuf,
    platform: Platform,
    mode: DiscoveryScanMode,
) -> Option<GameInfo> {
    build_game_info_with_mode_and_stats_path(name, game_path.clone(), game_path, platform, mode)
}

/// Build a GameInfo where metadata should be read from `stats_path` but
/// the returned game path should be `game_path` (used by Xbox Content folders).
pub fn build_game_info_with_mode_and_stats_path(
    name: String,
    game_path: PathBuf,
    stats_path: PathBuf,
    platform: Platform,
    mode: DiscoveryScanMode,
) -> Option<GameInfo> {
    if mode == DiscoveryScanMode::Quick {
        if let Some(cached) = cache::lookup_stale(&stats_path) {
            return game_info_from_cached(name, game_path, platform, cached);
        }

        let stats = dir_stats_quick(&stats_path);
        if stats.logical_size == 0 {
            return None;
        }

        let is_directstorage = crate::safety::known_games::is_known_directstorage_game(&stats_path);
        return Some(game_info_from_parts(
            name,
            game_path,
            platform,
            stats.logical_size,
            stats.physical_size,
            stats.is_compressed,
            is_directstorage,
        ));
    }

    let include_probe = cache::has_entry(&stats_path);
    let token = cache::compute_change_token(&stats_path, include_probe);
    if let Some(cached) = cache::lookup(&stats_path, &token) {
        return game_info_from_cached(name, game_path, platform, cached);
    }

    let stats = dir_stats(&stats_path);
    if stats.logical_size == 0 {
        return None;
    }

    let is_directstorage = crate::safety::directstorage::is_directstorage_game(&stats_path);
    cache::upsert(
        &stats_path,
        token,
        CachedGameStats::from_parts(
            stats.logical_size,
            stats.physical_size,
            stats.is_compressed,
            is_directstorage,
        ),
    );

    Some(game_info_from_parts(
        name,
        game_path,
        platform,
        stats.logical_size,
        stats.physical_size,
        stats.is_compressed,
        is_directstorage,
    ))
}

fn game_info_from_cached(
    name: String,
    game_path: PathBuf,
    platform: Platform,
    cached: CachedGameStats,
) -> Option<GameInfo> {
    if cached.logical_size == 0 {
        return None;
    }
    Some(game_info_from_parts(
        name,
        game_path,
        platform,
        cached.logical_size,
        cached.physical_size,
        cached.is_compressed,
        cached.is_directstorage,
    ))
}

fn game_info_from_parts(
    name: String,
    game_path: PathBuf,
    platform: Platform,
    logical_size: u64,
    physical_size: u64,
    is_compressed: bool,
    is_directstorage: bool,
) -> GameInfo {
    GameInfo {
        name,
        path: game_path,
        platform,
        size_bytes: logical_size,
        compressed_size: is_compressed.then_some(physical_size),
        is_compressed,
        is_directstorage,
        excluded: false,
        last_played: None,
    }
}
