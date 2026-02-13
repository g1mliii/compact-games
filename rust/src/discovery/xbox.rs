use super::platform::{GameInfo, PlatformScanner};

const DEFAULT_XBOX_PATH: &str = r"C:\XboxGames";

pub struct XboxScanner {
    xbox_path: std::path::PathBuf,
}

impl XboxScanner {
    pub fn new() -> Self {
        Self {
            xbox_path: std::path::PathBuf::from(DEFAULT_XBOX_PATH),
        }
    }
}

impl Default for XboxScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformScanner for XboxScanner {
    fn scan(&self) -> Vec<GameInfo> {
        // TODO: Phase 4 implementation
        // 1. Scan C:\XboxGames default path
        // 2. Handle UWP package permissions
        // 3. Calculate folder sizes
        log::info!(
            "Xbox scan: {} (not yet implemented)",
            self.xbox_path.display()
        );
        Vec::new()
    }

    fn platform_name(&self) -> &'static str {
        "Xbox Game Pass"
    }
}
