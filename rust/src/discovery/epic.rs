use std::path::{Path, PathBuf};

use super::platform::{GameInfo, Platform, PlatformScanner};
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
    fn scan(&self) -> Result<Vec<GameInfo>, ScanError> {
        let mut games = Vec::new();

        if self.epic_path.is_dir() {
            games.extend(scan_epic_dir(&self.epic_path));
        }

        // Check launcher manifests for additional install locations
        let manifest_games = scan_epic_manifests();
        utils::merge_games(&mut games, manifest_games);

        log::info!("Epic Games: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "Epic Games"
    }
}

/// Scan the Epic Games install directory for game folders.
fn scan_epic_dir(epic_path: &Path) -> Vec<GameInfo> {
    let entries = match std::fs::read_dir(epic_path) {
        Ok(e) => e,
        Err(e) => {
            log::warn!("Cannot read Epic directory {}: {e}", epic_path.display());
            return Vec::new();
        }
    };

    entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .filter_map(|e| {
            let game_path = e.path();
            let folder_name = e.file_name().to_string_lossy().into_owned();

            if is_epic_system_folder(&folder_name) {
                return None;
            }

            let name = read_egstore_name(&game_path).unwrap_or(folder_name);
            utils::build_game_info(name, game_path, Platform::EpicGames)
        })
        .collect()
}

/// Read game name from .egstore metadata folder.
fn read_egstore_name(game_path: &Path) -> Option<String> {
    let egstore = game_path.join(".egstore");
    if !egstore.is_dir() {
        return None;
    }

    let entries = std::fs::read_dir(&egstore).ok()?;
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.extension().is_some_and(|ext| ext == "mancpn") {
            if let Ok(content) = std::fs::read_to_string(&path) {
                if let Some(name) = parse_mancpn_name(&content) {
                    return Some(name);
                }
            }
        }
    }
    None
}

fn parse_mancpn_name(content: &str) -> Option<String> {
    let json: serde_json::Value = serde_json::from_str(content)
        .inspect_err(|e| log::debug!("Failed to parse .mancpn: {e}"))
        .ok()?;
    json.get("AppName")
        .or_else(|| json.get("appName"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_owned())
}

/// Scan Epic launcher .item manifest files for installed games.
fn scan_epic_manifests() -> Vec<GameInfo> {
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
        return scan_manifest_files(&alt);
    };

    scan_manifest_files(&manifests_path)
}

fn scan_manifest_files(dir: &Path) -> Vec<GameInfo> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };

    entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().is_some_and(|ext| ext == "item"))
        .filter_map(|e| {
            let content = std::fs::read_to_string(e.path()).ok()?;
            parse_epic_manifest_item(&content)
        })
        .collect()
}

fn parse_epic_manifest_item(content: &str) -> Option<GameInfo> {
    let json: serde_json::Value = serde_json::from_str(content)
        .inspect_err(|e| log::debug!("Failed to parse Epic manifest: {e}"))
        .ok()?;

    let name = json.get("DisplayName").and_then(|v| v.as_str())?.to_owned();
    let install_location = json.get("InstallLocation").and_then(|v| v.as_str())?;

    let game_path = PathBuf::from(install_location);
    if !game_path.is_dir() {
        return None;
    }

    utils::build_game_info(name, game_path, Platform::EpicGames)
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

    #[test]
    fn parse_mancpn_name_valid() {
        let json = r#"{"AppName": "Fortnite", "CatalogItemId": "abc123"}"#;
        assert_eq!(parse_mancpn_name(json), Some("Fortnite".to_owned()));
    }

    #[test]
    fn parse_mancpn_name_lowercase_key() {
        let json = r#"{"appName": "RocketLeague"}"#;
        assert_eq!(parse_mancpn_name(json), Some("RocketLeague".to_owned()));
    }

    #[test]
    fn parse_mancpn_name_missing() {
        let json = r#"{"CatalogItemId": "abc123"}"#;
        assert_eq!(parse_mancpn_name(json), None);
    }

    #[test]
    fn parse_mancpn_name_invalid_json() {
        assert_eq!(parse_mancpn_name("not json"), None);
    }

    #[test]
    fn parse_epic_manifest_item_nonexistent_path() {
        let json = r#"{
            "DisplayName": "Test Game",
            "InstallLocation": "C:\\NonExistent\\TestGame",
            "InstallSize": 5000000000
        }"#;
        assert!(parse_epic_manifest_item(json).is_none());
    }

    #[test]
    fn parse_epic_manifest_item_missing_fields() {
        let json = r#"{"InstallLocation": "C:\\Test"}"#;
        assert!(parse_epic_manifest_item(json).is_none());
    }

    #[test]
    fn is_epic_system_folder_filters_correctly() {
        assert!(is_epic_system_folder("Launcher"));
        assert!(is_epic_system_folder("DirectXRedist"));
        assert!(!is_epic_system_folder("Fortnite"));
        assert!(!is_epic_system_folder("Rocket League"));
    }

    #[test]
    fn epic_scanner_nonexistent_path_returns_empty() {
        let scanner = EpicScanner::with_path(PathBuf::from(r"C:\NonExistent\Epic"));
        let result = scanner.scan().unwrap();
        assert!(result.is_empty());
    }
}
