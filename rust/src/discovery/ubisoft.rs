use std::path::PathBuf;

use super::platform::{GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

const DEFAULT_UBISOFT_PATH: &str = r"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games";

pub struct UbisoftScanner;

impl Default for UbisoftScanner {
    fn default() -> Self {
        Self
    }
}

impl PlatformScanner for UbisoftScanner {
    fn scan(&self) -> Result<Vec<GameInfo>, ScanError> {
        let mut games = scan_ubisoft_registry();

        let default_path =
            find_ubisoft_games_path().unwrap_or_else(|| PathBuf::from(DEFAULT_UBISOFT_PATH));

        if default_path.is_dir() {
            let dir_games = utils::scan_game_subdirs(&default_path, Platform::UbisoftConnect);
            utils::merge_games(&mut games, dir_games);
        }

        log::info!("Ubisoft Connect: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "Ubisoft Connect"
    }
}

#[cfg(windows)]
fn scan_ubisoft_registry() -> Vec<GameInfo> {
    use winreg::enums::*;
    use winreg::RegKey;

    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);

    let installs_key = match hklm.open_subkey(r"SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs") {
        Ok(key) => key,
        Err(e) => {
            log::info!("Ubisoft registry key not found: {e}");
            return Vec::new();
        }
    };

    installs_key
        .enum_keys()
        .filter_map(|key_name| key_name.ok())
        .filter_map(|key_name| {
            let subkey = installs_key.open_subkey(&key_name).ok()?;
            let path_str: String = subkey.get_value("InstallDir").ok()?;

            let game_path = PathBuf::from(&path_str);
            if !game_path.is_dir() {
                return None;
            }

            let name = game_path
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| format!("Ubisoft Game {key_name}"));

            utils::build_game_info(name, game_path, Platform::UbisoftConnect)
        })
        .collect()
}

#[cfg(not(windows))]
fn scan_ubisoft_registry() -> Vec<GameInfo> {
    Vec::new()
}

#[cfg(windows)]
fn find_ubisoft_games_path() -> Option<PathBuf> {
    use winreg::enums::*;
    use winreg::RegKey;

    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let launcher_key = hklm
        .open_subkey(r"SOFTWARE\WOW6432Node\Ubisoft\Launcher")
        .ok()?;
    let install_dir: String = launcher_key.get_value("InstallDir").ok()?;
    let games_path = PathBuf::from(install_dir).join("games");
    games_path.is_dir().then_some(games_path)
}

#[cfg(not(windows))]
fn find_ubisoft_games_path() -> Option<PathBuf> {
    None
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;

    #[test]
    fn ubisoft_scanner_returns_ok() {
        let scanner = UbisoftScanner;
        let result = scanner.scan();
        assert!(result.is_ok());
    }

    #[test]
    fn scan_nonexistent_directory_returns_empty() {
        let games = utils::scan_game_subdirs(
            Path::new(r"C:\NonExistent\Ubisoft\Games"),
            Platform::UbisoftConnect,
        );
        assert!(games.is_empty());
    }
}
