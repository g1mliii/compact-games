use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use super::algorithm::CompressionAlgorithm;
use super::error::CompressionError;

/// Statistics returned after a compression operation completes.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressionStats {
    pub original_bytes: u64,
    pub compressed_bytes: u64,
    pub files_processed: u64,
    pub files_skipped: u64,
    pub duration_ms: u64,
}

impl CompressionStats {
    /// Space saved as a ratio (0.0 = no savings, 1.0 = 100% savings).
    pub fn savings_ratio(&self) -> f64 {
        if self.original_bytes == 0 {
            return 0.0;
        }
        1.0 - (self.compressed_bytes as f64 / self.original_bytes as f64)
    }

    /// Bytes saved by compression.
    pub fn bytes_saved(&self) -> u64 {
        self.original_bytes.saturating_sub(self.compressed_bytes)
    }
}

/// Shared cancellation token for cooperative cancellation.
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

/// Core compression engine.
///
/// Uses the Windows Overlay Filter (WOF) API to apply transparent
/// file-system-level compression. Files remain fully accessible to
/// applications; decompression is handled by the OS on read.
pub struct CompressionEngine {
    algorithm: CompressionAlgorithm,
    cancel_token: CancellationToken,
    files_processed: Arc<AtomicU64>,
    bytes_original: Arc<AtomicU64>,
    bytes_compressed: Arc<AtomicU64>,
}

impl CompressionEngine {
    pub fn new(algorithm: CompressionAlgorithm) -> Self {
        Self {
            algorithm,
            cancel_token: CancellationToken::new(),
            files_processed: Arc::new(AtomicU64::new(0)),
            bytes_original: Arc::new(AtomicU64::new(0)),
            bytes_compressed: Arc::new(AtomicU64::new(0)),
        }
    }

    /// Returns a clone of the cancellation token for external cancellation.
    pub fn cancel_token(&self) -> CancellationToken {
        self.cancel_token.clone()
    }

    /// Returns current progress counters (files_processed, bytes_original, bytes_compressed).
    pub fn progress(&self) -> (u64, u64, u64) {
        (
            self.files_processed.load(Ordering::Relaxed),
            self.bytes_original.load(Ordering::Relaxed),
            self.bytes_compressed.load(Ordering::Relaxed),
        )
    }

    /// Compress all files in `folder` using the configured algorithm.
    ///
    /// Walks the directory tree, applying WOF compression to each regular file.
    /// Skips files that are already compressed or locked.
    pub fn compress_folder(&self, folder: &Path) -> Result<CompressionStats, CompressionError> {
        self.validate_path(folder)?;

        let start = std::time::Instant::now();

        // TODO: Phase 2 implementation
        // 1. Walk directory with walkdir
        // 2. For each file, call WofSetFileDataLocation via windows-rs FFI
        // 3. Track progress with atomic counters
        // 4. Check cancel_token between files
        // 5. Skip locked/inaccessible files gracefully
        log::info!(
            "compress_folder: {} with {:?} (not yet implemented)",
            folder.display(),
            self.algorithm
        );

        Ok(CompressionStats {
            original_bytes: 0,
            compressed_bytes: 0,
            files_processed: 0,
            files_skipped: 0,
            duration_ms: start.elapsed().as_millis() as u64,
        })
    }

    /// Decompress all WOF-compressed files in `folder`.
    pub fn decompress_folder(&self, folder: &Path) -> Result<(), CompressionError> {
        self.validate_path(folder)?;

        // TODO: Phase 2 implementation
        // 1. Walk directory
        // 2. For each file, call WofSetFileDataLocation with no-compression flag
        // 3. Track progress
        log::info!(
            "decompress_folder: {} (not yet implemented)",
            folder.display()
        );

        Ok(())
    }

    /// Check the current compression ratio of a folder.
    pub fn get_compression_ratio(folder: &Path) -> Result<f64, CompressionError> {
        if !folder.exists() {
            return Err(CompressionError::PathNotFound(folder.to_path_buf()));
        }

        // TODO: Phase 2 implementation
        // 1. Walk directory, sum logical and physical sizes
        // 2. Return ratio
        log::info!(
            "get_compression_ratio: {} (not yet implemented)",
            folder.display()
        );

        Ok(0.0)
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stats_savings_ratio_zero_when_empty() {
        let stats = CompressionStats {
            original_bytes: 0,
            compressed_bytes: 0,
            files_processed: 0,
            files_skipped: 0,
            duration_ms: 0,
        };
        assert_eq!(stats.savings_ratio(), 0.0);
    }

    #[test]
    fn stats_savings_ratio_calculated_correctly() {
        let stats = CompressionStats {
            original_bytes: 1000,
            compressed_bytes: 600,
            files_processed: 10,
            files_skipped: 0,
            duration_ms: 100,
        };
        assert!((stats.savings_ratio() - 0.4).abs() < f64::EPSILON);
        assert_eq!(stats.bytes_saved(), 400);
    }

    #[test]
    fn cancellation_token_works() {
        let token = CancellationToken::new();
        assert!(!token.is_cancelled());
        token.cancel();
        assert!(token.is_cancelled());
    }

    #[test]
    fn compress_nonexistent_path_errors() {
        let engine = CompressionEngine::new(CompressionAlgorithm::default());
        let result = engine.compress_folder(Path::new(r"C:\__nonexistent_pressplay_test__"));
        assert!(result.is_err());
    }
}
