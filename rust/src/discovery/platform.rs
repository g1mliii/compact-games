use std::path::PathBuf;
use std::time::SystemTime;

use serde::{Deserialize, Serialize};

/// Supported game distribution platforms.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Platform {
    Steam,
    EpicGames,
    GogGalaxy,
    XboxGamePass,
    Custom,
}

impl std::fmt::Display for Platform {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Steam => write!(f, "Steam"),
            Self::EpicGames => write!(f, "Epic Games"),
            Self::GogGalaxy => write!(f, "GOG Galaxy"),
            Self::XboxGamePass => write!(f, "Xbox Game Pass"),
            Self::Custom => write!(f, "Custom"),
        }
    }
}

/// Information about a discovered game installation.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GameInfo {
    pub name: String,
    pub path: PathBuf,
    pub platform: Platform,
    pub size_bytes: u64,
    pub compressed_size: Option<u64>,
    pub is_compressed: bool,
    pub is_directstorage: bool,
    #[serde(default)]
    pub excluded: bool,
    pub last_played: Option<SystemTime>,
}

impl GameInfo {
    /// Space saved by compression, or 0 if not compressed.
    pub fn bytes_saved(&self) -> u64 {
        match self.compressed_size {
            Some(compressed) => self.size_bytes.saturating_sub(compressed),
            None => 0,
        }
    }

    /// Savings ratio as a percentage string (e.g. "34.2%").
    pub fn savings_display(&self) -> String {
        if !self.is_compressed || self.size_bytes == 0 {
            return String::from("Not compressed");
        }
        let ratio = self.bytes_saved() as f64 / self.size_bytes as f64 * 100.0;
        format!("{ratio:.1}%")
    }
}

/// Trait implemented by each platform scanner.
pub trait PlatformScanner {
    /// Scan for installed games from this platform.
    fn scan(&self) -> Vec<GameInfo>;

    /// Human-readable platform name.
    fn platform_name(&self) -> &'static str;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn game_info_bytes_saved_when_not_compressed() {
        let game = GameInfo {
            name: "Test Game".into(),
            path: PathBuf::from(r"C:\Games\Test"),
            platform: Platform::Steam,
            size_bytes: 10_000,
            compressed_size: None,
            is_compressed: false,
            is_directstorage: false,
            excluded: false,
            last_played: None,
        };
        assert_eq!(game.bytes_saved(), 0);
        assert_eq!(game.savings_display(), "Not compressed");
    }

    #[test]
    fn game_info_bytes_saved_when_compressed() {
        let game = GameInfo {
            name: "Test Game".into(),
            path: PathBuf::from(r"C:\Games\Test"),
            platform: Platform::Steam,
            size_bytes: 10_000,
            compressed_size: Some(6_000),
            is_compressed: true,
            is_directstorage: false,
            excluded: false,
            last_played: None,
        };
        assert_eq!(game.bytes_saved(), 4_000);
        assert_eq!(game.savings_display(), "40.0%");
    }

    #[test]
    fn serde_roundtrip() {
        let game = GameInfo {
            name: "Portal 2".into(),
            path: PathBuf::from(r"C:\Steam\steamapps\common\Portal 2"),
            platform: Platform::Steam,
            size_bytes: 12_000_000_000,
            compressed_size: Some(8_000_000_000),
            is_compressed: true,
            is_directstorage: false,
            excluded: false,
            last_played: None,
        };
        let json = serde_json::to_string(&game).unwrap();
        let parsed: GameInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.name, game.name);
        assert_eq!(parsed.platform, game.platform);
    }
}
