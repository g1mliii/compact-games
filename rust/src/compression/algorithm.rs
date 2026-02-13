use serde::{Deserialize, Serialize};

/// Compression algorithms available via the Windows Overlay Filter (WOF).
///
/// These map to `FILE_PROVIDER_COMPRESSION_*` constants used by
/// `WofSetFileDataLocation`. Unlike basic NTFS compression (LZNT1),
/// WOF compression is transparent to applications and offers better
/// ratios with modern algorithms.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum CompressionAlgorithm {
    /// Fast compression, moderate ratio. Recommended default for games.
    #[default]
    Xpress4K,
    /// Balanced compression and speed.
    Xpress8K,
    /// Better compression ratio, still reasonably fast.
    Xpress16K,
    /// Maximum compression, significantly slower decompression.
    /// Not recommended for games due to load-time impact.
    Lzx,
}

impl CompressionAlgorithm {
    /// Returns the WOF `FILE_PROVIDER_COMPRESSION_*` constant.
    pub fn wof_algorithm_id(&self) -> u32 {
        match self {
            Self::Xpress4K => 0,  // FILE_PROVIDER_COMPRESSION_XPRESS4K
            Self::Lzx => 1,       // FILE_PROVIDER_COMPRESSION_LZX
            Self::Xpress8K => 2,  // FILE_PROVIDER_COMPRESSION_XPRESS8K
            Self::Xpress16K => 3, // FILE_PROVIDER_COMPRESSION_XPRESS16K
        }
    }

    /// Returns the equivalent `compact.exe /exe:` flag value.
    pub fn compact_exe_flag(&self) -> &'static str {
        match self {
            Self::Xpress4K => "xpress4k",
            Self::Xpress8K => "xpress8k",
            Self::Xpress16K => "xpress16k",
            Self::Lzx => "lzx",
        }
    }

    /// Human-readable label for UI display.
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Xpress4K => "XPRESS 4K (Fast)",
            Self::Xpress8K => "XPRESS 8K (Balanced)",
            Self::Xpress16K => "XPRESS 16K (Better Ratio)",
            Self::Lzx => "LZX (Maximum)",
        }
    }
}

impl std::fmt::Display for CompressionAlgorithm {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.display_name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_xpress4k() {
        assert_eq!(
            CompressionAlgorithm::default(),
            CompressionAlgorithm::Xpress4K
        );
    }

    #[test]
    fn wof_ids_are_distinct() {
        let algorithms = [
            CompressionAlgorithm::Xpress4K,
            CompressionAlgorithm::Xpress8K,
            CompressionAlgorithm::Xpress16K,
            CompressionAlgorithm::Lzx,
        ];
        let ids: Vec<u32> = algorithms.iter().map(|a| a.wof_algorithm_id()).collect();
        let unique: std::collections::HashSet<u32> = ids.iter().copied().collect();
        assert_eq!(ids.len(), unique.len(), "WOF algorithm IDs must be unique");
    }

    #[test]
    fn serde_roundtrip() {
        let algo = CompressionAlgorithm::Xpress16K;
        let json = serde_json::to_string(&algo).unwrap();
        let parsed: CompressionAlgorithm = serde_json::from_str(&json).unwrap();
        assert_eq!(algo, parsed);
    }
}
