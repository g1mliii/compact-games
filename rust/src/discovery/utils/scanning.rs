use std::path::{Path, PathBuf};

use rayon::prelude::*;

use crate::discovery::cache;
use crate::discovery::platform::{DiscoveryScanMode, GameInfo, Platform, PlatformScanner};
use crate::discovery::storage::{
    has_any_hdd_disk, has_any_ssd_disk, storage_class_for_path, StorageClass,
};

use super::dedupe::merge_games;
use super::game_info::build_game_info_with_mode;

const PARALLEL_MIN_CANDIDATES: usize = 3;
const PARALLEL_UNKNOWN_MIN_CANDIDATES: usize = 8;

/// Scan a directory's immediate subdirectories for games.
/// Each subdirectory name is used as the game name.
pub fn scan_game_subdirs(
    games_path: &Path,
    platform: Platform,
    mode: DiscoveryScanMode,
) -> Vec<GameInfo> {
    let entries = match std::fs::read_dir(games_path) {
        Ok(e) => e,
        Err(e) => {
            log::warn!("Cannot read directory {}: {}", games_path.display(), e);
            return Vec::new();
        }
    };

    let candidates: Vec<(String, PathBuf)> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .map(|e| (e.file_name().to_string_lossy().into_owned(), e.path()))
        .collect();

    build_games_from_candidates(games_path, candidates, platform, mode)
}

pub fn build_games_from_candidates(
    scan_root: &Path,
    candidates: Vec<(String, PathBuf)>,
    platform: Platform,
    mode: DiscoveryScanMode,
) -> Vec<GameInfo> {
    if candidates.is_empty() {
        return Vec::new();
    }

    if should_parallelize_subdir_scan(scan_root, mode, candidates.len()) {
        log::debug!(
            "Parallel game metadata scan enabled for {} ({} candidates)",
            scan_root.display(),
            candidates.len()
        );
        return candidates
            .into_par_iter()
            .filter_map(|(name, path)| build_game_info_with_mode(name, path, platform, mode))
            .collect();
    }

    candidates
        .into_iter()
        .filter_map(|(name, path)| build_game_info_with_mode(name, path, platform, mode))
        .collect()
}

fn should_parallelize_subdir_scan(
    games_path: &Path,
    mode: DiscoveryScanMode,
    candidate_count: usize,
) -> bool {
    if mode != DiscoveryScanMode::Full || candidate_count < PARALLEL_MIN_CANDIDATES {
        return false;
    }

    match storage_class_for_path(games_path) {
        StorageClass::Hdd => false,
        StorageClass::Ssd => true,
        StorageClass::Unknown => {
            candidate_count >= PARALLEL_UNKNOWN_MIN_CANDIDATES && num_cpus::get() >= 8
        }
    }
}

/// Run all platform scanners and return merged, deduplicated results.
///
/// Individual scanner failures are logged but do not abort the scan.
/// This function encapsulates scanner instantiation so callers don't
/// need to depend on individual scanner types.
pub fn scan_all_platforms() -> Vec<GameInfo> {
    scan_all_platforms_with_mode(DiscoveryScanMode::Full)
}

pub fn scan_all_platforms_with_mode(mode: DiscoveryScanMode) -> Vec<GameInfo> {
    let tasks = scanner_tasks();
    let mut all_games = Vec::new();

    if should_parallelize_platform_scanners(mode) {
        let batches: Vec<Vec<GameInfo>> = tasks
            .into_par_iter()
            .map(|task| run_scanner_task(task, mode))
            .collect();
        for games in batches {
            merge_games(&mut all_games, games);
        }
    } else {
        for task in tasks {
            let games = run_scanner_task(task, mode);
            merge_games(&mut all_games, games);
        }
    }

    cache::persist_if_dirty();
    all_games
}

fn should_parallelize_platform_scanners(mode: DiscoveryScanMode) -> bool {
    let cpu_count = num_cpus::get();
    if cpu_count < 4 {
        return false;
    }

    if mode == DiscoveryScanMode::Quick {
        return true;
    }

    #[cfg(windows)]
    {
        let has_hdd = has_any_hdd_disk();
        let has_ssd = has_any_ssd_disk();

        if has_hdd && !has_ssd {
            // Pure-HDD systems remain conservative for traversal-heavy full scans.
            return false;
        }

        if has_hdd && has_ssd {
            // Mixed systems can still benefit, but require stronger CPU headroom.
            return cpu_count >= 8;
        }

        cpu_count >= 6
    }

    #[cfg(not(windows))]
    {
        true
    }
}

#[derive(Clone, Copy)]
enum ScannerTask {
    Steam,
    Epic,
    Gog,
    Ubisoft,
    Ea,
    BattleNet,
    Xbox,
}

fn scanner_tasks() -> Vec<ScannerTask> {
    vec![
        ScannerTask::Steam,
        ScannerTask::Epic,
        ScannerTask::Gog,
        ScannerTask::Ubisoft,
        ScannerTask::Ea,
        ScannerTask::BattleNet,
        ScannerTask::Xbox,
    ]
}

fn run_scanner_task(task: ScannerTask, mode: DiscoveryScanMode) -> Vec<GameInfo> {
    use crate::discovery::battlenet::BattleNetScanner;
    use crate::discovery::ea::EaScanner;
    use crate::discovery::epic::EpicScanner;
    use crate::discovery::gog::GogScanner;
    use crate::discovery::steam::SteamScanner;
    use crate::discovery::ubisoft::UbisoftScanner;
    use crate::discovery::xbox::XboxScanner;

    match task {
        ScannerTask::Steam => collect_scanner_results(SteamScanner::new(), mode),
        ScannerTask::Epic => collect_scanner_results(EpicScanner::new(), mode),
        ScannerTask::Gog => collect_scanner_results(GogScanner {}, mode),
        ScannerTask::Ubisoft => collect_scanner_results(UbisoftScanner {}, mode),
        ScannerTask::Ea => collect_scanner_results(EaScanner {}, mode),
        ScannerTask::BattleNet => collect_scanner_results(BattleNetScanner {}, mode),
        ScannerTask::Xbox => collect_scanner_results(XboxScanner::new(), mode),
    }
}

fn collect_scanner_results<S: PlatformScanner>(
    scanner: S,
    mode: DiscoveryScanMode,
) -> Vec<GameInfo> {
    match scanner.scan(mode) {
        Ok(games) => {
            log::info!("{}: found {} games", scanner.platform_name(), games.len());
            games
        }
        Err(e) => {
            log::warn!("{}: scan failed: {e}", scanner.platform_name());
            Vec::new()
        }
    }
}

/// Run a custom folder scan and return results.
pub fn scan_custom_paths(
    paths: Vec<PathBuf>,
) -> Result<Vec<GameInfo>, crate::discovery::scan_error::ScanError> {
    scan_custom_paths_with_mode(paths, DiscoveryScanMode::Full)
}

pub fn scan_custom_paths_with_mode(
    paths: Vec<PathBuf>,
    mode: DiscoveryScanMode,
) -> Result<Vec<GameInfo>, crate::discovery::scan_error::ScanError> {
    use crate::discovery::custom::CustomScanner;

    let result = CustomScanner::new(paths).scan(mode);
    cache::persist_if_dirty();
    result
}
