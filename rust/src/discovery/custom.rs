use std::path::{Path, PathBuf};

use rayon::prelude::*;
use walkdir::WalkDir;

use super::platform::{DiscoveryScanMode, GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

/// Minimum executable size to consider as a game (2MB).
const MIN_EXE_SIZE: u64 = 2 * 1024 * 1024;
/// Unity bootstrap executables are often smaller than main game binaries.
const MIN_UNITY_BOOTSTRAP_EXE_SIZE: u64 = 256 * 1024;
const UNITY_DATA_SUFFIX: &str = "_data";
const STEAM_APPS_FOLDER: &str = "steamapps";
const STEAM_COMMON_FOLDER: &str = "common";
const STEAM_LIBRARY_FOLDER: &str = "steamlibrary";

/// Maximum scan depth for finding game-like folders.
const MAX_SCAN_DEPTH: usize = 6;
const MAX_SIZE_SAMPLE_DEPTH: usize = 3;
const MAX_SIZE_SAMPLE_FILES: usize = 50;
/// Max non-directory entries allowed in a wrapper folder (e.g. a readme or shortcut).
const MAX_WRAPPER_LOOSE_FILES: usize = 3;

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

    // Collect raw subdirectory entries (cheap read_dir, no I/O-heavy heuristics).
    let entries = match std::fs::read_dir(root) {
        Ok(e) => e,
        Err(e) => {
            log::warn!("Cannot read custom path {}: {e}", root.display());
            return Err(ScanError::PermissionDenied(root.to_path_buf()));
        }
    };

    let raw_entries: Vec<(String, PathBuf)> = entries
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let path = e.path();
            if !path.is_dir() {
                return None;
            }
            let name = e.file_name().to_string_lossy().into_owned();
            let name_lower = name.to_ascii_lowercase();
            if SKIP_FOLDERS.iter().any(|skip| name_lower == *skip) {
                return None;
            }
            Some((name, path))
        })
        .collect();

    // Phase 1: identify game candidates via heuristics (is_game_folder /
    // wrapper detection). Each check is independent so we can parallelise
    // when the candidate list is large enough to justify the overhead.
    let resolve = |name: String, path: PathBuf| -> Option<(String, PathBuf)> {
        let resolved = resolve_game_candidate(&path)?;
        let display_name = match resolved.inner_name {
            Some(inner) => inner,
            None => name,
        };
        Some((display_name, resolved.path))
    };
    let candidates: Vec<(String, PathBuf)> = if raw_entries.len() >= PARALLEL_HEURISTIC_MIN {
        raw_entries
            .into_par_iter()
            .filter_map(|(name, path)| resolve(name, path))
            .collect()
    } else {
        raw_entries
            .into_iter()
            .filter_map(|(name, path)| resolve(name, path))
            .collect()
    };

    // Phase 2: build metadata for accepted candidates. This goes through
    // the shared build_games_from_candidates helper which already applies
    // rayon parallelisation on SSDs with enough candidates.
    let subdir_games = utils::build_games_from_candidates(root, candidates, Platform::Custom, mode);
    utils::merge_games(&mut games, subdir_games);

    Ok(games)
}

/// Minimum subdirectory count before parallelising the is_game_folder
/// heuristic phase. Below this the rayon thread-pool overhead dominates.
const PARALLEL_HEURISTIC_MIN: usize = 6;

struct ResolvedCandidate {
    path: PathBuf,
    /// When the candidate was resolved via wrapper unwrap, this is the
    /// inner folder's basename — used as the display name since users
    /// often rename the outer wrapper to something short/arbitrary.
    inner_name: Option<String>,
}

