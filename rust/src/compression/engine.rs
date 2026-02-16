use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use crossbeam_channel::{bounded, Receiver};
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

mod engine_safety;
mod estimation;
mod operation_session;
#[cfg(windows)]
mod wof_ops;

use super::algorithm::CompressionAlgorithm;
use super::error::CompressionError;
use crate::progress::reporter::{EngineCounters, ProgressReporter};
use crate::progress::tracker::CompressionProgress;

pub use self::engine_safety::SafetyConfig;
use self::engine_safety::{run_safety_checks, DirectStoragePolicy};
use self::operation_session::{OperationGuard, OperationLock, OperationSession};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressionStats {
    pub original_bytes: u64,
    pub compressed_bytes: u64,
    pub files_processed: u64,
    pub files_skipped: u64,
    pub duration_ms: u64,
}

impl CompressionStats {
    pub fn savings_ratio(&self) -> f64 {
        if self.original_bytes == 0 {
            return 0.0;
        }
        1.0 - (self.compressed_bytes as f64 / self.original_bytes as f64)
    }

    pub fn bytes_saved(&self) -> u64 {
        self.original_bytes.saturating_sub(self.compressed_bytes)
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct CompressionEstimate {
    pub scanned_files: u64,
    pub sampled_bytes: u64,
    pub estimated_saved_bytes: u64,
}

impl CompressionEstimate {
    pub fn estimated_compressed_bytes(&self) -> u64 {
        self.sampled_bytes
            .saturating_sub(self.estimated_saved_bytes)
    }

    pub fn estimated_savings_ratio(&self) -> f64 {
        if self.sampled_bytes == 0 {
            return 0.0;
        }
        self.estimated_saved_bytes as f64 / self.sampled_bytes as f64
    }
}

pub struct CompressionProgressHandle {
    pub progress: Receiver<CompressionProgress>,
    pub result: Receiver<Result<CompressionStats, CompressionError>>,
}

#[derive(Debug, Clone)]
pub struct CancellationToken {
    cancelled: Arc<AtomicBool>,
}

impl CancellationToken {
    pub fn new() -> Self {
        Self {
            cancelled: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }

    fn reset(&self) {
        self.cancelled.store(false, Ordering::Relaxed);
    }
}

impl Default for CancellationToken {
    fn default() -> Self {
        Self::new()
    }
}

const MIN_COMPRESSIBLE_SIZE: u64 = 4096;

#[derive(Clone)]
pub struct CompressionEngine {
    algorithm: CompressionAlgorithm,
    cancel_token: CancellationToken,
    operation_lock: Arc<OperationLock>,
    files_processed: Arc<AtomicU64>,
    files_total: Arc<AtomicU64>,
    bytes_original: Arc<AtomicU64>,
    bytes_compressed: Arc<AtomicU64>,
    safety: Option<SafetyConfig>,
    directstorage_policy: DirectStoragePolicy,
}

impl CompressionEngine {
    pub fn new(algorithm: CompressionAlgorithm) -> Self {
        Self {
            algorithm,
            cancel_token: CancellationToken::new(),
            operation_lock: Arc::new(OperationLock::new()),
            files_processed: Arc::new(AtomicU64::new(0)),
            files_total: Arc::new(AtomicU64::new(0)),
            bytes_original: Arc::new(AtomicU64::new(0)),
            bytes_compressed: Arc::new(AtomicU64::new(0)),
            safety: None,
            directstorage_policy: DirectStoragePolicy::Block,
        }
    }

    pub fn cancel_token(&self) -> CancellationToken {
        self.cancel_token.clone()
    }

    pub fn progress(&self) -> (u64, u64, u64, u64) {
        (
            self.files_processed.load(Ordering::Relaxed),
            self.files_total.load(Ordering::Relaxed),
            self.bytes_original.load(Ordering::Relaxed),
            self.bytes_compressed.load(Ordering::Relaxed),
        )
    }

    pub fn engine_counters(&self) -> EngineCounters {
        EngineCounters {
            files_processed: self.files_processed.clone(),
            files_total: self.files_total.clone(),
            bytes_original: self.bytes_original.clone(),
            bytes_compressed: self.bytes_compressed.clone(),
        }
    }

    fn reset_counters(&self) {
        self.files_processed.store(0, Ordering::Relaxed);
        self.files_total.store(0, Ordering::Relaxed);
        self.bytes_original.store(0, Ordering::Relaxed);
        self.bytes_compressed.store(0, Ordering::Relaxed);
    }

    fn operation_guard(&self) -> OperationGuard {
        OperationGuard::acquire(self.operation_lock.clone())
    }

    #[cfg(test)]
    fn try_operation_guard(&self) -> Option<OperationGuard> {
        OperationGuard::try_acquire(self.operation_lock.clone())
    }

    fn begin_operation(&self) -> OperationSession {
        OperationSession::new(self)
    }

    fn is_recoverable_file_error(error: &CompressionError) -> bool {
        matches!(
            error,
            CompressionError::LockedFile { .. } | CompressionError::PermissionDenied { .. }
        )
    }

    pub fn compress_folder(&self, folder: &Path) -> Result<CompressionStats, CompressionError> {
        self.validate_path(folder)?;
        run_safety_checks(folder, self.directstorage_policy, self.safety.as_ref())?;
        let _operation = self.begin_operation();
        self.compress_impl(folder)
    }

    pub fn compress_folder_with_progress(
        &self,
        folder: &Path,
        game_name: Arc<str>,
    ) -> Result<CompressionProgressHandle, CompressionError> {
        self.validate_path(folder)?;
        run_safety_checks(folder, self.directstorage_policy, self.safety.as_ref())?;
        let folder = folder.to_path_buf();
        let engine = self.clone();
        let operation = self.begin_operation();

        let (progress_ready_tx, progress_ready_rx) = bounded(1);
        let (result_tx, result_rx) = bounded(1);

        std::thread::spawn(move || {
            let _operation = operation;

            let counters = engine.engine_counters();
            let (mut reporter, progress_rx) =
                ProgressReporter::new_with_baseline(counters, game_name, true);
            if progress_ready_tx.send(progress_rx).is_err() {
                reporter.mark_done();
                reporter.stop();
                return;
            }

            let result = engine.compress_impl(&folder);

            reporter.mark_done();
            reporter.stop();

            let _ = result_tx.send(result);
        });

        let progress_rx = progress_ready_rx.recv().map_err(|_| CompressionError::Io {
            source: std::io::Error::new(
                std::io::ErrorKind::BrokenPipe,
                "failed to initialize compression progress stream",
            ),
        })?;

        Ok(CompressionProgressHandle {
            progress: progress_rx,
            result: result_rx,
        })
    }

    pub fn decompress_folder(&self, folder: &Path) -> Result<(), CompressionError> {
        self.validate_path(folder)?;
        let _operation = self.begin_operation();
        self.decompress_impl(folder)
    }

    pub fn get_compression_ratio(folder: &Path) -> Result<f64, CompressionError> {
        if !folder.exists() {
            return Err(CompressionError::PathNotFound(folder.to_path_buf()));
        }
        Self::ratio_impl(folder)
    }

    pub fn estimate_folder_savings(
        &self,
        folder: &Path,
    ) -> Result<CompressionEstimate, CompressionError> {
        self.validate_path(folder)?;
        let mut scanned_files: u64 = 0;
        let mut sampled_bytes: u64 = 0;
        let mut estimated_saved_bytes: u64 = 0;
        let algorithm_scale_num = estimation::algorithm_scale_num(self.algorithm);

        for entry in Self::file_iter(folder) {
            if self.cancel_token.is_cancelled() {
                return Err(CompressionError::Cancelled);
            }

            let metadata = match entry.metadata() {
                Ok(m) => m,
                Err(_) => continue,
            };
            let file_size = metadata.len();
            scanned_files = scanned_files.saturating_add(1);
            sampled_bytes = sampled_bytes.saturating_add(file_size);

            if file_size < MIN_COMPRESSIBLE_SIZE {
                continue;
            }

            let (ratio_num, ratio_den) = estimation::compression_ratio_parts(entry.path());

            let saved = file_size
                .saturating_mul(ratio_num)
                .saturating_mul(algorithm_scale_num)
                / ratio_den.saturating_mul(100);
            estimated_saved_bytes = estimated_saved_bytes.saturating_add(saved);
        }

        Ok(CompressionEstimate {
            scanned_files,
            sampled_bytes,
            estimated_saved_bytes,
        })
    }

    fn validate_path(&self, path: &Path) -> Result<(), CompressionError> {
        match std::fs::metadata(path) {
            Err(_) => Err(CompressionError::PathNotFound(path.to_path_buf())),
            Ok(m) if !m.is_dir() => Err(CompressionError::NotADirectory(path.to_path_buf())),
            Ok(_) => Ok(()),
        }
    }

    fn file_iter(folder: &Path) -> impl Iterator<Item = walkdir::DirEntry> + '_ {
        WalkDir::new(folder)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file())
    }

    #[cfg(not(windows))]
    fn compress_impl(&self, _folder: &Path) -> Result<CompressionStats, CompressionError> {
        Err(CompressionError::WofApiError {
            message: "WOF compression requires Windows".into(),
        })
    }

    #[cfg(not(windows))]
    fn decompress_impl(&self, _folder: &Path) -> Result<(), CompressionError> {
        Err(CompressionError::WofApiError {
            message: "WOF decompression requires Windows".into(),
        })
    }

    #[cfg(not(windows))]
    fn ratio_impl(_folder: &Path) -> Result<f64, CompressionError> {
        Err(CompressionError::WofApiError {
            message: "WOF ratio query requires Windows".into(),
        })
    }
}

#[cfg(test)]
mod unit_tests;
