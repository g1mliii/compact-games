//! Compression API exposed to Flutter via FRB.
//!
//! Uses a module-level `OnceLock<Mutex<..>>` to track the active
//! compression job so it can be cancelled from Dart.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use crossbeam_channel::RecvTimeoutError;
use flutter_rust_bridge::frb;

use super::types::{
    FrbCompressionAlgorithm, FrbCompressionError, FrbCompressionEstimate, FrbCompressionProgress,
    FrbCompressionStats,
};
use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::engine::{CancellationToken, CompressionEngine};
use crate::compression::error::CompressionError;
use crate::compression::history::{
    persist_if_dirty, record_compression, ActualStats, CompressionHistoryEntry, EstimateSnapshot,
};
use crate::frb_generated::StreamSink;
use crate::progress::tracker::CompressionProgress;
use crate::safety::directstorage::is_directstorage_game;

// ── Active compression tracking ───────────────────────────────────────

struct ActiveCompression {
    cancel_token: CancellationToken,
}

static ACTIVE: OnceLock<Mutex<Option<ActiveCompression>>> = OnceLock::new();
static ACTIVE_PROGRESS: OnceLock<Mutex<Option<CompressionProgress>>> = OnceLock::new();

fn active_lock() -> &'static Mutex<Option<ActiveCompression>> {
    ACTIVE.get_or_init(|| Mutex::new(None))
}

fn active_progress_lock() -> &'static Mutex<Option<CompressionProgress>> {
    ACTIVE_PROGRESS.get_or_init(|| Mutex::new(None))
}

fn set_active_progress(progress: Option<CompressionProgress>) {
    let mut guard = active_progress_lock().lock().unwrap_or_else(|e| {
        log::warn!("ACTIVE progress lock was poisoned; recovering");
        e.into_inner()
    });
    *guard = progress;
}

fn cancelled_stats() -> FrbCompressionStats {
    FrbCompressionStats {
        original_bytes: 0,
        compressed_bytes: 0,
        files_processed: 0,
        files_skipped: 0,
        duration_ms: 0,
    }
}

// ── Public API ────────────────────────────────────────────────────────

