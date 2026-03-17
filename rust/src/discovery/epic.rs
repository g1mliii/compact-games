use std::path::{Path, PathBuf};

use super::platform::{DiscoveryScanMode, GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

const DEFAULT_EPIC_PATH: &str = r"C:\Program Files\Epic Games";

pub struct EpicScanner {
    epic_path: PathBuf,
}

impl EpicScanner {
    pub fn new() -> Self {
        Self {
            epic_path: PathBuf::from(DEFAULT_EPIC_PATH),
        }
    }

    pub fn with_path(epic_path: PathBuf) -> Self {
        Self { epic_path }
    }
}

impl Default for EpicScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformScanner for EpicScanner {
    fn scan(&self, mode: DiscoveryScanMode) -> Result<Vec<GameInfo>, ScanError> {
        // Manifests first: they carry the authoritative DisplayName (e.g. "Rocket League",
        // not the internal AppName "Sugar" found in .egstore/.mancpn files).
        let mut games = scan_epic_manifests(mode);

        // Dir scan fills in any installs not covered by a manifest entry.
        // Paths already present in `games` are silently skipped by merge_games.
        if self.epic_path.is_dir() {
            utils::merge_games(&mut games, scan_epic_dir(&self.epic_path, mode));
        }

        log::info!("Epic Games: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "Epic Games"
    }
}

/// Scan the Epic Games install directory for game folders.
fn scan_epic_dir(epic_path: &Path, mode: DiscoveryScanMode) -> Vec<GameInfo> {
    let entries = match std::fs::read_dir(epic_path) {
        Ok(e) => e,
        Err(e) => {
            log::warn!("Cannot read Epic directory {}: {e}", epic_path.display());
            return Vec::new();
        }
    };

    let candidates: Vec<(String, PathBuf)> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .filter_map(|e| {
            let game_path = e.path();
            let folder_name = e.file_name().to_string_lossy().into_owned();

            if is_epic_system_folder(&folder_name) {
                return None;
            }

            // Use the folder name directly. The AppName field in .egstore/*.mancpn
            // is Epic's internal app identifier (e.g. "Sugar" for Rocket League), NOT
            // a display name. The authoritative DisplayName comes from the launcher's
            // .item manifest files, which are scanned first via scan_epic_manifests.
            Some((folder_name, game_path))
        })
        .collect();

    utils::build_games_from_candidates(epic_path, candidates, Platform::EpicGames, mode)
}

/// Scan Epic launcher .item manifest files for installed games.
fn scan_epic_manifests(mode: DiscoveryScanMode) -> Vec<GameInfo> {
    let program_data = std::env::var("PROGRAMDATA").ok();
    let manifests_path = program_data
        .map(|pd| {
            PathBuf::from(pd)
                .join("Epic")
                .join("EpicGamesLauncher")
                .join("Data")
                .join("Manifests")
        })
        .filter(|p| p.is_dir());

    let Some(manifests_path) = manifests_path else {
        let alt = PathBuf::from(r"C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests");
        if !alt.is_dir() {
            return Vec::new();
        }
        return scan_manifest_files(&alt, mode);
    };

    scan_manifest_files(&manifests_path, mode)
}

fn scan_manifest_files(dir: &Path, mode: DiscoveryScanMode) -> Vec<GameInfo> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };

    entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().is_some_and(|ext| ext == "item"))
        .filter_map(|e| {
            let content = std::fs::read_to_string(e.path()).ok()?;
            parse_epic_manifest_item(&content, mode)
        })
        .collect()
}

fn parse_epic_manifest_item(content: &str, mode: DiscoveryScanMode) -> Option<GameInfo> {
    let json: serde_json::Value = serde_json::from_str(content)
        .inspect_err(|e| log::debug!("Failed to parse Epic manifest: {e}"))
        .ok()?;

    let name = json.get("DisplayName").and_then(|v| v.as_str())?.to_owned();
    let install_location = json.get("InstallLocation").and_then(|v| v.as_str())?;

    let game_path = PathBuf::from(install_location);
    if !game_path.is_dir() {
        return None;
    }

    utils::build_game_info_with_mode(name, game_path, Platform::EpicGames, mode)
}

