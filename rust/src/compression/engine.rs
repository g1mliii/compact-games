use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};

use crossbeam_channel::{bounded, Receiver};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use super::algorithm::CompressionAlgorithm;
use super::error::CompressionError;
use crate::progress::reporter::{EngineCounters, ProgressReporter};
use crate::progress::tracker::CompressionProgress;

#[cfg(windows)]
use super::wof::{self, CompressFileResult};

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
    operation_lock: Arc<Mutex<()>>,
    files_processed: Arc<AtomicU64>,
    files_total: Arc<AtomicU64>,
    bytes_original: Arc<AtomicU64>,
    bytes_compressed: Arc<AtomicU64>,
}

impl CompressionEngine {
    pub fn new(algorithm: CompressionAlgorithm) -> Self {
        Self {
            algorithm,
            cancel_token: CancellationToken::new(),
            operation_lock: Arc::new(Mutex::new(())),
            files_processed: Arc::new(AtomicU64::new(0)),
            files_total: Arc::new(AtomicU64::new(0)),
            bytes_original: Arc::new(AtomicU64::new(0)),
            bytes_compressed: Arc::new(AtomicU64::new(0)),
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

    fn operation_guard(&self) -> MutexGuard<'_, ()> {
        match self.operation_lock.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                log::warn!("CompressionEngine operation lock poisoned; continuing");
                poisoned.into_inner()
            }
        }
    }

    fn is_recoverable_file_error(error: &CompressionError) -> bool {
        matches!(
            error,
            CompressionError::LockedFile { .. } | CompressionError::PermissionDenied { .. }
        )
    }

    pub fn compress_folder(&self, folder: &Path) -> Result<CompressionStats, CompressionError> {
        self.validate_path(folder)?;
        let _operation_guard = self.operation_guard();
        self.reset_counters();
        self.compress_impl(folder)
    }

    /// Starts compression on a background worker and returns:
    /// - a live progress stream receiver
    /// - a final operation result receiver
    ///
    /// Dropping the progress receiver does not cancel the operation. Cancellation
    /// remains explicit via `CancellationToken`.
    pub fn compress_folder_with_progress(
        &self,
        folder: &Path,
        game_name: String,
    ) -> Result<CompressionProgressHandle, CompressionError> {
        self.validate_path(folder)?;
        let folder = folder.to_path_buf();
        let engine = self.clone();

        let (progress_ready_tx, progress_ready_rx) = bounded(1);
        let (result_tx, result_rx) = bounded(1);

        std::thread::spawn(move || {
            let _operation_guard = engine.operation_guard();
            engine.reset_counters();

            let counters = engine.engine_counters();
            let (mut reporter, progress_rx) = ProgressReporter::new(counters, game_name);
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
        let _operation_guard = self.operation_guard();
        self.reset_counters();
        self.decompress_impl(folder)
    }

    pub fn get_compression_ratio(folder: &Path) -> Result<f64, CompressionError> {
        if !folder.exists() {
            return Err(CompressionError::PathNotFound(folder.to_path_buf()));
        }
        Self::ratio_impl(folder)
    }

    fn validate_path(&self, path: &Path) -> Result<(), CompressionError> {
        if !path.exists() {
            return Err(CompressionError::PathNotFound(path.to_path_buf()));
        }
        if !path.is_dir() {
            return Err(CompressionError::NotADirectory(path.to_path_buf()));
        }
        Ok(())
    }

    fn file_iter(folder: &Path) -> impl Iterator<Item = walkdir::DirEntry> + '_ {
        WalkDir::new(folder)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file())
    }

    #[cfg(windows)]
    fn compress_impl(&self, folder: &Path) -> Result<CompressionStats, CompressionError> {
        let start = std::time::Instant::now();
        // Single pass: discover + process files while incrementing files_total.
        let disk_full = Arc::new(AtomicBool::new(false));
        let skipped = Arc::new(AtomicU64::new(0));
        let algorithm = self.algorithm;

        let result = Self::file_iter(folder).par_bridge().try_for_each(|entry| {
            self.files_total.fetch_add(1, Ordering::Relaxed);
            let path = entry.into_path();
            if self.cancel_token.is_cancelled() {
                return Err(CompressionError::Cancelled);
            }
            if disk_full.load(Ordering::Relaxed) {
                return Err(CompressionError::DiskFull);
            }

            let file_size = match std::fs::metadata(&path) {
                Ok(m) => m.len(),
                Err(_) => {
                    skipped.fetch_add(1, Ordering::Relaxed);
                    self.files_processed.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
            };

            if file_size < MIN_COMPRESSIBLE_SIZE {
                skipped.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }

            match wof::wof_compress_file(&path, algorithm) {
                Ok(CompressFileResult::Compressed) => {
                    self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                    let phys = wof::get_physical_size(&path).unwrap_or(file_size);
                    self.bytes_compressed.fetch_add(phys, Ordering::Relaxed);
                }
                Ok(CompressFileResult::NotBeneficial) => {
                    self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                    self.bytes_compressed
                        .fetch_add(file_size, Ordering::Relaxed);
                    skipped.fetch_add(1, Ordering::Relaxed);
                }
                Err(CompressionError::DiskFull) => {
                    disk_full.store(true, Ordering::Relaxed);
                    return Err(CompressionError::DiskFull);
                }
                Err(e) if Self::is_recoverable_file_error(&e) => {
                    log::debug!("Skipping {}: locked or permission denied", path.display());
                    self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                    self.bytes_compressed
                        .fetch_add(file_size, Ordering::Relaxed);
                    skipped.fetch_add(1, Ordering::Relaxed);
                }
                Err(e) => {
                    log::warn!("Aborting compression for {}: {e}", path.display());
                    return Err(e);
                }
            }

            self.files_processed.fetch_add(1, Ordering::Relaxed);
            Ok(())
        });

        result?;

        Ok(CompressionStats {
            original_bytes: self.bytes_original.load(Ordering::Relaxed),
            compressed_bytes: self.bytes_compressed.load(Ordering::Relaxed),
            files_processed: self.files_processed.load(Ordering::Relaxed),
            files_skipped: skipped.load(Ordering::Relaxed),
            duration_ms: start.elapsed().as_millis() as u64,
        })
    }

    #[cfg(not(windows))]
    fn compress_impl(&self, _folder: &Path) -> Result<CompressionStats, CompressionError> {
        Err(CompressionError::WofApiError {
            message: "WOF compression requires Windows".into(),
        })
    }

    #[cfg(windows)]
    fn decompress_impl(&self, folder: &Path) -> Result<(), CompressionError> {
        let result = Self::file_iter(folder).par_bridge().try_for_each(|entry| {
            self.files_total.fetch_add(1, Ordering::Relaxed);
            let path = entry.into_path();
            if self.cancel_token.is_cancelled() {
                return Err(CompressionError::Cancelled);
            }

            match wof::wof_decompress_file(&path) {
                Ok(()) => {}
                Err(e) if Self::is_recoverable_file_error(&e) => {
                    log::debug!(
                        "Skipping decompression of {}: locked or denied",
                        path.display()
                    );
                }
                Err(CompressionError::DiskFull) => {
                    return Err(CompressionError::DiskFull);
                }
                Err(e) => {
                    log::warn!("Aborting decompression for {}: {e}", path.display());
                    return Err(e);
                }
            }

            self.files_processed.fetch_add(1, Ordering::Relaxed);
            Ok(())
        });

        result?;

        Ok(())
    }

    #[cfg(not(windows))]
    fn decompress_impl(&self, _folder: &Path) -> Result<(), CompressionError> {
        Err(CompressionError::WofApiError {
            message: "WOF decompression requires Windows".into(),
        })
    }

    #[cfg(windows)]
    fn ratio_impl(folder: &Path) -> Result<f64, CompressionError> {
        let mut logical_total: u64 = 0;
        let mut physical_total: u64 = 0;

        for entry in Self::file_iter(folder) {
            let path = entry.path();
            if let Ok(metadata) = std::fs::metadata(path) {
                let logical = metadata.len();
                let physical = wof::get_physical_size(path).unwrap_or(logical);
                logical_total += logical;
                physical_total += physical;
            }
        }

        if logical_total == 0 {
            return Ok(1.0);
        }

        Ok(physical_total as f64 / logical_total as f64)
    }

    #[cfg(not(windows))]
    fn ratio_impl(_folder: &Path) -> Result<f64, CompressionError> {
        Err(CompressionError::WofApiError {
            message: "WOF ratio query requires Windows".into(),
        })
    }
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn reset_counters_zeroes_all() {
        let engine = CompressionEngine::new(CompressionAlgorithm::default());
        engine.files_processed.store(42, Ordering::Relaxed);
        engine.files_total.store(100, Ordering::Relaxed);
        engine.bytes_original.store(999, Ordering::Relaxed);
        engine.bytes_compressed.store(500, Ordering::Relaxed);

        engine.reset_counters();
        let (fp, ft, bo, bc) = engine.progress();
        assert_eq!((fp, ft, bo, bc), (0, 0, 0, 0));
    }

    #[test]
    fn operation_guard_prevents_parallel_entry() {
        let engine = CompressionEngine::new(CompressionAlgorithm::default());
        let _guard = engine.operation_guard();
        assert!(
            engine.operation_lock.try_lock().is_err(),
            "operation lock should block concurrent operation entry"
        );
    }

    #[test]
    fn recoverable_error_classification_is_strict() {
        let locked = CompressionError::LockedFile {
            path: Path::new("C:\\test").to_path_buf(),
        };
        let denied = CompressionError::PermissionDenied {
            path: Path::new("C:\\test").to_path_buf(),
            source: std::io::Error::from(std::io::ErrorKind::PermissionDenied),
        };
        let wof = CompressionError::WofApiError {
            message: "unsupported".into(),
        };

        assert!(CompressionEngine::is_recoverable_file_error(&locked));
        assert!(CompressionEngine::is_recoverable_file_error(&denied));
        assert!(!CompressionEngine::is_recoverable_file_error(&wof));
    }
}
