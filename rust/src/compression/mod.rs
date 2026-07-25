pub mod algorithm;
pub mod community_db;
pub mod engine;
pub mod error;
pub mod history;
pub mod managed_paths;
pub mod thread_policy;
#[cfg(windows)]
pub mod wof;

#[cfg(test)]
mod tests;

use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::engine::CompressionStats;
use crate::compression::history::{record_compression, CompressionHistoryEntry, EstimateSnapshot};
use crate::compression::managed_paths::record_managed_compression;

/// Persist both durable records of a finished compression: the analytics
/// history entry and the restore-ownership ledger entry.
///
/// Every entry point that completes a compression must go through here, so a
/// new one cannot record history and silently leave the game unrestorable.
/// A ledger-write failure is logged rather than returned: the files are already
/// compressed and history is recorded, so surfacing an error would make callers
/// treat a finished game as unfinished and recompress it. The game is simply
/// not tracked for managed restore until the ledger becomes writable again.
pub fn record_successful_compression(
    game_path: String,
    game_name: String,
    estimate: Option<EstimateSnapshot>,
    stats: &CompressionStats,
    algorithm: CompressionAlgorithm,
) {
    record_compression(CompressionHistoryEntry::from_compression_stats(
        game_path.clone(),
        game_name.clone(),
        estimate,
        stats,
        algorithm,
    ));

    if let Err(error) = record_managed_compression(
        game_path.clone(),
        game_name,
        stats.original_bytes,
        stats.compressed_bytes,
    ) {
        log::warn!(
            "Compression completed for \"{game_path}\", but its restore record could not be saved: {error}"
        );
    }
}