fn is_epic_system_folder(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower == "launcher"
        || lower == "directxredist"
        || lower == "epic online services"
        || lower.contains("prerequisite")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::discovery::test_sync::lock_discovery_test;
    use std::fs;

    /// RAII guard that restores an environment variable when dropped, even if
    /// the test panics.  All mutations must be serialised by `lock_discovery_test`.
    ///
    /// Note: `std::env::set_var` / `remove_var` are `unsafe` in Rust edition 2024
    /// because they can cause data races in multi-threaded programs.  We use
    /// `lock_discovery_test()` to serialise all env-mutating tests, making these
    /// calls safe in practice.
    struct EnvVarGuard {
        key: &'static str,
        original: Option<String>,
    }

    impl EnvVarGuard {
        fn set(key: &'static str, value: &str) -> Self {
            let original = std::env::var(key).ok();
            // SAFETY: test-only; all env-mutating tests are serialised by
            // lock_discovery_test(), so no concurrent reads or writes occur.
            #[allow(unused_unsafe)]
            unsafe {
                std::env::set_var(key, value);
            }
            Self { key, original }
        }
    }

    impl Drop for EnvVarGuard {
        fn drop(&mut self) {
            // SAFETY: same serialisation guarantee as in `set`.
            #[allow(unused_unsafe)]
            unsafe {
                match &self.original {
                    Some(v) => std::env::set_var(self.key, v),
                    None => std::env::remove_var(self.key),
                }
            }
        }
    }

    #[test]
    fn parse_epic_manifest_item_nonexistent_path() {
        let _guard = lock_discovery_test();
        let json = r#"{
            "DisplayName": "Test Game",
            "InstallLocation": "C:\\NonExistent\\TestGame",
            "InstallSize": 5000000000
        }"#;
        assert!(parse_epic_manifest_item(json, DiscoveryScanMode::Full).is_none());
    }

    #[test]
    fn parse_epic_manifest_item_missing_fields() {
        let _guard = lock_discovery_test();
        let json = r#"{"InstallLocation": "C:\\Test"}"#;
        assert!(parse_epic_manifest_item(json, DiscoveryScanMode::Full).is_none());
    }

    #[test]
    fn is_epic_system_folder_filters_correctly() {
        let _guard = lock_discovery_test();
        assert!(is_epic_system_folder("Launcher"));
        assert!(is_epic_system_folder("DirectXRedist"));
        assert!(!is_epic_system_folder("Fortnite"));
        assert!(!is_epic_system_folder("Rocket League"));
    }

    #[test]
    fn epic_scanner_nonexistent_path_returns_empty() {
        let _guard = lock_discovery_test();
        let temp = tempfile::TempDir::new().unwrap();
        let manifests_dir = temp
            .path()
            .join("Epic")
            .join("EpicGamesLauncher")
            .join("Data")
            .join("Manifests");
        fs::create_dir_all(&manifests_dir).unwrap();
        let _env = EnvVarGuard::set("PROGRAMDATA", &temp.path().to_string_lossy());
        let scanner = EpicScanner::with_path(PathBuf::from(r"C:\NonExistent\Epic"));
        let result = scanner.scan(DiscoveryScanMode::Full).unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn manifest_display_name_wins_over_folder_name_for_same_install_path() {
        let _guard = lock_discovery_test();
        let temp = tempfile::TempDir::new().unwrap();
        let epic_root = temp.path().join("Epic Games");
        let game_dir = epic_root.join("rocketleague");
        fs::create_dir_all(&game_dir).unwrap();
        fs::File::create(game_dir.join("game.exe"))
            .unwrap()
            .set_len(3 * 1024 * 1024)
            .unwrap();
        fs::File::create(game_dir.join("content.bin"))
            .unwrap()
            .set_len(700 * 1024 * 1024)
            .unwrap();

        let manifest = serde_json::json!({
            "DisplayName": "Rocket League",
            "InstallLocation": game_dir.display().to_string(),
        })
        .to_string();

        let mut games = vec![parse_epic_manifest_item(&manifest, DiscoveryScanMode::Full)
            .expect("manifest should produce game info")];
        utils::merge_games(
            &mut games,
            scan_epic_dir(&epic_root, DiscoveryScanMode::Full),
        );

        assert_eq!(games.len(), 1);
        assert_eq!(games[0].name, "Rocket League");
        assert_eq!(games[0].path, game_dir);
    }
}
