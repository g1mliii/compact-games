use std::path::PathBuf;

use super::platform::{DiscoveryScanMode, GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

const DEFAULT_EA_PATHS: &[&str] = &[
    r"C:\Program Files\EA Games",
    r"C:\Program Files (x86)\Origin Games",
];

#[derive(Default)]
pub struct EaScanner {}

impl PlatformScanner for EaScanner {
    fn scan(&self, mode: DiscoveryScanMode) -> Result<Vec<GameInfo>, ScanError> {
        let mut games = scan_ea_registry(mode);

        for default_path in DEFAULT_EA_PATHS {
            let path = PathBuf::from(default_path);
            if path.is_dir() {
                let dir_games = utils::scan_game_subdirs(&path, Platform::EaApp, mode);
                utils::merge_games(&mut games, dir_games);
            }
        }

        if let Some(config_games) = scan_ea_desktop_config(mode) {
            utils::merge_games(&mut games, config_games);
        }

        log::info!("EA App: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "EA App"
    }
}

#[cfg(windows)]
fn scan_ea_registry(mode: DiscoveryScanMode) -> Vec<GameInfo> {
    use winreg::enums::*;
    use winreg::RegKey;

    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let mut games = Vec::new();

    let registry_paths = [
        r"SOFTWARE\WOW6432Node\EA Games",
        r"SOFTWARE\WOW6432Node\Electronic Arts",
    ];

    for reg_path in &registry_paths {
        let Ok(ea_key) = hklm.open_subkey(reg_path) else {
            continue;
        };

        let found: Vec<GameInfo> = ea_key
            .enum_keys()
            .filter_map(|key_name| key_name.ok())
            .filter_map(|key_name| {
                let subkey = ea_key.open_subkey(&key_name).ok()?;
                let path_str: String = subkey
                    .get_value("Install Dir")
                    .or_else(|_| subkey.get_value("InstallDir"))
                    .ok()?;

                let game_path = PathBuf::from(&path_str);
                if !game_path.is_dir() {
                    return None;
                }

                utils::build_game_info_with_mode(key_name, game_path, Platform::EaApp, mode)
            })
            .collect();

        games.extend(found);
    }

    games
}

#[cfg(not(windows))]
fn scan_ea_registry(_mode: DiscoveryScanMode) -> Vec<GameInfo> {
    Vec::new()
}

fn scan_ea_desktop_config(mode: DiscoveryScanMode) -> Option<Vec<GameInfo>> {
    let program_data = std::env::var("PROGRAMDATA").ok()?;
    let ea_config = PathBuf::from(program_data)
        .join("EA Desktop")
        .join("InstallData");

    if !ea_config.is_dir() {
        return None;
    }

    let entries = std::fs::read_dir(&ea_config).ok()?;
    let games: Vec<GameInfo> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().is_some_and(|ext| ext == "json"))
        .filter_map(|e| {
            let content = std::fs::read_to_string(e.path()).ok()?;
            parse_ea_install_json(&content, mode)
        })
        .collect();

    Some(games)
}

fn parse_ea_install_json(content: &str, mode: DiscoveryScanMode) -> Option<GameInfo> {
    let json: serde_json::Value = serde_json::from_str(content)
        .inspect_err(|e| log::debug!("Failed to parse EA config: {e}"))
        .ok()?;

    let name = json
        .get("displayName")
        .or_else(|| json.get("title"))
        .and_then(|v| v.as_str())?
        .to_owned();

    let install_path = json
        .get("installLocation")
        .or_else(|| json.get("installPath"))
        .and_then(|v| v.as_str())?;

    let game_path = PathBuf::from(install_path);
    if !game_path.is_dir() {
        return None;
    }

    utils::build_game_info_with_mode(name, game_path, Platform::EaApp, mode)
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;

    #[test]
    fn ea_scanner_returns_ok() {
        let scanner = EaScanner {};
        let result = scanner.scan(DiscoveryScanMode::Full);
        assert!(result.is_ok());
    }

    #[test]
    fn parse_ea_install_json_nonexistent_path() {
        let json = r#"{
            "displayName": "Test Game",
            "installLocation": "C:\\NonExistent\\TestGame"
        }"#;
        assert!(parse_ea_install_json(json, DiscoveryScanMode::Full).is_none());
    }

    #[test]
    fn parse_ea_install_json_missing_name() {
        let json = r#"{"installLocation": "C:\\Test"}"#;
        assert!(parse_ea_install_json(json, DiscoveryScanMode::Full).is_none());
    }

    #[test]
    fn scan_nonexistent_directory_returns_empty() {
        let games = utils::scan_game_subdirs(
            Path::new(r"C:\NonExistent\EA\Games"),
            Platform::EaApp,
            DiscoveryScanMode::Full,
        );
        assert!(games.is_empty());
    }
}
