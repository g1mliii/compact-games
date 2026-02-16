//! Compression API exposed to Flutter via FRB.
//!
//! Uses a module-level `OnceLock<Mutex<..>>` to track the active
//! compression job so it can be cancelled from Dart.

use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use crossbeam_channel::RecvTimeoutError;
use flutter_rust_bridge::frb;

use super::types::{
    FrbCompressionAlgorithm, FrbCompressionError, FrbCompressionProgress, FrbCompressionStats,
};
use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::engine::{CancellationToken, CompressionEngine};
use crate::frb_generated::StreamSink;
use crate::safety::directstorage::is_directstorage_game;

// ── Active compression tracking ───────────────────────────────────────

struct ActiveCompression {
    cancel_token: CancellationToken,
}

static ACTIVE: OnceLock<Mutex<Option<ActiveCompression>>> = OnceLock::new();
static ACTIVE_PROGRESS: OnceLock<Mutex<Option<FrbCompressionProgress>>> = OnceLock::new();

fn active_lock() -> &'static Mutex<Option<ActiveCompression>> {
    ACTIVE.get_or_init(|| Mutex::new(None))
}

fn active_progress_lock() -> &'static Mutex<Option<FrbCompressionProgress>> {
    ACTIVE_PROGRESS.get_or_init(|| Mutex::new(None))
}

fn set_active_progress(progress: Option<FrbCompressionProgress>) {
    let mut guard = active_progress_lock().lock().unwrap_or_else(|e| {
        log::warn!("ACTIVE progress lock was poisoned; recovering");
        e.into_inner()
    });
    *guard = progress;
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

    let handle = match engine.compress_folder_with_progress(&path, game_name) {
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
                let frb_progress: FrbCompressionProgress = progress.into();
                set_active_progress(Some(frb_progress.clone()));
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
        Some(Ok(stats)) => Ok(stats.into()),
        Some(Err(e)) => Err(e.into()),
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
    guard.clone()
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

/// Check if a game uses DirectStorage.
#[frb(sync)]
pub fn is_directstorage(game_path: String) -> bool {
    is_directstorage_game(Path::new(&game_path))
}
