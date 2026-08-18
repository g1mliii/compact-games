//! Windows-specific compress/decompress/ratio implementations using WOF API.

use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use rayon::iter::ParallelBridge;
use rayon::prelude::*;

fn build_thread_pool(
    parallelism: usize,
    low_io_priority: bool,
) -> Result<rayon::ThreadPool, CompressionError> {
    let mut builder = rayon::ThreadPoolBuilder::new().num_threads(parallelism);
    if low_io_priority {
        // Background mode is per-thread, so it has to be entered on each worker
        // rather than once here, and left again before the thread is reused.
        builder = builder
            .start_handler(|_| io_priority::enter_background_io())
            .exit_handler(|_| io_priority::leave_background_io());
    }
    builder.build().map_err(|e| CompressionError::Io {
        source: std::io::Error::other(e.to_string()),
    })
}

use super::super::error::CompressionError;
use super::super::io_priority;
use super::super::thread_policy::ThreadPolicy;
use super::super::wof::{self, CompressFileResult};
use super::{CompressionEngine, CompressionStats, ManifestFile, MIN_COMPRESSIBLE_SIZE};

/// Run a per-file operation through the same policy-controlled dispatcher used
/// by both compression and decompression.
///
/// Keeping this in one place makes the concurrency contract testable without
/// requiring a timing-sensitive WOF call in the unit test itself.
fn try_for_each_file<T, F>(
    files: &[T],
    policy: Option<&ThreadPolicy>,
    operation: F,
) -> Result<(), CompressionError>
where
    T: Sync,
    F: Fn(&T) -> Result<(), CompressionError> + Sync + Send,
{
    if let Some(policy) = policy {
        // Keep compression workers scoped to the operation so they terminate
        // when the job finishes instead of retaining stacks while idle in tray.
        let pool = build_thread_pool(policy.io_parallelism, policy.low_io_priority)?;
        pool.install(|| files.par_iter().try_for_each(&operation))
    } else {
        files.par_iter().try_for_each(operation)
    }
}

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
        self.compress_impl_from_manifest(folder, files)
    }

    pub(super) fn compress_impl_from_manifest(
        &self,
        folder: &Path,
        files: Vec<ManifestFile>,
    ) -> Result<CompressionStats, CompressionError> {
        let start = std::time::Instant::now();
        let disk_full = Arc::new(AtomicBool::new(false));
        let skipped = Arc::new(AtomicU64::new(0));
        let algorithm = self.algorithm;
        let canonical_root =
            std::fs::canonicalize(folder).map_err(|source| CompressionError::Io { source })?;

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

            let file = match wof::open_verified_file(path, &canonical_root) {
                Ok(file) => file,
                Err(error) if Self::is_recoverable_file_error(&error) => {
                    skipped.fetch_add(1, Ordering::Relaxed);
                    self.files_processed.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
                Err(error) => {
                    log::warn!(
                        "Skipping unsafe compression path {}: {error}",
                        path.display()
                    );
                    skipped.fetch_add(1, Ordering::Relaxed);
                    self.files_processed.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
            };

            if wof::link_count(&file).is_some_and(|count| count > 1) {
                log::warn!(
                    "Skipping multi-linked file during compression: {}",
                    path.display()
                );
                skipped.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }

            let file_size = file
                .metadata()
                .map(|metadata| metadata.len())
                .unwrap_or_default();
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

            // WOF does not overlay a second backing on an already-backed file,
            // so recompression with a different algorithm must clear the old
            // backing before applying the new one.
            match wof::wof_get_compression_open_file(&file, path) {
                Ok(Some(current_algo)) if current_algo == algorithm => {
                    let physical = wof::get_physical_size(path).unwrap_or(file_size);
                    self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                    self.bytes_compressed.fetch_add(physical, Ordering::Relaxed);
                    self.files_processed.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
                Ok(Some(_)) => {
                    if let Err(e) = wof::wof_decompress_open_file(&file, path) {
                        log::warn!(
                            "Skipping {} during re-apply: could not clear WOF backing: {e}",
                            path.display()
                        );
                        self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                        self.bytes_compressed
                            .fetch_add(file_size, Ordering::Relaxed);
                        skipped.fetch_add(1, Ordering::Relaxed);
                        self.files_processed.fetch_add(1, Ordering::Relaxed);
                        return Ok(());
                    }
                }
                _ => {
                    // Not WOF-backed (or query failed). Legacy heuristic: if
                    // physical < logical the file is NTFS LZNT1 or sparse, so
                    // leave it alone rather than layering WOF on top.
                    let physical = wof::get_physical_size(path).unwrap_or(file_size);
                    if physical < file_size {
                        self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                        self.bytes_compressed.fetch_add(physical, Ordering::Relaxed);
                        self.files_processed.fetch_add(1, Ordering::Relaxed);
                        return Ok(());
                    }
                }
            }

            match wof::wof_compress_open_file(&file, path, algorithm) {
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

        if let Some(policy) = &self.thread_policy {
            log::info!(
                "[compression][thread_policy] io_parallelism={} background={} low_io_priority={}",
                policy.io_parallelism,
                policy.is_background,
                policy.low_io_priority,
            );
        }

        try_for_each_file(&files, self.thread_policy.as_ref(), compress_body)?;

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
        let canonical_root =
            std::fs::canonicalize(folder).map_err(|source| CompressionError::Io { source })?;
        self.files_total
            .store(files.len() as u64, Ordering::Relaxed);

        let decompress_body = |manifest_file: &ManifestFile| -> Result<(), CompressionError> {
            if self.cancel_token.is_cancelled() {
                return Err(CompressionError::Cancelled);
            }

            let path = manifest_file.path.as_path();
            // Measured before the file is opened. Opening a WOF-backed file for
            // write releases its backing, so a physical size read after
            // open_verified_file always equals the logical size: every file
            // then looks uncompressed, the explicit decompress call is skipped,
            // and the restored total reported to the UI is always zero.
            let physical_before_open = wof::get_physical_size(path).ok();
            let file = match wof::open_verified_file(path, &canonical_root) {
                Ok(file) => file,
                Err(error) if Self::is_recoverable_file_error(&error) => {
                    self.files_processed.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
                Err(error) => {
                    log::warn!(
                        "Skipping unsafe decompression path {}: {error}",
                        path.display()
                    );
                    likely_uncompressed.fetch_add(1, Ordering::Relaxed);
                    self.files_processed.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
            };
            let file_size = match file.metadata() {
                Ok(metadata) => metadata.len(),
                Err(_) => {
                    self.files_processed.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
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

            let physical_size = physical_before_open.unwrap_or(file_size);
            if physical_size >= file_size {
                self.bytes_original.fetch_add(file_size, Ordering::Relaxed);
                self.bytes_compressed
                    .fetch_add(file_size, Ordering::Relaxed);
                likely_uncompressed.fetch_add(1, Ordering::Relaxed);
                self.files_processed.fetch_add(1, Ordering::Relaxed);
                return Ok(());
            }

            if wof::link_count(&file).is_some_and(|count| count > 1) {
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

            match wof::wof_decompress_open_file(&file, path) {
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

        if let Some(policy) = &self.thread_policy {
            log::info!(
                "[decompression][thread_policy] io_parallelism={} background={} low_io_priority={}",
                policy.io_parallelism,
                policy.is_background,
                policy.low_io_priority,
            );
        }

        try_for_each_file(&files, self.thread_policy.as_ref(), decompress_body)?;
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

#[cfg(test)]
mod tests {
    use std::collections::HashSet;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};
    use std::thread;
    use std::time::Duration;

    use super::*;

    fn observe_dispatch(parallelism: usize) -> (usize, usize) {
        let files = vec![(); 32];
        let active = Arc::new(AtomicUsize::new(0));
        let peak_active = Arc::new(AtomicUsize::new(0));
        let worker_threads = Arc::new(Mutex::new(HashSet::new()));
        let policy = ThreadPolicy {
            io_parallelism: parallelism,
            is_background: false,
            low_io_priority: false,
        };

        try_for_each_file(&files, Some(&policy), |_| {
            let current = active.fetch_add(1, Ordering::SeqCst) + 1;
            peak_active.fetch_max(current, Ordering::SeqCst);
            worker_threads
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .insert(thread::current().id());

            // Sleeping keeps several dispatched operations in flight at once,
            // making overlap deterministic without depending on CPU speed.
            thread::sleep(Duration::from_millis(15));
            active.fetch_sub(1, Ordering::SeqCst);
            Ok(())
        })
        .expect("dispatch should complete");

        let unique_workers = worker_threads
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .len();
        (peak_active.load(Ordering::SeqCst), unique_workers)
    }

    #[test]
    fn file_dispatch_uses_multiple_workers_when_policy_allows_it() {
        let (peak_active, unique_workers) = observe_dispatch(4);

        assert!(
            peak_active > 1,
            "four-worker policy must overlap per-file operations"
        );
        assert!(
            peak_active <= 4,
            "dispatcher exceeded configured parallelism: {peak_active}"
        );
        assert!(
            unique_workers > 1 && unique_workers <= 4,
            "expected 2..=4 worker threads, observed {unique_workers}"
        );
    }

    #[test]
    fn file_dispatch_stays_serial_for_one_worker_policy() {
        let (peak_active, unique_workers) = observe_dispatch(1);

        assert_eq!(peak_active, 1);
        assert_eq!(unique_workers, 1);
    }
}
