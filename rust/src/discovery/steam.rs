use std::collections::HashMap;
use std::path::{Path, PathBuf};

use super::platform::{GameInfo, Platform, PlatformScanner};
use super::scan_error::ScanError;
use super::utils;

const DEFAULT_STEAM_PATH: &str = r"C:\Program Files (x86)\Steam";

pub struct SteamScanner {
    steam_path: PathBuf,
}

impl SteamScanner {
    pub fn new() -> Self {
        Self {
            steam_path: PathBuf::from(DEFAULT_STEAM_PATH),
        }
    }

    pub fn with_path(steam_path: PathBuf) -> Self {
        Self { steam_path }
    }
}

impl Default for SteamScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformScanner for SteamScanner {
    fn scan(&self) -> Result<Vec<GameInfo>, ScanError> {
        if !self.steam_path.is_dir() {
            log::info!("Steam path not found: {}", self.steam_path.display());
            return Ok(Vec::new());
        }

        let library_paths = discover_library_paths(&self.steam_path);
        if library_paths.is_empty() {
            log::info!("No Steam library folders found");
            return Ok(Vec::new());
        }

        let games: Vec<GameInfo> = library_paths
            .iter()
            .flat_map(|lib_path| {
                scan_library(lib_path)
                    .inspect_err(|e| {
                        log::warn!("Failed to scan Steam library {}: {e}", lib_path.display())
                    })
                    .unwrap_or_default()
            })
            .collect();

        log::info!("Steam: found {} games", games.len());
        Ok(games)
    }

    fn platform_name(&self) -> &'static str {
        "Steam"
    }
}

/// Discover all Steam library folders from libraryfolders.vdf.
fn discover_library_paths(steam_path: &Path) -> Vec<PathBuf> {
    let vdf_path = steam_path.join("steamapps").join("libraryfolders.vdf");

    let Ok(content) = std::fs::read_to_string(&vdf_path) else {
        let default = steam_path.join("steamapps");
        if default.is_dir() {
            return vec![default];
        }
        return Vec::new();
    };

    let mut paths = parse_library_paths(&content);

    let default = steam_path.join("steamapps");
    if default.is_dir() && !paths.iter().any(|p| p == &default) {
        paths.insert(0, default);
    }

    paths.retain(|p| p.is_dir());
    paths
}

/// Parse library paths from libraryfolders.vdf content.
fn parse_library_paths(content: &str) -> Vec<PathBuf> {
    let mut paths = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("\"path\"") {
            let rest = rest.trim();
            if let Some(path_str) = extract_quoted_value(rest) {
                let unescaped = path_str.replace("\\\\", "\\");
                let lib_path = PathBuf::from(&unescaped).join("steamapps");
                paths.push(lib_path);
            }
        }
    }

    paths
}

/// Extract a quoted string value: `"some value"` -> `some value`
fn extract_quoted_value(s: &str) -> Option<&str> {
    let s = s.trim();
    let s = s.strip_prefix('"')?;
    let end = s.find('"')?;
    Some(&s[..end])
}

/// Scan a single Steam library folder for games.
fn scan_library(steamapps_path: &Path) -> Result<Vec<GameInfo>, ScanError> {
    let common_path = steamapps_path.join("common");
    if !common_path.is_dir() {
        return Ok(Vec::new());
    }

    let manifests = parse_app_manifests(steamapps_path);

    let games: Vec<GameInfo> = std::fs::read_dir(&common_path)?
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.path().is_dir())
        .filter_map(|entry| {
            let game_path = entry.path();
            let folder_name = entry.file_name().to_string_lossy().into_owned();

            if is_steam_tool(&folder_name) {
                return None;
            }

            let folder_key = folder_name.to_ascii_lowercase();
            let name = manifests.get(&folder_key).cloned().unwrap_or(folder_name);

            utils::build_game_info(name, game_path, Platform::Steam)
        })
        .collect();

    Ok(games)
}

struct AppManifest {
    name: String,
    install_dir: String,
}

fn parse_app_manifests(steamapps_path: &Path) -> HashMap<String, String> {
    let Ok(entries) = std::fs::read_dir(steamapps_path) else {
        return HashMap::new();
    };

    let mut manifests = HashMap::new();
    for entry in entries.filter_map(|e| e.ok()) {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !(name.starts_with("appmanifest_") && name.ends_with(".acf")) {
            continue;
        }

        let Some(manifest) = std::fs::read_to_string(entry.path())
            .inspect_err(|err| {
                log::debug!("Cannot read manifest {}: {err}", entry.path().display())
            })
            .ok()
            .and_then(|content| parse_acf_manifest(&content))
        else {
            continue;
        };

        manifests
            .entry(manifest.install_dir.to_ascii_lowercase())
            .or_insert(manifest.name);
    }

    manifests
}

