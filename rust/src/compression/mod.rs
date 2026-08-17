pub mod algorithm;
pub mod community_db;
pub mod engine;
pub mod error;
pub mod history;
pub mod io_priority;
pub mod managed_paths;
pub mod thread_policy;
#[cfg(windows)]
pub mod wof;

#[cfg(test)]
mod tests;

use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::engine::CompressionStats;
use crate::compression::history::{
    persist_if_dirty as persist_history_if_dirty, record_compression, CompressionHistoryEntry,
    EstimateSnapshot,
};
use crate::compression::managed_paths::record_managed_compression;
use crate::discovery::cache::{self, CachedGameStats};
use crate::discovery::utils::dir_stats_authoritative;

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
    // Resolve the discovery key before `record_compression` evicts the index.
    // This preserves the Xbox root -> Content mapping without treating every
    // unrelated top-level Content directory as an Xbox payload.
    let game_path_ref = std::path::Path::new(&game_path);
    let stats_path = crate::discovery::index::stats_path_for_game_path(game_path_ref)
        .unwrap_or_else(|| game_path_ref.to_path_buf());

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

    // `CompressionStats` intentionally describes operation accounting and can
    // omit small, inaccessible, or otherwise skipped files. Re-walk the exact
    // discovery payload so cached game totals remain authoritative.
    refresh_discovery_cache_after_compression(&stats_path);

    // Scheduler recovery consults history from a new process. Persist after
    // the replacement discovery entry so a forced close can never leave a
    // durable completion proof pointing at deliberately evicted metadata.
    persist_history_if_dirty();
}

fn refresh_discovery_cache_after_compression(stats_path: &std::path::Path) {
    if !stats_path.is_dir() {
        return;
    }

    let stats = match dir_stats_authoritative(stats_path) {
        Ok(stats) => stats,
        Err(error) => {
            log::warn!(
                "Compression completed, but authoritative discovery metadata could not be refreshed for {}: {error}",
                stats_path.display()
            );
            return;
        }
    };
    if stats.logical_size == 0 {
        return;
    }

    let token = cache::compute_change_token(stats_path, true);
    let is_directstorage = crate::safety::known_games::is_known_directstorage_game(stats_path);
    cache::upsert(
        stats_path,
        token,
        CachedGameStats::from_parts(
            stats.logical_size,
            stats.physical_size,
            stats.is_compressed,
            is_directstorage,
        ),
    );
    cache::persist_if_dirty();
}
