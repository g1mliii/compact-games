use super::platform::{GameInfo, PlatformScanner};

const DEFAULT_EPIC_PATH: &str = r"C:\Program Files\Epic Games";

pub struct EpicScanner {
    epic_path: std::path::PathBuf,
}

impl EpicScanner {
    pub fn new() -> Self {
        Self {
            epic_path: std::path::PathBuf::from(DEFAULT_EPIC_PATH),
        }
    }
}

impl Default for EpicScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformScanner for EpicScanner {
    fn scan(&self) -> Vec<GameInfo> {
        // TODO: Phase 4 implementation
        // 1. Scan default Epic Games path
        // 2. Parse .egstore metadata for game info
        // 3. Calculate folder sizes
        log::info!("Epic scan: {} (not yet implemented)", self.epic_path.display());
        Vec::new()
    }

    fn platform_name(&self) -> &'static str {
        "Epic Games"
    }
}