fn parse_acf_manifest(content: &str) -> Option<AppManifest> {
    let mut name = None;
    let mut install_dir = None;

    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("\"name\"") {
            if let Some(val) = extract_quoted_value(rest) {
                name = Some(val.to_owned());
            }
        } else if let Some(rest) = trimmed.strip_prefix("\"installdir\"") {
            if let Some(val) = extract_quoted_value(rest) {
                install_dir = Some(val.to_owned());
            }
        }
    }

    Some(AppManifest {
        name: name?,
        install_dir: install_dir?,
    })
}

fn is_steam_tool(folder_name: &str) -> bool {
    let lower = folder_name.to_ascii_lowercase();
    lower.contains("steamworks")
        || lower.contains("redistributable")
        || lower.contains("dedicated server")
        || lower == "steam controller configs"
        || lower == "steamvr"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_library_paths_single_library() {
        let vdf = r#"
"libraryfolders"
{
    "0"
    {
        "path"		"C:\\Program Files (x86)\\Steam"
        "label"		""
    }
}
"#;
        let paths = parse_library_paths(vdf);
        assert_eq!(paths.len(), 1);
        assert_eq!(
            paths[0],
            PathBuf::from(r"C:\Program Files (x86)\Steam\steamapps")
        );
    }

    #[test]
    fn parse_library_paths_multiple_libraries() {
        let vdf = r#"
"libraryfolders"
{
    "0"
    {
        "path"		"C:\\Program Files (x86)\\Steam"
    }
    "1"
    {
        "path"		"D:\\SteamLibrary"
    }
    "2"
    {
        "path"		"E:\\Games\\Steam"
    }
}
"#;
        let paths = parse_library_paths(vdf);
        assert_eq!(paths.len(), 3);
        assert_eq!(paths[1], PathBuf::from(r"D:\SteamLibrary\steamapps"));
    }

    #[test]
    fn parse_library_paths_empty_vdf() {
        let paths = parse_library_paths("");
        assert!(paths.is_empty());
    }

    #[test]
    fn parse_acf_manifest_valid() {
        let acf = r#"
"AppState"
{
    "appid"		"400"
    "Universe"		"1"
    "name"		"Portal"
    "StateFlags"		"4"
    "installdir"		"Portal"
}
"#;
        let manifest = parse_acf_manifest(acf).unwrap();
        assert_eq!(manifest.name, "Portal");
        assert_eq!(manifest.install_dir, "Portal");
    }

    #[test]
    fn parse_acf_manifest_missing_name() {
        let acf = r#"
"AppState"
{
    "appid"		"400"
    "installdir"		"Portal"
}
"#;
        assert!(parse_acf_manifest(acf).is_none());
    }

    #[test]
    fn parse_acf_manifest_missing_installdir() {
        let acf = r#"
"AppState"
{
    "name"		"Portal"
}
"#;
        assert!(parse_acf_manifest(acf).is_none());
    }

    #[test]
    fn extract_quoted_value_simple() {
        assert_eq!(
            extract_quoted_value(r#""hello world""#),
            Some("hello world")
        );
    }

    #[test]
    fn extract_quoted_value_with_tabs() {
        assert_eq!(
            extract_quoted_value("\t\t\"some value\""),
            Some("some value")
        );
    }

    #[test]
    fn extract_quoted_value_empty() {
        assert_eq!(extract_quoted_value(r#""""#), Some(""));
    }

    #[test]
    fn extract_quoted_value_no_quotes() {
        assert_eq!(extract_quoted_value("no quotes"), None);
    }

    #[test]
    fn is_steam_tool_filters_correctly() {
        assert!(is_steam_tool("Steamworks Shared"));
        assert!(is_steam_tool("Visual C++ Redistributable"));
        assert!(is_steam_tool("SteamVR"));
        assert!(!is_steam_tool("Half-Life 2"));
        assert!(!is_steam_tool("Portal 2"));
    }

    #[test]
    fn steam_scanner_nonexistent_path_returns_empty() {
        let scanner = SteamScanner::with_path(PathBuf::from(r"C:\NonExistent\Steam"));
        let result = scanner.scan().unwrap();
        assert!(result.is_empty());
    }
}