/// Returns the resolved game path if `path` (or its single wrapped child)
/// passes `is_game_folder`. Returns `None` if neither qualifies.
fn resolve_game_candidate(path: &Path) -> Option<ResolvedCandidate> {
    if is_game_folder(path) {
        return Some(ResolvedCandidate {
            path: path.to_path_buf(),
            inner_name: None,
        });
    }

    // Wrapper folder pattern: a folder containing exactly one subfolder
    // and few/no loose files (e.g. "Goblin-Nest/Goblin Nest/<game files>").
    // Relax the heuristic for the inner folder: the wrapper pattern itself
    // is strong signal of a game install, so a valid large exe is enough
    // even when the size sample is below MIN_GAME_SIZE.
    if let Some(inner) = unwrap_single_subfolder(path) {
        if is_game_folder_relaxed(&inner) {
            let inner_name = inner
                .file_name()
                .map(|n| n.to_string_lossy().into_owned());
            log::debug!(
                "Custom: detected wrapper folder, inner=\"{}\"",
                inner.display()
            );
            return Some(ResolvedCandidate {
                path: inner,
                inner_name,
            });
        }
    }

    None
}

/// Like `is_game_folder` but trusts a valid large exe without requiring
/// either a game-indicator subdir or a MIN_GAME_SIZE size sample. Use only
/// when surrounding context (wrapper pattern) already indicates game intent.
fn is_game_folder_relaxed(path: &Path) -> bool {
    if is_known_library_container(path) {
        return false;
    }
    if has_unity_layout(path) {
        return true;
    }
    if is_game_folder(path) {
        return true;
    }
    has_valid_large_exe(path)
}

fn has_valid_large_exe(path: &Path) -> bool {
    WalkDir::new(path)
        .max_depth(MAX_SCAN_DEPTH)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .any(|entry| {
            let is_exe = entry
                .path()
                .extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case("exe"));
            if !is_exe {
                return false;
            }
            let name = entry.file_name().to_string_lossy().to_ascii_lowercase();
            if is_non_game_exe(&name) {
                return false;
            }
            entry
                .metadata()
                .ok()
                .is_some_and(|m| m.len() >= MIN_EXE_SIZE)
        })
}

/// If `path` contains exactly one subdirectory and at most a few loose files,
/// return that subdirectory. This handles the common pattern where an extracted
/// archive creates a wrapper folder around the actual game folder.
///
/// Designed for fast early-exit: bails as soon as a second subdir or too many
/// files are seen, so the cost for non-wrapper folders is a partial `read_dir`.
fn unwrap_single_subfolder(path: &Path) -> Option<PathBuf> {
    let entries = std::fs::read_dir(path).ok()?;
    let mut sole_subdir: Option<PathBuf> = None;
    let mut file_count = 0_usize;

    for entry in entries.filter_map(|e| e.ok()) {
        let ft = entry.file_type().ok()?;
        if ft.is_dir() {
            if sole_subdir.is_some() {
                return None; // second subdir → not a wrapper
            }
            sole_subdir = Some(entry.path());
        } else {
            file_count += 1;
            if file_count > MAX_WRAPPER_LOOSE_FILES {
                return None;
            }
        }
    }

    sole_subdir
}

/// Heuristic check: does this folder look like a game installation?
fn is_game_folder(path: &Path) -> bool {
    if is_known_library_container(path) {
        return false;
    }

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

fn is_known_library_container(path: &Path) -> bool {
    let Some(folder_name) = path
        .file_name()
        .map(|name| name.to_string_lossy().to_ascii_lowercase())
    else {
        return false;
    };

    if folder_name == STEAM_LIBRARY_FOLDER && path.join(STEAM_APPS_FOLDER).is_dir() {
        return true;
    }

    if folder_name == STEAM_APPS_FOLDER {
        if path.join(STEAM_COMMON_FOLDER).is_dir() {
            return true;
        }

        if std::fs::read_dir(path).ok().is_some_and(|entries| {
            entries.filter_map(|entry| entry.ok()).any(|entry| {
                entry.path().is_file()
                    && entry
                        .file_name()
                        .to_string_lossy()
                        .to_ascii_lowercase()
                        .starts_with("appmanifest_")
            })
        }) {
            return true;
        }
    }

    if folder_name == STEAM_COMMON_FOLDER {
        let parent_name = path
            .parent()
            .and_then(|parent| parent.file_name())
            .map(|name| name.to_string_lossy().to_ascii_lowercase());
        if parent_name.as_deref() == Some(STEAM_APPS_FOLDER) {
            return true;
        }
    }

    false
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
