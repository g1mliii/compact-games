use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};

use super::platform::{DiscoveryScanMode, GameInfo, Platform, PlatformScanner};
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
    fn scan(&self, mode: DiscoveryScanMode) -> Result<Vec<GameInfo>, ScanError> {
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
                scan_library(lib_path, mode)
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
fn scan_library(
    steamapps_path: &Path,
    mode: DiscoveryScanMode,
) -> Result<Vec<GameInfo>, ScanError> {
    let common_path = steamapps_path.join("common");
    if !common_path.is_dir() {
        return Ok(Vec::new());
    }

    let manifests = parse_app_manifests(steamapps_path);
    // A scan already holds the freshest possible view of this library, so hand
    // it to the lookup cache instead of letting the next backfill re-read every
    // manifest. This is also what makes a just-installed game visible to the
    // lookup immediately after a rescan.
    publish_app_id_index(steamapps_path, &manifests);

    let mut manifest_candidates = Vec::new();
    let mut heuristic_candidates = Vec::new();
    for entry in std::fs::read_dir(&common_path)?.filter_map(|entry| entry.ok()) {
        if !entry.path().is_dir() {
            continue;
        }
        let game_path = entry.path();
        let folder_name = entry.file_name().to_string_lossy().into_owned();
        if is_steam_tool(&folder_name) {
            continue;
        }

        let folder_key = folder_name.to_ascii_lowercase();
        if let Some(manifest) = manifests
            .get(&folder_key)
            .filter(|manifest| manifest.is_fully_installed())
        {
            manifest_candidates.push((manifest.name.clone(), game_path));
        } else {
            heuristic_candidates.push((folder_name, game_path));
        }
    }

    let mut games = utils::build_games_from_launcher_metadata_candidates(
        &common_path,
        manifest_candidates,
        Platform::Steam,
        mode,
    );
    utils::merge_games(
        &mut games,
        utils::build_games_from_candidates(
            &common_path,
            heuristic_candidates,
            Platform::Steam,
            mode,
        ),
    );
    for game in &mut games {
        let Some(folder_key) = game
            .path
            .file_name()
            .and_then(|name| name.to_str())
            .map(|name| name.to_ascii_lowercase())
        else {
            continue;
        };
        if let Some(manifest) = manifests.get(&folder_key) {
            game.steam_app_id = Some(manifest.app_id);
        }
    }
    Ok(games)
}

struct AppManifest {
    app_id: u32,
    name: String,
    install_dir: String,
    state_flags: Option<u32>,
}

const STEAM_STATE_FULLY_INSTALLED: u32 = 4;

impl AppManifest {
    fn is_fully_installed(&self) -> bool {
        self.state_flags
            .is_some_and(|flags| flags & STEAM_STATE_FULLY_INSTALLED != 0)
    }
}

fn parse_app_manifests(steamapps_path: &Path) -> HashMap<String, AppManifest> {
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

        let Some(app_id) = parse_app_id_from_manifest_filename(&name) else {
            continue;
        };

        let Some(mut manifest) = std::fs::read_to_string(entry.path())
            .inspect_err(|err| {
                log::debug!("Cannot read manifest {}: {err}", entry.path().display())
            })
            .ok()
            .and_then(|content| parse_acf_manifest(&content))
        else {
            continue;
        };

        manifest.app_id = app_id;
        manifests
            .entry(manifest.install_dir.to_ascii_lowercase())
            .or_insert(manifest);
    }

    manifests
}

/// Lowered `installdir` to app id for one `steamapps/` directory.
type AppIdIndex = HashMap<String, u32>;

/// Mirrors the bounds the Dart-side manifest cache used before this lookup moved
/// into Rust: a handful of library roots, re-read on a timer so a game installed
/// while the app is running is picked up without a restart.
const APP_ID_INDEX_TTL: Duration = Duration::from_secs(15 * 60);
const APP_ID_INDEX_MAX_ROOTS: usize = 8;

struct AppIdIndexEntry {
    index: Arc<AppIdIndex>,
    read_at: Instant,
}

static APP_ID_INDEX_CACHE: LazyLock<Mutex<HashMap<PathBuf, AppIdIndexEntry>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Drops every cached index so the next lookup re-reads from disk.
///
/// Exposed to Dart so the app's tray/memory-pressure trim can reclaim this the
/// same way it reclaims the visible-only cover art caches.
pub fn invalidate_app_id_index_cache() {
    lock_app_id_index_cache().clear();
}

