//! Windows-specific compress/decompress/ratio implementations using WOF API.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use rayon::iter::ParallelBridge;
use rayon::prelude::*;

use super::super::error::CompressionError;
use super::super::wof::{self, CompressFileResult};
use super::{CompressionEngine, CompressionStats, MIN_COMPRESSIBLE_SIZE};

impl CompressionEngine {
    pub(super) fn compress_impl(
        &self,
        folder: &Path,
    ) -> Result<CompressionStats, CompressionError> {
        let files: Vec<PathBuf> = Self::file_iter(folder).map(|e| e.into_path()).collect();
        self.compress_impl_from_manifest(files)
    }

    pub(super) fn compress_impl_from_manifest(
        &self,
        files: Vec<PathBuf>,
    ) -> Result<CompressionStats, CompressionError> {
        let start = std::time::Instant::now();
        let disk_full = Arc::new(AtomicBool::new(false));
        let skipped = Arc::new(AtomicU64::new(0));
        let algorithm = self.algorithm;

        self.files_total
            .store(files.len() as u64, Ordering::Relaxed);

        let result = files.par_iter().try_for_each(|path| {
            if self.cancel_token.is_cancelled() {
                return Err(CompressionError::Cancelled);
            }
            if disk_full.load(Ordering::Relaxed) {
                return Err(CompressionError::DiskFull);
            }

            let file_size = match std::fs::metadata(path) {
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

            // Skip already-compressed files
            let physical = wof::get_physical_size(path).unwrap_or(file_size);
            if physical < file_size {
                self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                self.bytes_compressed.fetch_add(physical, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }

            match wof::wof_compress_file(path, algorithm) {
                Ok(CompressFileResult::Compressed) => {
                    self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                    let phys = wof::get_physical_size(path).unwrap_or(file_size);
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

    pub(super) fn decompress_impl(&self, folder: &Path) -> Result<(), CompressionError> {
        self.files_total.store(0, Ordering::Relaxed);
        let decompression_candidates = Arc::new(AtomicU64::new(0));
        let likely_uncompressed = Arc::new(AtomicU64::new(0));

        let result = Self::file_iter(folder).par_bridge().try_for_each(|entry| {
            if self.cancel_token.is_cancelled() {
                return Err(CompressionError::Cancelled);
            }
            self.files_total.fetch_add(1, Ordering::Relaxed);

            let path = entry.path();
            let file_size = match entry.metadata() {
                Ok(m) => m.len(),
                Err(_) => {
                    self.files_processed.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
            };
            if file_size < MIN_COMPRESSIBLE_SIZE {
                likely_uncompressed.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }

            let physical_size = wof::get_physical_size(path).unwrap_or(file_size);
            if physical_size >= file_size {
                likely_uncompressed.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }
            decompression_candidates.fetch_add(1, Ordering::Relaxed);

            match wof::wof_decompress_file(path) {
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
        log::warn!(
            "[decompression][summary] path=\"{}\" files={} candidates={} skipped_likely_uncompressed={}",
            folder.display(),
            self.files_total.load(Ordering::Relaxed),
            decompression_candidates.load(Ordering::Relaxed),
            likely_uncompressed.load(Ordering::Relaxed),
        );

        Ok(())
    }

    pub(super) fn ratio_impl(folder: &Path) -> Result<f64, CompressionError> {
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
}
