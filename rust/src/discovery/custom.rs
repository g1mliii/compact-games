use std::path::{Path, PathBuf};

use walkdir::WalkDir;

use super::platform::{DiscoveryScanMode, GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

/// Minimum executable size to consider as a game (2MB).
const MIN_EXE_SIZE: u64 = 2 * 1024 * 1024;
/// Unity bootstrap executables are often smaller than main game binaries.
const MIN_UNITY_BOOTSTRAP_EXE_SIZE: u64 = 256 * 1024;
const UNITY_DATA_SUFFIX: &str = "_data";

/// Maximum scan depth for finding game-like folders.
const MAX_SCAN_DEPTH: usize = 6;
const MAX_SIZE_SAMPLE_DEPTH: usize = 3;
const MAX_SIZE_SAMPLE_FILES: usize = 50;

/// Non-game folders to always skip.
const SKIP_FOLDERS: &[&str] = &[
    "windows",
    "system32",
    "syswow64",
    "program files",
    "programdata",
    "$recycle.bin",
    "system volume information",
    "recovery",
    "msocache",
    "node_modules",
    ".git",
    ".vs",
    "__pycache__",
];

/// Common game subdirectories that indicate a game folder.
const GAME_INDICATORS: &[&str] = &[
    "bin",
    "data",
    "assets",
    "engine",
    "content",
    "shaders",
    "levels",
    "maps",
    "textures",
    "sounds",
    "music",
    "localization",
];

/// Minimum folder size to consider as a game without game indicator subdirs (100MB).
const MIN_GAME_SIZE: u64 = 100 * 1024 * 1024;

pub struct CustomScanner {
    paths: Vec<PathBuf>,
    include_root_candidate: bool,
}

impl CustomScanner {
    pub fn new(paths: Vec<PathBuf>) -> Self {
        Self {
            paths,
            include_root_candidate: true,
        }
    }

    pub fn new_library_roots(paths: Vec<PathBuf>) -> Self {
        Self {
            paths,
            include_root_candidate: false,
        }
    }
}

impl PlatformScanner for CustomScanner {
    fn scan(&self, mode: DiscoveryScanMode) -> Result<Vec<GameInfo>, ScanError> {
        let games: Vec<GameInfo> = self
            .paths
            .iter()
            .filter(|p| p.is_dir())
            .flat_map(|path| {
                scan_custom_path(path, mode, self.include_root_candidate)
                    .inspect_err(|e| {
                        log::warn!("Failed to scan custom path {}: {e}", path.display());
                    })
                    .unwrap_or_default()
            })
            .collect();

        log::info!("Custom: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "Custom"
    }
}

/// Scan a user-provided path for game-like folders.
fn scan_custom_path(
    root: &Path,
    mode: DiscoveryScanMode,
    include_root_candidate: bool,
) -> Result<Vec<GameInfo>, ScanError> {
    let mut games = Vec::new();

    // If the root itself looks like a game, add it directly
    if include_root_candidate && is_game_folder(root) {
        let name = root
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "Unknown Game".to_owned());

        if let Some(game) =
            utils::build_game_info_with_mode(name, root.to_path_buf(), Platform::Custom, mode)
        {
            games.push(game);
        }
    }

    // Otherwise scan subdirectories for game folders
    let entries = match std::fs::read_dir(root) {
        Ok(e) => e,
        Err(e) => {
            log::warn!("Cannot read custom path {}: {e}", root.display());
            return Err(ScanError::PermissionDenied(root.to_path_buf()));
        }
    };

    let subdir_games: Vec<GameInfo> = entries
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let game_path = e.path();
            if !game_path.is_dir() {
                return None;
            }

            let folder_name = e.file_name().to_string_lossy().into_owned();
            let folder_name_lower = folder_name.to_ascii_lowercase();
            if SKIP_FOLDERS.iter().any(|skip| folder_name_lower == *skip) {
                return None;
            }

            if !is_game_folder(&game_path) {
                return None;
            }

            let name = folder_name;
            utils::build_game_info_with_mode(name, game_path, Platform::Custom, mode)
        })
        .collect();

    utils::merge_games(&mut games, subdir_games);

    Ok(games)
}

/// Heuristic check: does this folder look like a game installation?
fn is_game_folder(path: &Path) -> bool {
    if has_unity_layout(path) {
        return true;
    }

    // Check for common game subdirectories up front.
    let has_game_subdir = GAME_INDICATORS
        .iter()
        .any(|indicator| path.join(indicator).is_dir())
        || has_nested_game_indicator_subdir(path);

    let mut has_large_exe = false;
    let mut sample_size: u64 = 0;
    let mut sampled_files: usize = 0;

    // Single walk for both executable detection and shallow size sampling.
    for entry in WalkDir::new(path)
        .max_depth(MAX_SCAN_DEPTH)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
    {
        let should_sample = !has_game_subdir
            && sampled_files < MAX_SIZE_SAMPLE_FILES
            && entry.depth() <= MAX_SIZE_SAMPLE_DEPTH;

        let mut should_check_exe_size = false;
        if !has_large_exe {
            let is_exe = entry
                .path()
                .extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case("exe"));
            if is_exe {
                let name = entry.file_name().to_string_lossy().to_ascii_lowercase();
                should_check_exe_size = !is_non_game_exe(&name);
            }
        }

        if should_check_exe_size || should_sample {
            if let Ok(file_meta) = entry.metadata() {
                let file_len = file_meta.len();

                if should_check_exe_size && file_len >= MIN_EXE_SIZE {
                    has_large_exe = true;
                    if has_game_subdir {
                        return true;
                    }
                }

                if should_sample {
                    sample_size = sample_size.saturating_add(file_len);
                    sampled_files += 1;
                }
            }
        }

        if has_large_exe && (has_game_subdir || sample_size >= MIN_GAME_SIZE) {
            return true;
        }
    }

    has_large_exe && (has_game_subdir || sample_size >= MIN_GAME_SIZE)
}

fn has_nested_game_indicator_subdir(path: &Path) -> bool {
    let entries = match std::fs::read_dir(path) {
        Ok(entries) => entries,
        Err(_) => return false,
    };

    entries
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|child| child.is_dir())
        .any(|child| {
            GAME_INDICATORS
                .iter()
                .any(|indicator| child.join(indicator).is_dir())
        })
}

fn has_unity_layout(path: &Path) -> bool {
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

            let exe_path = path.join(exe_name);
            exe_path
                .metadata()
                .ok()
                .is_some_and(|meta| meta.is_file() && meta.len() >= MIN_UNITY_BOOTSTRAP_EXE_SIZE)
        })
}

// Use the canonical shared version from utils.
use super::utils::is_non_game_exe;

#[cfg(test)]
mod tests;