/// Seeds the cache from manifests a caller has already parsed.
///
/// A scan reads every manifest anyway; publishing the derived index here is what
/// keeps the first post-scan lookup from repeating that whole directory read.
fn publish_app_id_index(steamapps_path: &Path, manifests: &HashMap<String, AppManifest>) {
    let index: AppIdIndex = manifests
        .iter()
        .map(|(install_dir, manifest)| (install_dir.clone(), manifest.app_id))
        .collect();
    store_app_id_index(steamapps_path, Arc::new(index), Instant::now());
}

/// Inserts `index` for `steamapps_path`, evicting the least recently read root
/// once the cache is full.
fn store_app_id_index(steamapps_path: &Path, index: Arc<AppIdIndex>, read_at: Instant) {
    let mut cache = lock_app_id_index_cache();
    if cache.len() >= APP_ID_INDEX_MAX_ROOTS && !cache.contains_key(steamapps_path) {
        if let Some(oldest) = cache
            .iter()
            .min_by_key(|(_, entry)| entry.read_at)
            .map(|(path, _)| path.clone())
        {
            cache.remove(&oldest);
        }
    }
    cache.insert(
        steamapps_path.to_path_buf(),
        AppIdIndexEntry { index, read_at },
    );
}

fn lock_app_id_index_cache() -> std::sync::MutexGuard<'static, HashMap<PathBuf, AppIdIndexEntry>> {
    // A panic in another thread must not take the lookup down with it; the map
    // is a pure cache, so recovering the poisoned contents is always safe.
    APP_ID_INDEX_CACHE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Returns the folder → app id index for `steamapps_path`, reading from disk
/// only on a cold or expired entry.
///
/// Callers reach this once per game, so an uncached read here would re-enumerate
/// and re-parse every `appmanifest_*.acf` in the library for every game in a
/// refresh burst.
fn app_id_index(steamapps_path: &Path) -> Arc<AppIdIndex> {
    let now = Instant::now();
    {
        let cache = lock_app_id_index_cache();
        if let Some(entry) = cache.get(steamapps_path) {
            if now.duration_since(entry.read_at) < APP_ID_INDEX_TTL {
                return Arc::clone(&entry.index);
            }
        }
    }

    // Parsed outside the lock: this is directory-wide file I/O, and holding a
    // process-global mutex across it would serialize unrelated libraries.
    let index: Arc<AppIdIndex> = Arc::new(
        parse_app_manifests(steamapps_path)
            .into_iter()
            .map(|(install_dir, manifest)| (install_dir, manifest.app_id))
            .collect(),
    );

    store_app_id_index(steamapps_path, Arc::clone(&index), now);
    index
}

/// Look up the Steam app ID for an installed game by walking from the game
/// path up to the surrounding `steamapps/` directory and matching the folder
/// name against any `appmanifest_*.acf` `installdir`. Returns `None` if the
/// path isn't a conventional Steam install or no manifest matches.
///
/// Backed by [`app_id_index`], so a burst of lookups across one library costs a
/// single directory read rather than one per game.
pub fn lookup_steam_app_id_for_path(game_path: &Path) -> Option<u32> {
    let folder_name = game_path.file_name()?.to_str()?.to_ascii_lowercase();
    let common = game_path.parent()?;
    let steamapps = common.parent()?;
    if !steamapps
        .file_name()
        .and_then(|n| n.to_str())?
        .eq_ignore_ascii_case("steamapps")
    {
        return None;
    }
    app_id_index(steamapps).get(&folder_name).copied()
}

fn parse_app_id_from_manifest_filename(name: &str) -> Option<u32> {
    name.strip_prefix("appmanifest_")?
        .strip_suffix(".acf")?
        .parse()
        .ok()
}

