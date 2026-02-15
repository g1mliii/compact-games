use std::path::{Path, PathBuf};

use walkdir::WalkDir;

use super::platform::{GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

/// Minimum executable size to consider as a game (10MB).
const MIN_EXE_SIZE: u64 = 10 * 1024 * 1024;

/// Maximum scan depth for finding game-like folders.
const MAX_SCAN_DEPTH: usize = 3;

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
}

impl CustomScanner {
    pub fn new(paths: Vec<PathBuf>) -> Self {
        Self { paths }
    }
}

impl PlatformScanner for CustomScanner {
    fn scan(&self) -> Result<Vec<GameInfo>, ScanError> {
        let games: Vec<GameInfo> = self
            .paths
            .iter()
            .filter(|p| p.is_dir())
            .flat_map(|path| {
                scan_custom_path(path)
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
fn scan_custom_path(root: &Path) -> Result<Vec<GameInfo>, ScanError> {
    let mut games = Vec::new();

    // If the root itself looks like a game, add it directly
    if is_game_folder(root) {
        let name = root
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "Unknown Game".to_owned());

        if let Some(game) = utils::build_game_info(name, root.to_path_buf(), Platform::Custom) {
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
            utils::build_game_info(name, game_path, Platform::Custom)
        })
        .collect();

    utils::merge_games(&mut games, subdir_games);

    Ok(games)
}

/// Heuristic check: does this folder look like a game installation?
fn is_game_folder(path: &Path) -> bool {
    // Check for common game subdirectories up front.
    let has_game_subdir = GAME_INDICATORS
        .iter()
        .any(|indicator| path.join(indicator).is_dir());

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
        let metadata = entry.metadata().ok();

        if !has_large_exe {
            let is_exe = entry
                .path()
                .extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case("exe"));

            if is_exe {
                let name = entry.file_name().to_string_lossy().to_ascii_lowercase();
                if !is_non_game_exe(&name)
                    && metadata
                        .as_ref()
                        .is_some_and(|file_meta| file_meta.len() >= MIN_EXE_SIZE)
                {
                    has_large_exe = true;
                    if has_game_subdir {
                        return true;
                    }
                }
            }
        }

        // Quick size estimate: sample up to 50 files within shallow depth.
        if !has_game_subdir && sampled_files < 50 && entry.depth() <= 2 {
            if let Some(file_meta) = metadata.as_ref() {
                sample_size = sample_size.saturating_add(file_meta.len());
                sampled_files += 1;
            }
        }

        if has_large_exe && (has_game_subdir || sample_size >= MIN_GAME_SIZE) {
            return true;
        }
    }

    has_large_exe && (has_game_subdir || sample_size >= MIN_GAME_SIZE)
}

fn is_non_game_exe(name: &str) -> bool {
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
mod tests {
    use std::fs::File;

    use tempfile::TempDir;

    use super::*;

    #[test]
    fn custom_scanner_empty_paths_returns_empty() {
        let scanner = CustomScanner::new(Vec::new());
        let result = scanner.scan().unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn custom_scanner_nonexistent_path_returns_empty() {
        let scanner = CustomScanner::new(vec![PathBuf::from(r"C:\NonExistent\CustomGames")]);
        let result = scanner.scan().unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn scan_custom_path_includes_subdirs_when_root_matches() {
        let root = TempDir::new().unwrap();
        let root_path = root.path();

        std::fs::create_dir(root_path.join("data")).unwrap();
        let root_exe = root_path.join("rootgame.exe");
        File::create(&root_exe)
            .unwrap()
            .set_len(MIN_EXE_SIZE + 1)
            .unwrap();

        let sub_game_path = root_path.join("SubGame");
        std::fs::create_dir_all(sub_game_path.join("bin")).unwrap();
        let sub_exe = sub_game_path.join("subgame.exe");
        File::create(&sub_exe)
            .unwrap()
            .set_len(MIN_EXE_SIZE + 1)
            .unwrap();

        let games = scan_custom_path(root_path).unwrap();
        assert!(games.iter().any(|g| g.path == sub_game_path));
    }

    #[test]
    fn is_non_game_exe_filters_installers() {
        assert!(is_non_game_exe("unins000.exe"));
        assert!(is_non_game_exe("setup.exe"));
        assert!(is_non_game_exe("vcredist_x64.exe"));
        assert!(is_non_game_exe("dxsetup.exe"));
        assert!(!is_non_game_exe("game.exe"));
        assert!(!is_non_game_exe("portal2.exe"));
    }

    #[test]
    fn skip_folders_are_lowercase() {
        for folder in SKIP_FOLDERS {
            assert_eq!(*folder, folder.to_ascii_lowercase());
        }
    }
}
