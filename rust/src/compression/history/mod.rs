use serde::{Deserialize, Serialize};

pub mod adaptive;
pub mod cache;

pub use cache::{get_historical_stats, persist_if_dirty, record_compression};

use super::algorithm::CompressionAlgorithm;

/// Single compression history entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressionHistoryEntry {
    pub game_path: String,
    pub game_name: String,
    pub timestamp_ms: u64,

    // Pre-compression data
    pub estimate: EstimateSnapshot,

    // Post-compression data
    pub actual_stats: ActualStats,

    // Algorithm used
    pub algorithm: CompressionAlgorithm,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EstimateSnapshot {
    pub scanned_files: u64,
    pub sampled_bytes: u64,
    pub estimated_saved_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActualStats {
    pub original_bytes: u64,
    pub compressed_bytes: u64,
    pub actual_saved_bytes: u64,
    pub files_processed: u64,
}

impl CompressionHistoryEntry {
    /// Calculate estimate accuracy (1.0 = perfect, <1.0 = under-estimated, >1.0 = over-estimated)
    pub fn estimate_accuracy_ratio(&self) -> f64 {
        if self.estimate.estimated_saved_bytes == 0 {
            return 1.0;
        }
        self.actual_stats.actual_saved_bytes as f64 / self.estimate.estimated_saved_bytes as f64
    }
}