fn parse_acf_manifest(content: &str) -> Option<AppManifest> {
    let mut name = None;
    let mut install_dir = None;
    let mut state_flags = None;

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
        } else if let Some(rest) = trimmed.strip_prefix("\"StateFlags\"") {
            state_flags = extract_quoted_value(rest).and_then(|value| value.parse().ok());
        }
    }

    Some(AppManifest {
        app_id: 0,
        name: name?,
        install_dir: install_dir?,
        state_flags,
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

    fn write_manifest(steamapps: &Path, app_id: u32, install_dir: &str) {
        std::fs::write(
            steamapps.join(format!("appmanifest_{app_id}.acf")),
            format!(
                "\"AppState\"\n{{\n\t\"appid\"\t\t\"{app_id}\"\n\t\"name\"\t\t\"{install_dir}\"\n\t\"installdir\"\t\t\"{install_dir}\"\n\t\"StateFlags\"\t\t\"4\"\n}}\n"
            ),
        )
        .unwrap();
    }

    #[test]
    fn lookup_steam_app_id_reuses_the_cached_index() {
        let root = tempfile::tempdir().unwrap();
        let steamapps = root.path().join("steamapps");
        let common = steamapps.join("common");
        std::fs::create_dir_all(&common).unwrap();
        write_manifest(&steamapps, 620, "Portal 2");
        invalidate_app_id_index_cache();

        assert_eq!(
            lookup_steam_app_id_for_path(&common.join("Portal 2")),
            Some(620)
        );

        // A manifest added after the index was built is not visible until the
        // cache is dropped — that is the point of the cache, and it is what
        // keeps a refresh burst from re-reading the whole directory per game.
        write_manifest(&steamapps, 440, "Team Fortress 2");
        assert_eq!(
            lookup_steam_app_id_for_path(&common.join("Team Fortress 2")),
            None
        );

        invalidate_app_id_index_cache();
        assert_eq!(
            lookup_steam_app_id_for_path(&common.join("Team Fortress 2")),
            Some(440)
        );
        invalidate_app_id_index_cache();
    }

    #[test]
    fn lookup_steam_app_id_rejects_a_non_steam_layout() {
        let root = tempfile::tempdir().unwrap();
        let games = root.path().join("Games");
        std::fs::create_dir_all(games.join("Foo")).unwrap();
        assert_eq!(lookup_steam_app_id_for_path(&games.join("Foo")), None);
    }

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
        assert!(manifest.is_fully_installed());
    }

    #[test]
    fn parse_acf_manifest_without_fully_installed_flag_is_not_authoritative() {
        let acf = r#"
"AppState"
{
    "name"		"Partial Game"
    "StateFlags"		"2"
    "installdir"		"PartialGame"
}
"#;
        let manifest = parse_acf_manifest(acf).unwrap();
        assert!(!manifest.is_fully_installed());
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
        assert!(!is_steam_tool("Cyberpunk 2077"));
        assert!(!is_steam_tool("Sample Adventure"));
    }

    #[test]
    fn steam_scanner_nonexistent_path_returns_empty() {
        let scanner = SteamScanner::with_path(PathBuf::from(r"C:\NonExistent\Steam"));
        let result = scanner.scan(DiscoveryScanMode::Full).unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn manifest_backed_small_install_is_discovered_without_executable_probe() {
        let _guard = crate::discovery::test_sync::lock_discovery_test();

        let temp = tempfile::TempDir::new().unwrap();
        let steamapps = temp.path().join("steamapps");
        let game_dir = steamapps.join("common").join("wallpaper_engine");
        std::fs::create_dir_all(&game_dir).unwrap();
        std::fs::write(game_dir.join("payload.bin"), vec![0_u8; 1024]).unwrap();
        std::fs::write(
            steamapps.join("appmanifest_431960.acf"),
            r#""AppState"
{
    "appid" "431960"
    "name" "Wallpaper Engine"
    "StateFlags" "4"
    "installdir" "wallpaper_engine"
}"#,
        )
        .unwrap();

        let games = SteamScanner::with_path(temp.path().to_path_buf())
            .scan(DiscoveryScanMode::Full)
            .unwrap();

        assert_eq!(games.len(), 1);
        assert_eq!(games[0].name, "Wallpaper Engine");
        assert_eq!(games[0].steam_app_id, Some(431_960));
        assert_eq!(games[0].path, game_dir);
    }

    #[test]
    fn incomplete_manifest_does_not_authorize_partial_install() {
        let _guard = crate::discovery::test_sync::lock_discovery_test();

        let temp = tempfile::TempDir::new().unwrap();
        let steamapps = temp.path().join("steamapps");
        let game_dir = steamapps.join("common").join("partial_game");
        std::fs::create_dir_all(&game_dir).unwrap();
        std::fs::write(game_dir.join("partial.bin"), vec![0_u8; 1024]).unwrap();
        std::fs::write(
            steamapps.join("appmanifest_123.acf"),
            r#""AppState"
{
    "appid" "123"
    "name" "Partial Game"
    "StateFlags" "2"
    "installdir" "partial_game"
}"#,
        )
        .unwrap();

        let games = SteamScanner::with_path(temp.path().to_path_buf())
            .scan(DiscoveryScanMode::Full)
            .unwrap();

        assert!(games.is_empty());
    }
}
