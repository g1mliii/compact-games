//! Windows-specific compress/decompress/ratio implementations using WOF API.

use std::fs::OpenOptions;
use std::os::windows::fs::OpenOptionsExt;
use std::os::windows::io::AsRawHandle;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use rayon::iter::ParallelBridge;
use rayon::prelude::*;
use windows::Win32::Foundation::HANDLE;
use windows::Win32::Storage::FileSystem::{
    GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION, FILE_SHARE_DELETE, FILE_SHARE_READ,
    FILE_SHARE_WRITE,
};

use super::super::error::CompressionError;
use super::super::wof::{self, CompressFileResult};
use super::{CompressionEngine, CompressionStats, ManifestFile, MIN_COMPRESSIBLE_SIZE};

impl CompressionEngine {
    pub(super) fn compress_impl(
        &self,
        folder: &Path,
    ) -> Result<CompressionStats, CompressionError> {
        let files: Vec<ManifestFile> = Self::file_iter(folder)?
            .map(|entry| {
                let logical_size_hint = entry.metadata().ok().map(|m| m.len());
                ManifestFile {
                    path: entry.into_path(),
                    logical_size_hint,
                }
            })
            .collect();
        self.compress_impl_from_manifest(files)
    }

    pub(super) fn compress_impl_from_manifest(
        &self,
        files: Vec<ManifestFile>,
    ) -> Result<CompressionStats, CompressionError> {
        let start = std::time::Instant::now();
        let disk_full = Arc::new(AtomicBool::new(false));
        let skipped = Arc::new(AtomicU64::new(0));
        let algorithm = self.algorithm;

        self.files_total
            .store(files.len() as u64, Ordering::Relaxed);

        let result = files.par_iter().try_for_each(|manifest_file| {
            let path = manifest_file.path.as_path();
            if self.cancel_token.is_cancelled() {
                return Err(CompressionError::Cancelled);
            }
            if disk_full.load(Ordering::Relaxed) {
                return Err(CompressionError::DiskFull);
            }

            let file_size = manifest_file
                .logical_size_hint
                .unwrap_or_else(|| std::fs::metadata(path).map(|m| m.len()).unwrap_or_default());
            if file_size == 0 {
                skipped.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }

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

            if has_multiple_links(path) {
                log::warn!(
                    "Skipping multi-linked file during compression: {}",
                    path.display()
                );
                self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                self.bytes_compressed
                    .fetch_add(file_size, Ordering::Relaxed);
                skipped.fetch_add(1, Ordering::Relaxed);
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

        let result = Self::file_iter(folder)?.par_bridge().try_for_each(|entry| {
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

            if has_multiple_links(path) {
                log::warn!(
                    "Skipping multi-linked file during decompression: {}",
                    path.display()
                );
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
        log::info!(
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

        for entry in Self::file_iter(folder)? {
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

fn has_multiple_links(path: &Path) -> bool {
    link_count(path).is_some_and(|count| count > 1)
}

fn link_count(path: &Path) -> Option<u64> {
    let file = OpenOptions::new()
        .read(true)
        .share_mode((FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE).0)
        .open(path)
        .ok()?;
    let mut info = BY_HANDLE_FILE_INFORMATION::default();
    let ok = unsafe {
        // Windows API required to get stable hard-link count for the file.
        GetFileInformationByHandle(HANDLE(file.as_raw_handle()), &mut info).is_ok()
    };
    if !ok {
        return None;
    }
    Some(info.nNumberOfLinks as u64)
}
