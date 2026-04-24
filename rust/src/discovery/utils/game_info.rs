use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use walkdir::WalkDir;

use crate::discovery::cache::{self, CachedGameStats};
use crate::discovery::hidden_paths;
use crate::discovery::index;
use crate::discovery::install_history;
use crate::discovery::platform::{DiscoveryScanMode, GameInfo, Platform};

use super::stats::{dir_stats, dir_stats_quick};

mod logging;

use self::logging::log_candidate_decision;

const MIN_LIKELY_INSTALL_SIZE_BYTES: u64 = 512 * 1024 * 1024;
/// Folders above this threshold are accepted as games without an exe probe.
/// Between MIN_LIKELY_INSTALL_SIZE_BYTES and this value an exe probe is required,
/// which filters out sub-2 GB uninstall remnants that left no game binary behind.
const LARGE_GAME_THRESHOLD_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const MIN_GAME_EXE_SIZE_BYTES: u64 = 2 * 1024 * 1024;
const MIN_UNITY_BOOTSTRAP_EXE_SIZE_BYTES: u64 = 256 * 1024;
const MIN_REMNANT_HISTORY_SIZE_BYTES: u64 = 4 * 1024 * 1024 * 1024;
const MAX_REMNANT_CURRENT_SIZE_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const REMNANT_SHRINK_RATIO_DEN: u64 = 5;
const INSTALL_PROBE_MAX_DEPTH: usize = 3;
const INSTALL_PROBE_MAX_FILES: usize = 256;
const UNITY_DATA_SUFFIX: &str = "_data";

