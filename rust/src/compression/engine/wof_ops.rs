//! Windows-specific compress/decompress/ratio implementations using WOF API.

use std::fs::OpenOptions;
use std::os::windows::fs::OpenOptionsExt;
use std::os::windows::io::AsRawHandle;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use rayon::iter::ParallelBridge;
use rayon::prelude::*;
use std::sync::Mutex;
use windows::Win32::Foundation::HANDLE;

/// Single cached thread pool.
///
/// Keeping only one pool avoids unbounded resident worker threads when users
/// change thread overrides frequently (for example 2 -> 4 -> 8 -> ...), while
/// still reusing the most recently used pool for the common steady-state case.
type CachedPool = Option<(usize, Arc<rayon::ThreadPool>)>;

static THREAD_POOL_CACHE: std::sync::LazyLock<Mutex<CachedPool>> =
    std::sync::LazyLock::new(|| Mutex::new(None));

fn get_or_create_thread_pool(
    parallelism: usize,
) -> Result<Arc<rayon::ThreadPool>, CompressionError> {
    let mut cache = THREAD_POOL_CACHE.lock().unwrap_or_else(|e| {
        log::warn!("Thread pool cache lock poisoned; recovering");
        e.into_inner()
    });
    if let Some((cached_parallelism, pool)) = cache.as_ref() {
        if *cached_parallelism == parallelism {
            return Ok(Arc::clone(pool));
        }
    }
    let pool = Arc::new(
        rayon::ThreadPoolBuilder::new()
            .num_threads(parallelism)
            .build()
            .map_err(|e| CompressionError::Io {
                source: std::io::Error::other(e.to_string()),
            })?,
    );
    *cache = Some((parallelism, Arc::clone(&pool)));
    Ok(pool)
}
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

        // Reset counters before starting to avoid stale accumulation from
        // a previous run when the engine instance is reused.
        self.reset_counters();
        self.files_total
            .store(files.len() as u64, Ordering::Relaxed);

        let compress_body = |manifest_file: &ManifestFile| -> Result<(), CompressionError> {
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
        };

        let result = if let Some(policy) = &self.thread_policy {
            let pool = get_or_create_thread_pool(policy.io_parallelism)?;
            log::info!(
                "[compression][thread_policy] io_parallelism={} background={}",
                policy.io_parallelism,
                policy.is_background,
            );
            pool.install(|| files.par_iter().try_for_each(compress_body))
        } else {
            files.par_iter().try_for_each(compress_body)
        };

        result?;

        let duration = start.elapsed();
        let original = self.bytes_original.load(Ordering::Relaxed);
        let duration_ms = duration.as_millis() as u64;
        if duration_ms > 0 {
            let throughput_mbps =
                (original as f64 / (1024.0 * 1024.0)) / (duration_ms as f64 / 1000.0);
            log::info!(
                "[compression][throughput] {:.1} MB/s ({} bytes in {}ms)",
                throughput_mbps,
                original,
                duration_ms,
            );
        }

        Ok(CompressionStats {
            original_bytes: self.bytes_original.load(Ordering::Relaxed),
            compressed_bytes: self.bytes_compressed.load(Ordering::Relaxed),
            files_processed: self.files_processed.load(Ordering::Relaxed),
            files_skipped: skipped.load(Ordering::Relaxed),
            duration_ms: start.elapsed().as_millis() as u64,
        })
    }

    pub(super) fn decompress_impl(&self, folder: &Path) -> Result<(), CompressionError> {
        let files: Vec<ManifestFile> = Self::file_iter(folder)?
            .map(|entry| {
                let logical_size_hint = entry.metadata().ok().map(|m| m.len());
                ManifestFile {
                    path: entry.into_path(),
                    logical_size_hint,
                }
            })
            .collect();
        self.decompress_impl_from_manifest(folder, files)
    }

    pub(super) fn decompress_impl_from_manifest(
        &self,
        folder: &Path,
        files: Vec<ManifestFile>,
    ) -> Result<(), CompressionError> {
        self.reset_counters();
        let decompression_candidates = Arc::new(AtomicU64::new(0));
        let likely_uncompressed = Arc::new(AtomicU64::new(0));
        self.files_total
            .store(files.len() as u64, Ordering::Relaxed);

        let decompress_body = |manifest_file: &ManifestFile| -> Result<(), CompressionError> {
            if self.cancel_token.is_cancelled() {
                return Err(CompressionError::Cancelled);
            }

            let path = manifest_file.path.as_path();
            let file_size = match manifest_file.logical_size_hint {
                Some(size) => size,
                None => match std::fs::metadata(path) {
                    Ok(metadata) => metadata.len(),
                    Err(_) => {
                        self.files_processed.fetch_add(1, Ordering::Relaxed);
                        return Ok(());
                    }
                },
            };
            if file_size == 0 {
                likely_uncompressed.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }
            if file_size < MIN_COMPRESSIBLE_SIZE {
                self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                self.bytes_compressed
                    .fetch_add(file_size, Ordering::Relaxed);
                likely_uncompressed.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }

            let physical_size = wof::get_physical_size(path).unwrap_or(file_size);
            if physical_size >= file_size {
                self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                self.bytes_compressed
                    .fetch_add(file_size, Ordering::Relaxed);
                likely_uncompressed.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }

            if has_multiple_links(path) {
                self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                self.bytes_compressed
                    .fetch_add(file_size, Ordering::Relaxed);
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
                Ok(()) => {
                    self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                    self.bytes_compressed
                        .fetch_add(physical_size, Ordering::Relaxed);
                }
                Err(e) if Self::is_recoverable_file_error(&e) => {
                    self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                    self.bytes_compressed
                        .fetch_add(file_size, Ordering::Relaxed);
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
        };

        let result = if let Some(policy) = &self.thread_policy {
            let pool = get_or_create_thread_pool(policy.io_parallelism)?;
            pool.install(|| files.par_iter().try_for_each(decompress_body))
        } else {
            files.par_iter().try_for_each(decompress_body)
        };

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
        let logical_total = AtomicU64::new(0);
        let physical_total = AtomicU64::new(0);

        Self::file_iter(folder)?.par_bridge().for_each(|entry| {
            let path = entry.path();
            if let Ok(metadata) = std::fs::metadata(path) {
                let logical = metadata.len();
                let physical = wof::get_physical_size(path).unwrap_or(logical);
                logical_total.fetch_add(logical, Ordering::Relaxed);
                physical_total.fetch_add(physical, Ordering::Relaxed);
            }
        });

        let logical = logical_total.load(Ordering::Relaxed);
        if logical == 0 {
            return Ok(1.0);
        }

        Ok(physical_total.load(Ordering::Relaxed) as f64 / logical as f64)
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
