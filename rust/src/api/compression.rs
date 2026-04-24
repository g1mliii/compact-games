//! Compression API exposed to Flutter via FRB.
//!
//! Uses a module-level `OnceLock<Mutex<..>>` to track the active
//! manual compression/decompression operation so it can be cancelled from Dart.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use crossbeam_channel::RecvTimeoutError;
use flutter_rust_bridge::frb;
use sysinfo::System;

use super::types::{
    FrbCompressionAlgorithm, FrbCompressionError, FrbCompressionEstimate, FrbCompressionProgress,
    FrbCompressionStats, FrbEstimateContext,
};
use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::engine::{
    CancellationToken, CompressionEngine, CompressionProgressHandle, EstimateGameContext,
};
use crate::compression::error::CompressionError;
use crate::compression::history::{
    persist_if_dirty, record_compression, CompressionHistoryEntry, EstimateSnapshot,
};

use crate::compression::thread_policy::compute_thread_policy;
use crate::frb_generated::StreamSink;
use crate::progress::tracker::CompressionProgress;
use crate::safety::directstorage::is_directstorage_game;

// ── Active manual-operation tracking ──────────────────────────────────

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

fn install_active_operation(cancel_token: &CancellationToken) -> Result<(), FrbCompressionError> {
    let mut guard = active_lock().lock().unwrap_or_else(|e| {
        log::warn!("ACTIVE manual-operation lock was poisoned; recovering");
        e.into_inner()
    });
    if guard.is_some() {
        return Err(FrbCompressionError::IoError {
            message: "A compression or decompression operation is already in progress".into(),
        });
    }
    *guard = Some(ActiveCompression {
        cancel_token: cancel_token.clone(),
    });
    Ok(())
}

fn clear_active_operation() {
    let mut guard = active_lock().lock().unwrap_or_else(|e| {
        log::warn!("ACTIVE manual-operation lock was poisoned during cleanup; recovering");
        e.into_inner()
    });
    *guard = None;
}

fn rollback_active_operation() {
    let mut guard = active_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("ACTIVE manual-operation lock was poisoned during rollback; recovering");
        poisoned.into_inner()
    });
    *guard = None;
    drop(guard);
    set_active_progress(None);
}

