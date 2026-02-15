use serde::{Deserialize, Serialize};

/// Compression algorithms available via the Windows Overlay Filter (WOF).
///
/// These map to `FILE_PROVIDER_COMPRESSION_*` constants used by
/// `WofSetFileDataLocation`. Unlike basic NTFS compression (LZNT1),
/// WOF compression is transparent to applications and offers better
/// ratios with modern algorithms.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum CompressionAlgorithm {

    #[default]
    Xpress4K,
    Xpress8K,
    Xpress16K,
    Lzx,
}

impl CompressionAlgorithm {
    pub fn wof_algorithm_id(&self) -> u32 {
        match self {
            Self::Xpress4K => 0,
            Self::Lzx => 1,
            Self::Xpress8K => 2,
            Self::Xpress16K => 3,
        }
    }

    pub fn from_wof_id(id: u32) -> Option<Self> {
        match id {
            0 => Some(Self::Xpress4K),
            1 => Some(Self::Lzx),
            2 => Some(Self::Xpress8K),
            3 => Some(Self::Xpress16K),
            _ => None,
        }
    }

    pub fn compact_exe_flag(&self) -> &'static str {
        match self {
            Self::Xpress4K => "xpress4k",
            Self::Xpress8K => "xpress8k",
            Self::Xpress16K => "xpress16k",
            Self::Lzx => "lzx",
        }
    }

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
    fn wof_id_roundtrip() {
        let algorithms = [
            CompressionAlgorithm::Xpress4K,
            CompressionAlgorithm::Xpress8K,
            CompressionAlgorithm::Xpress16K,
            CompressionAlgorithm::Lzx,
        ];
        for algo in &algorithms {
            let id = algo.wof_algorithm_id();
            let back = CompressionAlgorithm::from_wof_id(id);
            assert_eq!(
                back,
                Some(*algo),
                "round-trip failed for {algo:?} (id={id})"
            );
        }
    }

    #[test]
    fn from_wof_id_unknown_returns_none() {
        assert_eq!(CompressionAlgorithm::from_wof_id(99), None);
    }

    #[test]
    fn serde_roundtrip() {
        let algo = CompressionAlgorithm::Xpress16K;
        let json = serde_json::to_string(&algo).unwrap();
        let parsed: CompressionAlgorithm = serde_json::from_str(&json).unwrap();
        assert_eq!(algo, parsed);
    }
}
