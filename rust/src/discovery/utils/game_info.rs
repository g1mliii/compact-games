use std::path::{Path, PathBuf};

use walkdir::WalkDir;

use crate::discovery::cache::{self, CachedGameStats};
use crate::discovery::platform::{DiscoveryScanMode, GameInfo, Platform};

use super::stats::{dir_stats, dir_stats_quick};

mod logging;

use self::logging::log_candidate_decision;

const MIN_LIKELY_INSTALL_SIZE_BYTES: u64 = 512 * 1024 * 1024;
const MIN_GAME_EXE_SIZE_BYTES: u64 = 2 * 1024 * 1024;
const MIN_UNITY_BOOTSTRAP_EXE_SIZE_BYTES: u64 = 256 * 1024;
const INSTALL_PROBE_MAX_DEPTH: usize = 3;
const INSTALL_PROBE_MAX_FILES: usize = 256;
const UNITY_DATA_SUFFIX: &str = "_data";

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
    if !stats_path.exists() {
        cache::remove(&stats_path);
        log_candidate_decision(
            "skip",
            platform,
            &name,
            &stats_path,
            mode,
            "stats path missing",
        );
        return None;
    }

    if mode == DiscoveryScanMode::Quick {
        let include_probe = cache::has_entry(&stats_path);
        let token = cache::compute_change_token(&stats_path, include_probe);

        if let Some(cached) = cache::lookup(&stats_path, &token) {
            if !is_likely_installed_game(&stats_path, cached.logical_size, platform) {
                cache::remove(&stats_path);
                log_candidate_decision(
                    "skip",
                    platform,
                    &name,
                    &stats_path,
                    mode,
                    "token cache hit but candidate failed install probe",
                );
                return None;
            }
            log_candidate_decision(
                "accept",
                platform,
                &name,
                &stats_path,
                mode,
                "token cache hit",
            );
            return game_info_from_cached(name, game_path, platform, cached);
        }

        // Keep quick mode stable: if authoritative cache exists but token drifted,
        // use stale cached stats until hydration/full scan refreshes this entry.
        if let Some(stale_cached) = cache::lookup_stale(&stats_path) {
            if !is_likely_installed_game(&stats_path, stale_cached.logical_size, platform) {
                cache::remove(&stats_path);
                log_candidate_decision(
                    "skip",
                    platform,
                    &name,
                    &stats_path,
                    mode,
                    "stale cache fallback failed install probe",
                );
                return None;
            }

            log_candidate_decision(
                "accept",
                platform,
                &name,
                &stats_path,
                mode,
                "stale cache fallback",
            );
            return game_info_from_cached(name, game_path, platform, stale_cached);
        }

        let stats = dir_stats_quick(&stats_path);
        if stats.logical_size == 0 {
            cache::remove(&stats_path);
            log_candidate_decision(
                "skip",
                platform,
                &name,
                &stats_path,
                mode,
                "quick stats reported zero logical size",
            );
            return None;
        }

        if !is_likely_installed_game(&stats_path, stats.logical_size, platform) {
            cache::remove(&stats_path);
            log_candidate_decision(
                "skip",
                platform,
                &name,
                &stats_path,
                mode,
                "quick stats path failed install probe",
            );
            return None;
        }

        let is_directstorage = crate::safety::known_games::is_known_directstorage_game(&stats_path);
        log_candidate_decision(
            "accept",
            platform,
            &name,
            &stats_path,
            mode,
            "quick stats sampled (not persisted)",
        );
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
        if !is_likely_installed_game(&stats_path, cached.logical_size, platform) {
            cache::remove(&stats_path);
            log_candidate_decision(
                "skip",
                platform,
                &name,
                &stats_path,
                mode,
                "full token cache hit but candidate failed install probe",
            );
            return None;
        }
        log_candidate_decision(
            "accept",
            platform,
            &name,
            &stats_path,
            mode,
            "full token cache hit",
        );
        return game_info_from_cached(name, game_path, platform, cached);
    }

    let stats = dir_stats(&stats_path);
    if stats.logical_size == 0 {
        cache::remove(&stats_path);
        log_candidate_decision(
            "skip",
            platform,
            &name,
            &stats_path,
            mode,
            "full stats reported zero logical size",
        );
        return None;
    }

    if !is_likely_installed_game(&stats_path, stats.logical_size, platform) {
        cache::remove(&stats_path);
        log_candidate_decision(
            "skip",
            platform,
            &name,
            &stats_path,
            mode,
            "full stats path failed install probe",
        );
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

    log_candidate_decision(
        "accept",
        platform,
        &name,
        &stats_path,
        mode,
        "full stats refreshed cache",
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

fn is_likely_installed_game(path: &Path, logical_size: u64, platform: Platform) -> bool {
    if logical_size == 0 {
        return false;
    }

    if logical_size >= MIN_LIKELY_INSTALL_SIZE_BYTES {
        return true;
    }

    // Xbox UWP layouts may not expose a direct game executable at root.
    if platform == Platform::XboxGamePass && logical_size >= (256 * 1024 * 1024) {
        return true;
    }

    if has_unity_bootstrap_layout(path) {
        return true;
    }

    has_game_executable(path)
}

fn has_unity_bootstrap_layout(path: &Path) -> bool {
    let entries = match std::fs::read_dir(path) {
        Ok(entries) => entries,
        Err(_) => return false,
    };

    entries
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.path().is_dir())
        .any(|entry| {
            let folder_name = entry.file_name().to_string_lossy().into_owned();
            let folder_name_lower = folder_name.to_ascii_lowercase();
            if !folder_name_lower.ends_with(UNITY_DATA_SUFFIX) {
                return false;
            }

            let stem_len = folder_name.len().saturating_sub(UNITY_DATA_SUFFIX.len());
            if stem_len == 0 {
                return false;
            }

            let exe_stem = &folder_name[..stem_len];
            let exe_name = format!("{exe_stem}.exe");
            let exe_name_lower = exe_name.to_ascii_lowercase();
            if is_non_game_exe(&exe_name_lower) {
                return false;
            }

            path.join(exe_name)
                .metadata()
                .ok()
                .is_some_and(|meta| {
                    meta.is_file() && meta.len() >= MIN_UNITY_BOOTSTRAP_EXE_SIZE_BYTES
                })
        })
}

fn has_game_executable(path: &Path) -> bool {
    for (files_seen, entry) in WalkDir::new(path)
        .max_depth(INSTALL_PROBE_MAX_DEPTH)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .enumerate()
    {
        if files_seen >= INSTALL_PROBE_MAX_FILES {
            break;
        }

        let is_exe = entry
            .path()
            .extension()
            .is_some_and(|ext| ext.eq_ignore_ascii_case("exe"));
        if !is_exe {
            continue;
        }

        let exe_name = entry.file_name().to_string_lossy().to_ascii_lowercase();
        if is_non_game_exe(&exe_name) {
            continue;
        }

        let size = entry.metadata().ok().map(|m| m.len()).unwrap_or(0);
        if size >= MIN_GAME_EXE_SIZE_BYTES {
            return true;
        }
    }

    false
}

/// Returns true for executables that are known installers, redistributables,
/// or crash reporters -- not actual game binaries. Intentionally excludes
/// `"launcher"` because many games ship a `*Launcher.exe` as the main
/// entry point (see Lesson 67).
pub(crate) fn is_non_game_exe(name: &str) -> bool {
    name.contains("unins")
        || name.contains("setup")
        || name.contains("install")
        || name.contains("redist")
        || name.contains("vcredist")
        || name.contains("dxsetup")
        || name.contains("dotnet")
        || name == "ue4prereqsetup_x64.exe"
        || name == "crashreportclient.exe"
}

#[cfg(test)]
mod tests;
