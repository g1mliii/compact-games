use std::path::PathBuf;

use super::platform::{GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

pub struct GogScanner;

impl Default for GogScanner {
    fn default() -> Self {
        Self
    }
}

impl PlatformScanner for GogScanner {
    fn scan(&self) -> Result<Vec<GameInfo>, ScanError> {
        let mut games = scan_gog_registry_games();

        if let Some(galaxy_path) = find_gog_galaxy_games_path() {
            let dir_games = utils::scan_game_subdirs(&galaxy_path, Platform::GogGalaxy);
            utils::merge_games(&mut games, dir_games);
        }

        log::info!("GOG Galaxy: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "GOG Galaxy"
    }
}

#[cfg(windows)]
fn scan_gog_registry_games() -> Vec<GameInfo> {
    use winreg::enums::*;
    use winreg::RegKey;

    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);

    let gog_key = match hklm.open_subkey(r"SOFTWARE\WOW6432Node\GOG.com\Games") {
        Ok(key) => key,
        Err(e) => {
            log::info!("GOG registry key not found: {e}");
            return Vec::new();
        }
    };

    gog_key
        .enum_keys()
        .filter_map(|key_name| key_name.ok())
        .filter_map(|key_name| {
            let subkey = gog_key.open_subkey(&key_name).ok()?;
            let name: String = subkey.get_value("gameName").ok()?;
            let path_str: String = subkey.get_value("path").ok()?;

            let game_path = PathBuf::from(&path_str);
            if !game_path.is_dir() {
                return None;
            }

            utils::build_game_info(name, game_path, Platform::GogGalaxy)
        })
        .collect()
}

#[cfg(not(windows))]
fn scan_gog_registry_games() -> Vec<GameInfo> {
    Vec::new()
}

#[cfg(windows)]
fn find_gog_galaxy_games_path() -> Option<PathBuf> {
    use winreg::enums::*;
    use winreg::RegKey;

    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let galaxy_key = hklm
        .open_subkey(r"SOFTWARE\WOW6432Node\GOG.com\GalaxyClient\paths")
        .ok()?;
    let client_path: String = galaxy_key.get_value("client").ok()?;
    let games_path = PathBuf::from(client_path).parent()?.join("Games");

    if games_path.is_dir() {
        Some(games_path)
    } else {
        let default = PathBuf::from(r"C:\Program Files (x86)\GOG Galaxy\Games");
        default.is_dir().then_some(default)
    }
}

#[cfg(not(windows))]
fn find_gog_galaxy_games_path() -> Option<PathBuf> {
    None
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;

    #[test]
    fn gog_scanner_returns_ok() {
        let scanner = GogScanner;
        let result = scanner.scan();
        assert!(result.is_ok());
    }

    #[test]
    fn scan_nonexistent_directory_returns_empty() {
        let games =
            utils::scan_game_subdirs(Path::new(r"C:\NonExistent\GOG\Games"), Platform::GogGalaxy);
        assert!(games.is_empty());
    }
}
