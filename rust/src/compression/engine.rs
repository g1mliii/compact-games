use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use crossbeam_channel::{bounded, Receiver};
use serde::{Deserialize, Serialize};

mod engine_safety;
mod estimation;
mod estimation_runtime;
mod operation_session;
mod path_guard;
#[cfg(windows)]
mod wof_ops;

use super::algorithm::CompressionAlgorithm;
use super::error::CompressionError;
use crate::progress::reporter::{EngineCounters, ProgressReporter};
use crate::progress::tracker::CompressionProgress;

pub use self::engine_safety::SafetyConfig;
use self::engine_safety::{run_safety_checks, DirectStoragePolicy};
use self::operation_session::{OperationGuard, OperationLock, OperationSession};
use self::path_guard::safe_file_iter;

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressionEstimate {
    pub scanned_files: u64,
    pub sampled_bytes: u64,
    pub estimated_saved_bytes: u64,
    pub artwork_candidate_path: Option<PathBuf>,
    pub executable_candidate_path: Option<PathBuf>,
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
pub struct ManifestFile {
    pub path: PathBuf,
    pub logical_size_hint: Option<u64>,
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
        self.cancelled.store(true, Ordering::Release);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    fn reset(&self) {
        self.cancelled.store(false, Ordering::Release);
    }
}

impl Default for CancellationToken {
    fn default() -> Self {
        Self::new()
    }
}

const MIN_COMPRESSIBLE_SIZE: u64 = 4096;
const USE_ADAPTIVE_ESTIMATION: bool = true;

#[derive(Clone, Default)]
struct EstimateTotals {
    scanned_files: u64,
    sampled_bytes: u64,
    estimated_saved_bytes: u64,
    saw_cancel: bool,
    artwork_candidate: Option<EstimateCandidate>,
    executable_candidate: Option<EstimateCandidate>,
}

#[derive(Clone)]
struct EstimateCandidate {
    score: u16,
    path: PathBuf,
    path_len: usize,
}

impl EstimateTotals {
    fn merge(self, other: Self) -> Self {
        Self {
            scanned_files: self.scanned_files.saturating_add(other.scanned_files),
            sampled_bytes: self.sampled_bytes.saturating_add(other.sampled_bytes),
            estimated_saved_bytes: self
                .estimated_saved_bytes
                .saturating_add(other.estimated_saved_bytes),
            saw_cancel: self.saw_cancel || other.saw_cancel,
            artwork_candidate: select_best_candidate(
                self.artwork_candidate,
                other.artwork_candidate,
            ),
            executable_candidate: select_best_candidate(
                self.executable_candidate,
                other.executable_candidate,
            ),
        }
    }
}

fn select_best_candidate(
    left: Option<EstimateCandidate>,
    right: Option<EstimateCandidate>,
) -> Option<EstimateCandidate> {
    match (left, right) {
        (None, None) => None,
        (Some(candidate), None) | (None, Some(candidate)) => Some(candidate),
        (Some(left), Some(right)) => {
            if left.score > right.score {
                Some(left)
            } else if right.score > left.score {
                Some(right)
            } else if left.path_len <= right.path_len {
                Some(left)
            } else {
                Some(right)
            }
        }
    }
}

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

    /// Build a per-request file manifest for traversal reuse.
    ///
    /// Intended for immediate reuse inside a single compression action
    /// (estimate + compression), not for long-term caching.
    pub fn build_file_manifest(
        &self,
        folder: &Path,
    ) -> Result<Vec<ManifestFile>, CompressionError> {
        self.validate_path(folder)?;
        if self.cancel_token.is_cancelled() {
            return Err(CompressionError::Cancelled);
        }
        Ok(Self::file_iter(folder)?
            .map(|entry| {
                let logical_size_hint = entry.metadata().ok().map(|m| m.len());
                ManifestFile {
                    path: entry.into_path(),
                    logical_size_hint,
                }
            })
            .collect())
    }

    pub fn compress_folder_with_progress(
        &self,
        folder: &Path,
        game_name: Arc<str>,
    ) -> Result<CompressionProgressHandle, CompressionError> {
        let file_manifest = self.build_file_manifest(folder)?;
        self.compress_folder_with_progress_with_manifest(folder, game_name, file_manifest)
    }

    pub fn compress_folder_with_progress_with_manifest(
        &self,
        folder: &Path,
        game_name: Arc<str>,
        file_manifest: Vec<ManifestFile>,
    ) -> Result<CompressionProgressHandle, CompressionError> {
        self.validate_path(folder)?;
        run_safety_checks(folder, self.directstorage_policy, self.safety.as_ref())?;
        let engine = self.clone();
        let operation = self.begin_operation();
        let files_total = file_manifest.len() as u64;

        let (progress_ready_tx, progress_ready_rx) = bounded(1);
        let (result_tx, result_rx) = bounded(1);

        self.files_total.store(files_total, Ordering::Relaxed);
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

            let result = engine.compress_impl_from_manifest(file_manifest);

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

    fn validate_path(&self, path: &Path) -> Result<(), CompressionError> {
        match std::fs::metadata(path) {
            Err(_) => Err(CompressionError::PathNotFound(path.to_path_buf())),
            Ok(m) if !m.is_dir() => Err(CompressionError::NotADirectory(path.to_path_buf())),
            Ok(_) => Ok(()),
        }
    }

    fn file_iter(
        folder: &Path,
    ) -> Result<impl Iterator<Item = walkdir::DirEntry> + '_, CompressionError> {
        let canonical_root =
            std::fs::canonicalize(folder).map_err(|source| CompressionError::Io { source })?;
        Ok(safe_file_iter(folder, canonical_root))
    }

    #[cfg(not(windows))]
    fn compress_impl(&self, _folder: &Path) -> Result<CompressionStats, CompressionError> {
        Err(CompressionError::WofApiError {
            message: "WOF compression requires Windows".into(),
        })
    }

    #[cfg(not(windows))]
    fn compress_impl_from_manifest(
        &self,
        _files: Vec<ManifestFile>,
    ) -> Result<CompressionStats, CompressionError> {
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
