use serde::{Deserialize, Serialize};

pub mod adaptive;
pub mod cache;

pub use cache::{
    get_historical_stats, latest_compression_timestamp_ms, latest_compression_timestamps_by_path,
    persist_if_dirty, record_compression,
};

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

    /// Build a history entry from compression stats.
    ///
    /// `estimate` is optional — when absent (e.g. auto-compression path),
    /// a zeroed snapshot is used so the entry still records "last compressed"
    /// without biasing adaptive estimate learning.
    pub fn from_compression_stats(
        game_path: String,
        game_name: String,
        estimate: Option<EstimateSnapshot>,
        stats: &crate::compression::engine::CompressionStats,
        algorithm: CompressionAlgorithm,
    ) -> Self {
        Self {
            game_path,
            game_name,
            timestamp_ms: crate::utils::unix_now_ms(),
            estimate: estimate.unwrap_or(EstimateSnapshot {
                scanned_files: 0,
                sampled_bytes: 0,
                estimated_saved_bytes: 0,
            }),
            actual_stats: ActualStats {
                original_bytes: stats.original_bytes,
                compressed_bytes: stats.compressed_bytes,
                actual_saved_bytes: stats.bytes_saved(),
                files_processed: stats.files_processed,
            },
            algorithm,
            duration_ms: stats.duration_ms,
        }
    }
}