fn evict_candidate(path: &Path) {
    cache::remove(path);
    index::remove(path);
}

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
    let stats_path = game_path.clone();
    build_game_info_with_mode_and_stats_path(name, game_path, stats_path, platform, mode)
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
        evict_candidate(&stats_path);
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

    let hidden_token = cache::compute_change_token(&stats_path, false);
    if hidden_paths::should_hide(&stats_path, &hidden_token) {
        evict_candidate(&stats_path);
        log_candidate_decision(
            "skip",
            platform,
            &name,
            &stats_path,
            mode,
            "path hidden by user until install changes",
        );
        return None;
    }

    let include_probe = cache::has_entry(&stats_path);
    let token = cache::compute_change_token(&stats_path, include_probe);

    if mode == DiscoveryScanMode::Quick {
        if let Some(cached) = cache::lookup(&stats_path, &token) {
            if !is_likely_installed_game(&stats_path, cached.logical_size, platform) {
                evict_candidate(&stats_path);
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
            let current_sample_logical_size = token
                .probe_total_size
                .unwrap_or_else(|| dir_stats_quick(&stats_path).logical_size);
            if current_sample_logical_size == 0 {
                evict_candidate(&stats_path);
                log_candidate_decision(
                    "skip",
                    platform,
                    &name,
                    &stats_path,
                    mode,
                    "stale cache fallback quick stats reported zero logical size",
                );
                return None;
            }

            if !is_plausible_current_install_for_stale_cache(
                &stats_path,
                current_sample_logical_size,
                platform,
            ) {
                evict_candidate(&stats_path);
                log_candidate_decision(
                    "skip",
                    platform,
                    &name,
                    &stats_path,
                    mode,
                    "stale cache fallback current quick stats failed install probe",
                );
                return None;
            }

            if is_probable_uninstall_remnant(&stats_path, current_sample_logical_size) {
                evict_candidate(&stats_path);
                log_candidate_decision(
                    "skip",
                    platform,
                    &name,
                    &stats_path,
                    mode,
                    "stale cache fallback current quick stats indicate prior install shrank to remnant",
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
            evict_candidate(&stats_path);
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
            evict_candidate(&stats_path);
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

    if let Some(mut indexed_game) = index::lookup(&stats_path, &token) {
        if !is_likely_installed_game(&stats_path, indexed_game.size_bytes, platform) {
            evict_candidate(&stats_path);
            log_candidate_decision(
                "skip",
                platform,
                &name,
                &stats_path,
                mode,
                "incremental index hit but candidate failed install probe",
            );
            return None;
        }

        indexed_game.name = name;
        indexed_game.path = game_path;
        indexed_game.platform = platform;
        refresh_dynamic_game_metadata(&mut indexed_game);
        index::upsert(&stats_path, token.clone(), &indexed_game);
        install_history::record_authoritative_size(&stats_path, indexed_game.size_bytes);
        log_candidate_decision(
            "accept",
            platform,
            &indexed_game.name,
            &stats_path,
            mode,
            "incremental index hit",
        );
        return Some(indexed_game);
    }

    // Full scan uses TTL-aware lookup: entries older than 10 minutes are
    // re-verified even when the change token still matches.
    if let Some(cached) = cache::lookup_fresh(&stats_path, &token) {
        if !is_likely_installed_game(&stats_path, cached.logical_size, platform) {
            evict_candidate(&stats_path);
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
        install_history::record_authoritative_size(&stats_path, cached.logical_size);
        if let Some(game) = game_info_from_cached(name, game_path, platform, cached) {
            index::upsert(&stats_path, token.clone(), &game);
            return Some(game);
        }
        return None;
    }

    let stats = dir_stats(&stats_path);
    if stats.logical_size == 0 {
        evict_candidate(&stats_path);
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
        evict_candidate(&stats_path);
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

    if is_probable_uninstall_remnant(&stats_path, stats.logical_size) {
        evict_candidate(&stats_path);
        log_candidate_decision(
            "skip",
            platform,
            &name,
            &stats_path,
            mode,
            "full stats indicate prior install shrank to remnant",
        );
        return None;
    }

    let is_directstorage = crate::safety::directstorage::is_directstorage_game(&stats_path);
    install_history::record_authoritative_size(&stats_path, stats.logical_size);
    cache::upsert(
        &stats_path,
        token.clone(),
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

    let game = game_info_from_parts(
        name,
        game_path,
        platform,
        stats.logical_size,
        stats.physical_size,
        stats.is_compressed,
        is_directstorage,
    );
    index::upsert(&stats_path, token, &game);
    Some(game)
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
    let mut game = GameInfo {
        name,
        path: game_path,
        platform,
        size_bytes: logical_size,
        compressed_size: is_compressed.then_some(physical_size),
        is_compressed,
        is_directstorage,
        is_unsupported: false,
        excluded: false,
        steam_app_id: None,
        last_played: None,
    };
    refresh_dynamic_game_metadata(&mut game);
    game
}

pub(crate) fn refresh_dynamic_game_metadata(game: &mut GameInfo) {
    game.is_unsupported = crate::safety::unsupported_games::is_unsupported_game(&game.path);
    // Reuse `last_played` transport slot as "last compressed" timestamp.
    // The old last-played source is not currently populated.
    game.last_played = compression_timestamp_for_game_path(&game.path, game.is_compressed);
}

fn compression_timestamp_for_game_path(path: &Path, is_compressed: bool) -> Option<SystemTime> {
    if !is_compressed {
        return None;
    }

    crate::compression::history::latest_compression_timestamp_ms(path)
        .and_then(|millis| UNIX_EPOCH.checked_add(Duration::from_millis(millis)))
}

fn is_likely_installed_game(path: &Path, logical_size: u64, platform: Platform) -> bool {
    // Application folders are user-chosen; skip game-likeness heuristics.
    if platform == Platform::Application {
        return logical_size > 0;
    }

    if logical_size == 0 {
        return false;
    }

    // Very large folders are almost certainly real game installs; skip exe probe.
    if logical_size >= LARGE_GAME_THRESHOLD_BYTES {
        return true;
    }

    if has_unity_bootstrap_layout(path) {
        return true;
    }

    if platform == Platform::XboxGamePass && logical_size >= (256 * 1024 * 1024) {
        return true;
    }

    if logical_size < MIN_LIKELY_INSTALL_SIZE_BYTES {
        // Custom folders come from user-curated "Games" directories where small
        // indie titles are common. Allow them through if they contain a real
        // game executable, rather than applying the launcher-oriented size floor.
        return platform == Platform::Custom && has_game_executable(path);
    }

    has_game_executable(path)
}

/// Validates stale-cache fallback against the *current* filesystem view.
///
/// Quick stats are intentionally shallow, so a legitimate install may still
/// look "small" when most content sits deeper than the quick-scan depth.
/// For stale authoritative cache entries, allow an executable-backed install to
/// remain plausible even when the current quick sample falls below the normal
/// size floor.
fn is_plausible_current_install_for_stale_cache(
    path: &Path,
    logical_size: u64,
    platform: Platform,
) -> bool {
    if logical_size == 0 {
        return false;
    }

    if is_likely_installed_game(path, logical_size, platform) {
        return true;
    }

    has_unity_bootstrap_layout(path) || has_game_executable(path)
}

fn is_probable_uninstall_remnant(path: &Path, logical_size: u64) -> bool {
    if logical_size == 0 || logical_size > MAX_REMNANT_CURRENT_SIZE_BYTES {
        return false;
    }

    let Some(max_observed_size) = install_history::max_observed_size(path) else {
        return false;
    };

    if max_observed_size < MIN_REMNANT_HISTORY_SIZE_BYTES {
        return false;
    }

    logical_size.saturating_mul(REMNANT_SHRINK_RATIO_DEN) <= max_observed_size
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

            path.join(exe_name).metadata().ok().is_some_and(|meta| {
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