/// Start compression with progress streaming.
///
/// FRB translates `StreamSink<T>` in Rust to `Stream<T>` on the Dart side.
/// The function blocks on a thread-pool thread, forwarding crossbeam
/// channel messages to the sink. Dart listens via `await for`.
pub fn compress_game(
    game_path: String,
    game_name: String,
    algorithm: FrbCompressionAlgorithm,
    sink: StreamSink<FrbCompressionProgress>,
) -> Result<FrbCompressionStats, FrbCompressionError> {
    let algo: CompressionAlgorithm = algorithm.into();
    let path = PathBuf::from(&game_path);

    let engine = CompressionEngine::new(algo);
    let cancel_token = engine.cancel_token();
    let file_manifest = match engine.build_file_manifest(&path) {
        Ok(files) => files,
        Err(e) => return Err(e.into()),
    };

    // Capture estimate before compression for history tracking
    let estimate_snapshot =
        match engine.estimate_folder_savings_with_manifest(&path, &file_manifest) {
            Ok(est) => Some(EstimateSnapshot {
                scanned_files: est.scanned_files,
                sampled_bytes: est.sampled_bytes,
                estimated_saved_bytes: est.estimated_saved_bytes,
            }),
            Err(_) => None,
        };

    // Store cancel token for external cancellation access
    {
        let mut guard = active_lock().lock().unwrap_or_else(|e| {
            log::warn!("ACTIVE compression lock was poisoned; recovering");
            e.into_inner()
        });
        if guard.is_some() {
            return Err(FrbCompressionError::IoError {
                message: "A compression operation is already in progress".into(),
            });
        }
        *guard = Some(ActiveCompression {
            cancel_token: cancel_token.clone(),
        });
    }
    set_active_progress(None);

    let handle = match engine.compress_folder_with_progress_with_manifest(
        &path,
        Arc::from(game_name.clone()),
        file_manifest,
    ) {
        Ok(handle) => handle,
        Err(e) => {
            let mut guard = active_lock().lock().unwrap_or_else(|poisoned| {
                log::warn!(
                    "ACTIVE compression lock was poisoned during start rollback; recovering"
                );
                poisoned.into_inner()
            });
            *guard = None;
            drop(guard);
            set_active_progress(None);
            return Err(e.into());
        }
    };

    // Forward progress from crossbeam channel to FRB StreamSink
    let mut sink_is_open = true;
    loop {
        match handle.progress.recv_timeout(Duration::from_millis(200)) {
            Ok(progress) => {
                // Clone progress (cheap, Arc<str> for game_name) for storage
                set_active_progress(Some(progress.clone()));
                // Convert to FRB type only when sending to Dart
                let frb_progress: FrbCompressionProgress = progress.into();
                if sink_is_open && sink.add(frb_progress).is_err() {
                    // Dart side closed the stream — cancel compression but keep
                    // draining until the worker thread exits to avoid orphan work.
                    cancel_token.cancel();
                    sink_is_open = false;
                }
            }
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }

    // Read final result from worker before cleanup to avoid detached
    // compression work continuing after API return.
    let result = handle.result.recv().ok();

    // Cleanup
    {
        let mut guard = active_lock().lock().unwrap_or_else(|e| {
            log::warn!("ACTIVE compression lock was poisoned during cleanup; recovering");
            e.into_inner()
        });
        *guard = None;
    }
    set_active_progress(None);

    match result {
        Some(Ok(stats)) => {
            let saved = stats.original_bytes.saturating_sub(stats.compressed_bytes);
            let saved_ratio = if stats.original_bytes > 0 {
                (saved as f64 / stats.original_bytes as f64) * 100.0
            } else {
                0.0
            };
            log::warn!(
                "[compression][summary] game=\"{}\" algo={} processed={} skipped={} original={} compressed={} saved={} ({:.2}%)",
                game_path,
                algo,
                stats.files_processed,
                stats.files_skipped,
                stats.original_bytes,
                stats.compressed_bytes,
                saved,
                saved_ratio
            );

            // Record compression history for adaptive learning
            if let Some(est) = estimate_snapshot {
                let history_entry = CompressionHistoryEntry {
                    game_path: game_path.clone(),
                    game_name: game_name.clone(),
                    timestamp_ms: std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .ok()
                        .map(|d| d.as_millis() as u64)
                        .unwrap_or_default(),
                    estimate: est,
                    actual_stats: ActualStats {
                        original_bytes: stats.original_bytes,
                        compressed_bytes: stats.compressed_bytes,
                        actual_saved_bytes: stats.bytes_saved(),
                        files_processed: stats.files_processed,
                    },
                    algorithm: algo,
                    duration_ms: stats.duration_ms,
                };

                record_compression(history_entry);
            }

            Ok(stats.into())
        }
        Some(Err(CompressionError::Cancelled)) => Ok(cancelled_stats()),
        Some(Err(e)) => Err(e.into()),
        None if cancel_token.is_cancelled() => Ok(cancelled_stats()),
        None => Err(FrbCompressionError::IoError {
            message: "Compression ended without a result".into(),
        }),
    }
}

/// Cancel the active compression job.
#[frb(sync)]
pub fn cancel_compression() {
    let guard = active_lock().lock().unwrap_or_else(|e| {
        log::warn!("ACTIVE compression lock was poisoned during cancel; recovering");
        e.into_inner()
    });
    if let Some(active) = guard.as_ref() {
        active.cancel_token.cancel();
    }
}

/// Return the latest known progress for the active compression job.
#[frb(sync)]
pub fn get_compression_progress() -> Option<FrbCompressionProgress> {
    let guard = active_progress_lock().lock().unwrap_or_else(|e| {
        log::warn!("ACTIVE progress lock was poisoned during read; recovering");
        e.into_inner()
    });
    // Convert to FRB type only when requested (cheap Arc<str> clone on CompressionProgress)
    guard.clone().map(Into::into)
}

/// Decompress a game folder (no progress streaming needed).
pub fn decompress_game(game_path: String) -> Result<(), FrbCompressionError> {
    let path = PathBuf::from(&game_path);
    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    engine.decompress_folder(&path).map_err(Into::into)
}

/// Get the compression ratio for a folder.
pub fn get_compression_ratio(folder_path: String) -> Result<f64, FrbCompressionError> {
    let path = PathBuf::from(&folder_path);
    CompressionEngine::get_compression_ratio(&path).map_err(Into::into)
}

/// Estimate potential savings before compression.
pub fn estimate_compression_savings(
    game_path: String,
    algorithm: FrbCompressionAlgorithm,
) -> Result<FrbCompressionEstimate, FrbCompressionError> {
    let path = PathBuf::from(&game_path);
    let algo: CompressionAlgorithm = algorithm.into();
    let engine = CompressionEngine::new(algo);
    let estimate = engine.estimate_folder_savings(&path)?;
    Ok(estimate.into())
}

/// Check if a game uses DirectStorage.
#[frb(sync)]
pub fn is_directstorage(game_path: String) -> bool {
    is_directstorage_game(Path::new(&game_path))
}

/// Persist compression history to disk.
#[frb(sync)]
pub fn persist_compression_history() {
    persist_if_dirty();
}