fn drain_progress_stream(
    handle: CompressionProgressHandle,
    cancel_token: &CancellationToken,
    sink: StreamSink<FrbCompressionProgress>,
) -> Option<Result<crate::compression::engine::CompressionStats, CompressionError>> {
    let CompressionProgressHandle { progress, result } = handle;
    let mut sink_is_open = true;

    loop {
        match progress.recv_timeout(Duration::from_millis(200)) {
            Ok(progress) => {
                set_active_progress(Some(progress.clone()));
                let frb_progress: FrbCompressionProgress = progress.into();
                if sink_is_open && sink.add(frb_progress).is_err() {
                    cancel_token.cancel();
                    sink_is_open = false;
                }
            }
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }

    result.recv().ok()
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
    allow_directstorage_override: bool,
    io_parallelism_override: Option<u64>,
    sink: StreamSink<FrbCompressionProgress>,
) -> Result<FrbCompressionStats, FrbCompressionError> {
    let algo: CompressionAlgorithm = algorithm.into();
    let path = PathBuf::from(&game_path);

    // User-initiated compression: full parallelism (is_background = false)
    let policy = compute_thread_policy(
        &path,
        false,
        current_cpu_usage_percent(),
        io_override_to_usize(io_parallelism_override),
    );
    let engine = CompressionEngine::new(algo)
        .with_thread_policy(policy)
        .with_directstorage_override(allow_directstorage_override);
    let cancel_token = engine.cancel_token();
    let file_manifest = match engine.build_file_manifest(&path) {
        Ok(files) => files,
        Err(e) => return Err(e.into()),
    };

    let estimate_snapshot = match engine.estimate_folder_savings_with_manifest_and_context(
        &path,
        &file_manifest,
        EstimateGameContext {
            game_name: Some(&game_name),
            steam_app_id: None,
            known_size_bytes: None,
        },
    ) {
        Ok(est) => Some(EstimateSnapshot {
            scanned_files: est.scanned_files,
            sampled_bytes: est.sampled_bytes,
            estimated_saved_bytes: est.estimated_saved_bytes,
        }),
        Err(_) => None,
    };

    install_active_operation(&cancel_token)?;
    set_active_progress(None);

    let handle = match engine.compress_folder_with_progress_with_manifest(
        &path,
        Arc::from(game_name.clone()),
        file_manifest,
    ) {
        Ok(handle) => handle,
        Err(e) => {
            rollback_active_operation();
            return Err(e.into());
        }
    };

    let result = drain_progress_stream(handle, &cancel_token, sink);

    clear_active_operation();
    set_active_progress(None);

    match result {
        Some(Ok(stats)) => {
            let saved = stats.original_bytes.saturating_sub(stats.compressed_bytes);
            let saved_ratio = if stats.original_bytes > 0 {
                (saved as f64 / stats.original_bytes as f64) * 100.0
            } else {
                0.0
            };
            log::info!(
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

            record_compression(CompressionHistoryEntry::from_compression_stats(
                game_path.clone(),
                game_name.clone(),
                estimate_snapshot,
                &stats,
                algo,
            ));

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

/// Cancel the active manual compression/decompression job.
#[frb(sync)]
pub fn cancel_compression() {
    let guard = active_lock().lock().unwrap_or_else(|e| {
        log::warn!("ACTIVE manual-operation lock was poisoned during cancel; recovering");
        e.into_inner()
    });
    if let Some(active) = guard.as_ref() {
        active.cancel_token.cancel();
    }
}

/// Return the latest known progress for the active manual operation.
#[frb(sync)]
pub fn get_compression_progress() -> Option<FrbCompressionProgress> {
    let guard = active_progress_lock().lock().unwrap_or_else(|e| {
        log::warn!("ACTIVE progress lock was poisoned during read; recovering");
        e.into_inner()
    });
    // Convert to FRB type only when requested (cheap Arc<str> clone on CompressionProgress)
    guard.clone().map(Into::into)
}

/// Decompress a game folder with progress streaming.
pub fn decompress_game(
    game_path: String,
    game_name: String,
    io_parallelism_override: Option<u64>,
    sink: StreamSink<FrbCompressionProgress>,
) -> Result<(), FrbCompressionError> {
    let path = PathBuf::from(&game_path);
    // User-initiated decompression: full parallelism
    let policy = compute_thread_policy(
        &path,
        false,
        current_cpu_usage_percent(),
        io_override_to_usize(io_parallelism_override),
    );
    let engine = CompressionEngine::new(CompressionAlgorithm::default()).with_thread_policy(policy);
    let cancel_token = engine.cancel_token();

    install_active_operation(&cancel_token)?;
    set_active_progress(None);

    let handle = match engine.decompress_folder_with_progress(&path, Arc::from(game_name)) {
        Ok(handle) => handle,
        Err(e) => {
            rollback_active_operation();
            return Err(e.into());
        }
    };

    let result = drain_progress_stream(handle, &cancel_token, sink);

    clear_active_operation();
    set_active_progress(None);

    match result {
        Some(Ok(stats)) => {
            let restored = stats.original_bytes.saturating_sub(stats.compressed_bytes);
            log::info!(
                "[decompression][summary] game=\"{}\" processed={} original={} compressed={} restored={}",
                game_path,
                stats.files_processed,
                stats.original_bytes,
                stats.compressed_bytes,
                restored
            );
            Ok(())
        }
        Some(Err(CompressionError::Cancelled)) => Ok(()),
        Some(Err(e)) => Err(e.into()),
        None if cancel_token.is_cancelled() => Ok(()),
        None => Err(FrbCompressionError::IoError {
            message: "Decompression ended without a result".into(),
        }),
    }
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
    context: FrbEstimateContext,
) -> Result<FrbCompressionEstimate, FrbCompressionError> {
    let path = PathBuf::from(&game_path);
    let algo: CompressionAlgorithm = algorithm.into();
    let engine = CompressionEngine::new(algo);
    let estimate = engine.estimate_folder_savings_with_context(
        &path,
        EstimateGameContext {
            game_name: context.game_name.as_deref(),
            steam_app_id: context.steam_app_id,
            known_size_bytes: context.known_size_bytes,
        },
    )?;
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

/// Cached CPU monitor that persists between calls so `sysinfo` can compute
/// deltas accurately. A fresh `System::new()` + single `refresh_cpu_all()`
/// always returns ~0% because `sysinfo` needs two consecutive refreshes with a
/// time gap to measure actual usage.
fn current_cpu_usage_percent() -> Option<f32> {
    use std::sync::Mutex;
    use std::time::Instant;

    static CPU_MONITOR: OnceLock<Mutex<(System, Instant)>> = OnceLock::new();
    const MIN_REFRESH_INTERVAL: Duration = Duration::from_millis(500);

    let monitor = CPU_MONITOR.get_or_init(|| {
        let mut sys = System::new();
        sys.refresh_cpu_all();
        Mutex::new((sys, Instant::now()))
    });

    let mut guard = monitor.lock().unwrap_or_else(|e| {
        log::warn!("CPU monitor lock poisoned; recovering");
        e.into_inner()
    });

    let (ref mut sys, ref mut last_refresh) = *guard;
    if last_refresh.elapsed() >= MIN_REFRESH_INTERVAL {
        sys.refresh_cpu_all();
        *last_refresh = Instant::now();
    }

    let usage = sys.global_cpu_usage();
    // sysinfo returns 0.0 until a second refresh completes after a delay.
    // In that case, return None so thread_policy falls through to defaults.
    if usage <= 0.01 {
        None
    } else {
        Some(usage)
    }
}

fn io_override_to_usize(io_parallelism_override: Option<u64>) -> Option<usize> {
    crate::utils::io_parallelism_override_to_usize(io_parallelism_override)
}
