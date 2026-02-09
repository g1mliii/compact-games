use std::path::PathBuf;

use super::platform::{GameInfo, PlatformScanner};

pub struct CustomScanner {
    paths: Vec<PathBuf>,
}

impl CustomScanner {
    pub fn new(paths: Vec<PathBuf>) -> Self {
        Self { paths }
    }
}

impl PlatformScanner for CustomScanner {
    fn scan(&self) -> Vec<GameInfo> {
        // TODO: Phase 4 implementation
        // 1. For each user-specified path, scan for game-like folders
        // 2. Calculate folder sizes
        log::info!("Custom scan: {:?} (not yet implemented)", self.paths);
        Vec::new()
    }

    fn platform_name(&self) -> &'static str {
        "Custom"
    }
}
