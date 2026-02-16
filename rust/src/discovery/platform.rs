use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Supported game distribution platforms.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Platform {
    Steam,
    EpicGames,
    GogGalaxy,
    UbisoftConnect,
    EaApp,
    BattleNet,
    XboxGamePass,
    Custom,
}

/// Discovery scan strategy.
///
/// `Quick` prioritizes responsiveness and may use cached or sampled metadata.
/// `Full` computes authoritative metadata and refreshes persistent cache entries.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DiscoveryScanMode {
    Quick,
    #[default]
    Full,
}

impl std::fmt::Display for Platform {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Steam => write!(f, "Steam"),
            Self::EpicGames => write!(f, "Epic Games"),
            Self::GogGalaxy => write!(f, "GOG Galaxy"),
            Self::UbisoftConnect => write!(f, "Ubisoft Connect"),
            Self::EaApp => write!(f, "EA App"),
            Self::BattleNet => write!(f, "Battle.net"),
            Self::XboxGamePass => write!(f, "Xbox Game Pass"),
            Self::Custom => write!(f, "Custom"),
        }
    }
}

/// Serialize SystemTime as milliseconds since Unix epoch for Flutter/Dart compatibility.
fn serialize_systemtime_millis<S>(
    time: &Option<SystemTime>,
    serializer: S,
) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    match time {
        Some(t) => {
            let millis = t
                .duration_since(UNIX_EPOCH)
                .map_err(serde::ser::Error::custom)?
                .as_millis() as i64;
            serializer.serialize_some(&millis)
        }
        None => serializer.serialize_none(),
    }
}

/// Deserialize SystemTime from milliseconds since Unix epoch.
fn deserialize_systemtime_millis<'de, D>(deserializer: D) -> Result<Option<SystemTime>, D::Error>
where
    D: Deserializer<'de>,
{
    let millis: Option<i64> = Option::deserialize(deserializer)?;
    match millis {
        Some(m) if m >= 0 => {
            // Safe: checked that m is non-negative
            Ok(Some(
                UNIX_EPOCH
                    .checked_add(std::time::Duration::from_millis(m as u64))
                    .ok_or_else(|| serde::de::Error::custom("timestamp overflow"))?,
            ))
        }
        Some(m) => {
            // Negative timestamp (pre-1970) - reject with error
            Err(serde::de::Error::custom(format!(
                "timestamp {} is before Unix epoch (1970-01-01)",
                m
            )))
        }
        None => Ok(None),
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
    #[serde(
        default,
        serialize_with = "serialize_systemtime_millis",
        deserialize_with = "deserialize_systemtime_millis"
    )]
    pub last_played: Option<SystemTime>,
}

impl GameInfo {
    /// Space saved by compression, or 0 if not compressed.
    #[must_use]
    pub fn bytes_saved(&self) -> u64 {
        match self.compressed_size {
            Some(compressed) => self.size_bytes.saturating_sub(compressed),
            None => 0,
        }
    }

    /// Savings ratio as a percentage string (e.g. "34.2%").
    #[must_use]
    #[allow(clippy::cast_precision_loss)]
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
    fn scan(&self, mode: DiscoveryScanMode) -> Result<Vec<GameInfo>, super::scan_error::ScanError>;

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

    #[test]
    fn game_info_zero_byte_game() {
        // Test division-by-zero guard
        let game = GameInfo {
            name: "Empty Game".into(),
            path: PathBuf::from(r"C:\Games\Empty"),
            platform: Platform::Custom,
            size_bytes: 0,
            compressed_size: Some(0),
            is_compressed: true,
            is_directstorage: false,
            excluded: false,
            last_played: None,
        };
        assert_eq!(game.bytes_saved(), 0);
        assert_eq!(game.savings_display(), "Not compressed");
    }

    #[test]
    fn game_info_pathological_compression() {
        // Test saturating_sub when compressed > uncompressed (shouldn't happen, but defensive)
        let game = GameInfo {
            name: "Broken Game".into(),
            path: PathBuf::from(r"C:\Games\Broken"),
            platform: Platform::Steam,
            size_bytes: 1_000,
            compressed_size: Some(2_000), // Pathological: compressed is larger
            is_compressed: true,
            is_directstorage: false,
            excluded: false,
            last_played: None,
        };
        // saturating_sub should prevent underflow, returning 0
        assert_eq!(game.bytes_saved(), 0);
    }

    #[test]
    fn systemtime_serialization() {
        use std::time::Duration;

        // Test with a specific timestamp
        let timestamp = UNIX_EPOCH + Duration::from_millis(1_609_459_200_000); // 2021-01-01 00:00:00 UTC
        let game = GameInfo {
            name: "Test Game".into(),
            path: PathBuf::from(r"C:\Games\Test"),
            platform: Platform::Steam,
            size_bytes: 10_000,
            compressed_size: None,
            is_compressed: false,
            is_directstorage: false,
            excluded: false,
            last_played: Some(timestamp),
        };

        // Serialize to JSON
        let json = serde_json::to_string(&game).unwrap();

        // Verify it contains the milliseconds value
        assert!(json.contains("1609459200000"));

        // Deserialize and verify round-trip
        let parsed: GameInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.last_played, Some(timestamp));
    }

    #[test]
    fn systemtime_serialization_none() {
        // Test None case for last_played
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

        let json = serde_json::to_string(&game).unwrap();
        let parsed: GameInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.last_played, None);
    }

    #[test]
    fn systemtime_deserialization_missing_field_defaults_to_none() {
        let json = r#"{
            "name": "Test Game",
            "path": "C:\\Games\\Test",
            "platform": "steam",
            "sizeBytes": 10000,
            "compressedSize": null,
            "isCompressed": false,
            "isDirectstorage": false,
            "excluded": false
        }"#;

        let parsed: GameInfo = serde_json::from_str(json).unwrap();
        assert_eq!(parsed.last_played, None);
    }

    #[test]
    fn systemtime_deserialization_rejects_negative() {
        // Test that negative timestamps (pre-1970) are rejected safely, not panicked
        let json = r#"{
            "name": "Test Game",
            "path": "C:\\Games\\Test",
            "platform": "steam",
            "sizeBytes": 10000,
            "compressedSize": null,
            "isCompressed": false,
            "isDirectstorage": false,
            "excluded": false,
            "lastPlayed": -1000
        }"#;

        let result: Result<GameInfo, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "Negative timestamp should be rejected with error, not panic"
        );
        let err_msg = result.unwrap_err().to_string();
        assert!(err_msg.contains("before Unix epoch"));
    }

    #[test]
    fn systemtime_deserialization_rejects_overflow() {
        // Test that timestamps beyond SystemTime's range are rejected safely
        let json = format!(
            r#"{{
            "name": "Test Game",
            "path": "C:\\Games\\Test",
            "platform": "steam",
            "sizeBytes": 10000,
            "compressedSize": null,
            "isCompressed": false,
            "isDirectstorage": false,
            "excluded": false,
            "lastPlayed": {}
        }}"#,
            i64::MAX
        );

        let result: Result<GameInfo, _> = serde_json::from_str(&json);
        assert!(
            result.is_err(),
            "Overflow timestamp should be rejected with error, not panic"
        );
        let err_msg = result.unwrap_err().to_string();
        assert!(err_msg.contains("overflow"));
    }
}
