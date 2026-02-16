use std::path::PathBuf;

use super::platform::{DiscoveryScanMode, GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

const DEFAULT_XBOX_PATH: &str = r"C:\XboxGames";

pub struct XboxScanner {
    xbox_path: PathBuf,
}

impl XboxScanner {
    pub fn new() -> Self {
        Self {
            xbox_path: PathBuf::from(DEFAULT_XBOX_PATH),
        }
    }

    pub fn with_path(xbox_path: PathBuf) -> Self {
        Self { xbox_path }
    }
}

impl Default for XboxScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformScanner for XboxScanner {
    fn scan(&self, mode: DiscoveryScanMode) -> Result<Vec<GameInfo>, ScanError> {
        let mut games = Vec::new();

        if self.xbox_path.is_dir() {
            games.extend(scan_xbox_dir(&self.xbox_path, mode));
        }

        let registry_games = scan_xbox_registry(mode);
        utils::merge_games(&mut games, registry_games);

        log::info!("Xbox Game Pass: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "Xbox Game Pass"
    }
}

/// Scan the Xbox Games directory for game folders.
fn scan_xbox_dir(xbox_path: &std::path::Path, mode: DiscoveryScanMode) -> Vec<GameInfo> {
    let entries = match std::fs::read_dir(xbox_path) {
        Ok(e) => e,
        Err(e) => {
            log::warn!("Cannot read Xbox directory {}: {e}", xbox_path.display());
            return Vec::new();
        }
    };

    entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .filter_map(|e| {
            let game_path = e.path();
            let folder_name = e.file_name().to_string_lossy().into_owned();

            // Xbox games have a "Content" subfolder typically - use it for size calc
            let size_path = if game_path.join("Content").is_dir() {
                game_path.join("Content")
            } else {
                game_path.clone()
            };

            let name = clean_xbox_name(&folder_name);

            utils::build_game_info_with_mode_and_stats_path(
                name,
                game_path,
                size_path,
                Platform::XboxGamePass,
                mode,
            )
        })
        .collect()
}

/// Scan registry for Xbox/Microsoft Store game installations.
#[cfg(windows)]
fn scan_xbox_registry(mode: DiscoveryScanMode) -> Vec<GameInfo> {
    use winreg::enums::*;
    use winreg::RegKey;

    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);

    let Ok(gaming_key) =
        hklm.open_subkey(r"SOFTWARE\Microsoft\GamingServices\PackageRepository\Root")
    else {
        return Vec::new();
    };

    gaming_key
        .enum_keys()
        .filter_map(|key_name| key_name.ok())
        .filter_map(|key_name| {
            let subkey = gaming_key.open_subkey(&key_name).ok()?;
            let path_str: String = subkey.get_value("Root").ok()?;

            let game_path = PathBuf::from(&path_str);
            if !game_path.is_dir() {
                return None;
            }

            let name = clean_xbox_name(
                &game_path
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_else(|| key_name.clone()),
            );

            utils::build_game_info_with_mode(name, game_path, Platform::XboxGamePass, mode)
        })
        .collect()
}

#[cfg(not(windows))]
fn scan_xbox_registry(_mode: DiscoveryScanMode) -> Vec<GameInfo> {
    Vec::new()
}

/// Clean up Xbox game folder names to human-readable display names.
///
/// Xbox folders often look like "BethesdaSoftworks.Starfield" or
/// "343Industries.Halo-Infinite".
fn clean_xbox_name(raw_name: &str) -> String {
    let name = raw_name;

    // Remove publisher prefix (e.g., "BethesdaSoftworks." -> "")
    let name = if let Some(pos) = name.find('.') {
        &name[pos + 1..]
    } else {
        name
    };

    // Remove version suffix (e.g., "_1.0.0.0_x64__...")
    let name = if let Some(pos) = name.find('_') {
        &name[..pos]
    } else {
        name
    };

    // Replace hyphens with spaces and add spaces before capitals
    let mut result = String::with_capacity(name.len() + 4);
    let mut prev_was_lowercase = false;
    for ch in name.chars() {
        if ch == '-' {
            result.push(' ');
            prev_was_lowercase = false;
        } else if prev_was_lowercase && ch.is_uppercase() {
            result.push(' ');
            result.push(ch);
            prev_was_lowercase = ch.is_lowercase();
        } else {
            result.push(ch);
            prev_was_lowercase = ch.is_lowercase();
        }
    }

    if result.is_empty() {
        raw_name.to_owned()
    } else {
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_xbox_name_publisher_prefix() {
        assert_eq!(clean_xbox_name("BethesdaSoftworks.Starfield"), "Starfield");
    }

    #[test]
    fn clean_xbox_name_with_hyphen() {
        assert_eq!(
            clean_xbox_name("343Industries.Halo-Infinite"),
            "Halo Infinite"
        );
    }

    #[test]
    fn clean_xbox_name_with_version_suffix() {
        assert_eq!(
            clean_xbox_name("Microsoft.MinecraftUWP_1.0.0.0_x64__abc123"),
            "Minecraft UWP"
        );
    }

    #[test]
    fn clean_xbox_name_camel_case_splitting() {
        assert_eq!(clean_xbox_name("FortniteGame"), "Fortnite Game");
    }

    #[test]
    fn clean_xbox_name_simple() {
        assert_eq!(clean_xbox_name("Starfield"), "Starfield");
    }

    #[test]
    fn clean_xbox_name_unicode_safe() {
        assert_eq!(clean_xbox_name("Studio.ÉliteGame"), "Élite Game");
    }

    #[test]
    fn xbox_scanner_nonexistent_path_returns_empty() {
        let scanner = XboxScanner::with_path(PathBuf::from(r"C:\NonExistent\XboxGames"));
        let result = scanner.scan(DiscoveryScanMode::Full).unwrap();
        assert!(result.is_empty());
    }
}
