use std::path::{Path, PathBuf};

use super::platform::{DiscoveryScanMode, GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

/// Known Battle.net game folder names and their display names.
const KNOWN_BATTLENET_GAMES: &[(&str, &str)] = &[
    ("World of Warcraft", "World of Warcraft"),
    ("Overwatch", "Overwatch 2"),
    ("Diablo IV", "Diablo IV"),
    ("Diablo III", "Diablo III"),
    ("Diablo Immortal", "Diablo Immortal"),
    ("StarCraft II", "StarCraft II"),
    ("StarCraft", "StarCraft Remastered"),
    ("Hearthstone", "Hearthstone"),
    ("Heroes of the Storm", "Heroes of the Storm"),
    ("Warcraft III", "Warcraft III Reforged"),
    ("Call of Duty", "Call of Duty"),
    ("Crash Bandicoot 4", "Crash Bandicoot 4"),
];

#[derive(Default)]
pub struct BattleNetScanner {}

impl PlatformScanner for BattleNetScanner {
    fn scan(&self, mode: DiscoveryScanMode) -> Result<Vec<GameInfo>, ScanError> {
        let mut games = Vec::new();

        if let Some(config_games) = scan_battlenet_config(mode) {
            games.extend(config_games);
        }

        let registry_games = scan_battlenet_registry(mode);
        utils::merge_games(&mut games, registry_games);

        // Fallback: check common install paths for known games
        let fallback_games: Vec<GameInfo> = KNOWN_BATTLENET_GAMES
            .iter()
            .filter_map(|(folder, display_name)| {
                let path = PathBuf::from(r"C:\Program Files (x86)").join(folder);
                if path.is_dir() {
                    utils::build_game_info_with_mode(
                        display_name.to_string(),
                        path,
                        Platform::BattleNet,
                        mode,
                    )
                } else {
                    None
                }
            })
            .collect();
        utils::merge_games(&mut games, fallback_games);

        log::info!("Battle.net: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "Battle.net"
    }
}

/// Parse Battle.net launcher config for installed game paths.
fn scan_battlenet_config(mode: DiscoveryScanMode) -> Option<Vec<GameInfo>> {
    let program_data = std::env::var("PROGRAMDATA").ok()?;

    // Try Battle.net's launcher JSON config
    let config_path = PathBuf::from(&program_data)
        .join("Battle.net")
        .join("Setup")
        .join("battle.net.config");

    if config_path.is_file() {
        return parse_battlenet_json_config(&config_path, mode);
    }

    // Try product.install text file
    let product_install = PathBuf::from(&program_data)
        .join("Battle.net")
        .join("Agent")
        .join("product.install");

    if product_install.is_file() {
        let content = std::fs::read_to_string(&product_install).ok()?;
        return Some(parse_product_install(&content, mode));
    }

    None
}

fn parse_battlenet_json_config(
    config_path: &Path,
    mode: DiscoveryScanMode,
) -> Option<Vec<GameInfo>> {
    let content = std::fs::read_to_string(config_path).ok()?;
    let json: serde_json::Value = serde_json::from_str(&content)
        .inspect_err(|e| log::debug!("Failed to parse Battle.net config: {e}"))
        .ok()?;

    let base_path = json
        .get("Client")
        .and_then(|c| c.get("Install"))
        .and_then(|i| i.get("DefaultInstallPath"))
        .and_then(|v| v.as_str())?;

    let base = PathBuf::from(base_path);
    if !base.is_dir() {
        return None;
    }

    Some(scan_battlenet_dir(&base, mode))
}

fn parse_product_install(content: &str, mode: DiscoveryScanMode) -> Vec<GameInfo> {
    content
        .lines()
        .filter_map(|line| extract_install_path(line.trim()))
        .filter_map(|path_str| {
            let game_path = PathBuf::from(path_str);
            if !game_path.is_dir() {
                return None;
            }

            let folder_name = game_path
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())?;

            let display_name = resolve_battlenet_name(&folder_name);
            utils::build_game_info_with_mode(display_name, game_path, Platform::BattleNet, mode)
        })
        .collect()
}

/// Try to extract an install path from a product.install line.
fn extract_install_path(line: &str) -> Option<&str> {
    let bytes = line.as_bytes();
    for start in 0..bytes.len().saturating_sub(2) {
        if bytes[start].is_ascii_alphabetic()
            && bytes[start + 1] == b':'
            && bytes[start + 2] == b'\\'
        {
            let rest = &line[start..];
            let end = rest.find(['\t', '\n', '\r', '"']).unwrap_or(rest.len());
            return Some(rest[..end].trim_end_matches(','));
        }
    }
    None
}

/// Map a folder name to a known Battle.net display name.
fn resolve_battlenet_name(folder_name: &str) -> String {
    KNOWN_BATTLENET_GAMES
        .iter()
        .find(|(f, _)| folder_name.eq_ignore_ascii_case(f))
        .map(|(_, d)| d.to_string())
        .unwrap_or_else(|| folder_name.to_owned())
}

/// Scan registry for Battle.net game installations.
#[cfg(windows)]
fn scan_battlenet_registry(mode: DiscoveryScanMode) -> Vec<GameInfo> {
    use winreg::enums::*;
    use winreg::RegKey;

    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let mut games = Vec::new();

    let Ok(uninstall_key) =
        hklm.open_subkey(r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")
    else {
        return games;
    };

    for key_name in uninstall_key.enum_keys().filter_map(|k| k.ok()) {
        let Ok(subkey) = uninstall_key.open_subkey(&key_name) else {
            continue;
        };

        let publisher: String = match subkey.get_value("Publisher") {
            Ok(p) => p,
            Err(_) => continue,
        };

        if !publisher.contains("Blizzard") && !publisher.contains("Activision") {
            continue;
        }

        let Ok(path_str): Result<String, _> = subkey.get_value("InstallLocation") else {
            continue;
        };

        let game_path = PathBuf::from(&path_str);
        if !game_path.is_dir() {
            continue;
        }

        let name: String = subkey
            .get_value("DisplayName")
            .unwrap_or_else(|_| key_name.clone());

        if let Some(game) =
            utils::build_game_info_with_mode(name, game_path, Platform::BattleNet, mode)
        {
            games.push(game);
        }
    }

    games
}

#[cfg(not(windows))]
fn scan_battlenet_registry(_mode: DiscoveryScanMode) -> Vec<GameInfo> {
    Vec::new()
}

fn scan_battlenet_dir(games_path: &Path, mode: DiscoveryScanMode) -> Vec<GameInfo> {
    let Ok(entries) = std::fs::read_dir(games_path) else {
        return Vec::new();
    };

    let candidates: Vec<(String, PathBuf)> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .map(|e| {
            let game_path = e.path();
            let folder_name = e.file_name().to_string_lossy().into_owned();
            let display_name = resolve_battlenet_name(&folder_name);
            (display_name, game_path)
        })
        .collect();

    utils::build_games_from_candidates(games_path, candidates, Platform::BattleNet, mode)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn battlenet_scanner_returns_ok() {
        let scanner = BattleNetScanner {};
        let result = scanner.scan(DiscoveryScanMode::Full);
        assert!(result.is_ok());
    }

    #[test]
    fn extract_install_path_valid() {
        assert_eq!(
            extract_install_path(r"game	C:\Program Files\WoW"),
            Some(r"C:\Program Files\WoW")
        );
    }

    #[test]
    fn extract_install_path_no_path() {
        assert_eq!(extract_install_path("no path here"), None);
    }

    #[test]
    fn extract_install_path_lowercase_drive() {
        assert_eq!(
            extract_install_path(r"install_path	c:\Program Files\WoW"),
            Some(r"c:\Program Files\WoW")
        );
    }

    #[test]
    fn resolve_battlenet_name_known() {
        assert_eq!(resolve_battlenet_name("Diablo IV"), "Diablo IV");
    }

    #[test]
    fn resolve_battlenet_name_unknown() {
        assert_eq!(resolve_battlenet_name("SomeGame"), "SomeGame");
    }

    #[test]
    fn scan_nonexistent_directory_returns_empty() {
        let games = scan_battlenet_dir(
            Path::new(r"C:\NonExistent\BattleNet"),
            DiscoveryScanMode::Full,
        );
        assert!(games.is_empty());
    }
}
