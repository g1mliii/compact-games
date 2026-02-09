use super::platform::{GameInfo, PlatformScanner};

/// Default Steam library location.
const DEFAULT_STEAM_PATH: &str = r"C:\Program Files (x86)\Steam";

pub struct SteamScanner {
    steam_path: std::path::PathBuf,
}

impl SteamScanner {
    pub fn new() -> Self {
        Self {
            steam_path: std::path::PathBuf::from(DEFAULT_STEAM_PATH),
        }
    }

    pub fn with_path(steam_path: std::path::PathBuf) -> Self {
        Self { steam_path }
    }
}

impl Default for SteamScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformScanner for SteamScanner {
    fn scan(&self) -> Vec<GameInfo> {
        // TODO: Phase 4 implementation
        // 1. Parse libraryfolders.vdf for all library paths
        // 2. For each library, scan steamapps/common/
        // 3. Parse appmanifest_*.acf for game metadata
        // 4. Calculate folder sizes
        // 5. Check compression status
        log::info!("Steam scan: {} (not yet implemented)", self.steam_path.display());
        Vec::new()
    }

    fn platform_name(&self) -> &'static str {
        "Steam"
    }
}
