use super::platform::{GameInfo, PlatformScanner};

pub struct GogScanner;

impl Default for GogScanner {
    fn default() -> Self {
        Self
    }
}

impl PlatformScanner for GogScanner {
    fn scan(&self) -> Vec<GameInfo> {
        // TODO: Phase 4 implementation
        // 1. Read Windows registry for GOG Galaxy install path
        // 2. Parse Galaxy database for installed games
        // 3. Calculate folder sizes
        log::info!("GOG scan: not yet implemented");
        Vec::new()
    }

    fn platform_name(&self) -> &'static str {
        "GOG Galaxy"
    }
}
