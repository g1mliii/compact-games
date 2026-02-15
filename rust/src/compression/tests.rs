//! Integration tests for the compression engine.
//!
//! Windows-specific tests exercise real WOF compression on NTFS.
//! Cross-platform tests cover path validation, cancellation, and stats.

use std::fs;
use std::path::Path;
use std::time::{Duration, Instant};

use tempfile::TempDir;

use super::algorithm::CompressionAlgorithm;
use super::engine::{
    CancellationToken, CompressionEngine, CompressionProgressHandle, CompressionStats, SafetyConfig,
};
use super::error::CompressionError;
use crate::safety::process::ProcessChecker;

// ── Test helpers ─────────────────────────────────────────────────────

fn create_compressible_file(dir: &Path, name: &str, size: usize) -> std::path::PathBuf {
    let path = dir.join(name);
    fs::write(&path, vec![0u8; size]).unwrap();
    path
}

fn create_random_file(dir: &Path, name: &str, size: usize) -> std::path::PathBuf {
    let path = dir.join(name);
    let data: Vec<u8> = (0..size)
        .map(|i| (i.wrapping_mul(7).wrapping_add(13)) as u8)
        .collect();
    fs::write(&path, data).unwrap();
    path
}

fn create_nested_structure(dir: &Path) {
    // Create a nested directory tree with mixed content
    let sub1 = dir.join("subdir1");
    let sub2 = dir.join("subdir2");
    let nested = sub1.join("nested");
    fs::create_dir_all(&nested).unwrap();
    fs::create_dir_all(&sub2).unwrap();

    // Large compressible files
    create_compressible_file(&sub1, "big_zeros.dat", 1_048_576);
    create_compressible_file(&nested, "nested_zeros.dat", 524_288);
    // Small file (should be skipped, < 4096 bytes)
    create_compressible_file(&sub2, "tiny.dat", 100);
    // Incompressible file
    create_random_file(&sub2, "random.bin", 65_536);
    // Empty file (should be skipped)
    fs::write(dir.join("empty.txt"), b"").unwrap();
}

// ── Cross-platform unit tests ────────────────────────────────────────

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
fn progress_returns_four_counters() {
    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    let (fp, ft, bo, bc) = engine.progress();
    assert_eq!((fp, ft, bo, bc), (0, 0, 0, 0));
}

// ── Property-based tests for CompressionStats ────────────────────────

#[cfg(test)]
mod stats_properties {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// Property: savings_ratio is in valid range [0.0, 1.0] when compression is beneficial.
        /// Can be negative when compressed > original (incompressible data).
        #[test]
        fn savings_ratio_range_when_beneficial(
            original in 1u64..=u64::MAX,
            compressed in 0u64..=u64::MAX,
        ) {
            // Only test when compressed <= original (beneficial compression)
            prop_assume!(compressed <= original);

            let stats = CompressionStats {
                original_bytes: original,
                compressed_bytes: compressed,
                files_processed: 1,
                files_skipped: 0,
                duration_ms: 100,
            };

            let ratio = stats.savings_ratio();
            prop_assert!((0.0..=1.0).contains(&ratio),
                "savings_ratio {ratio} not in [0.0, 1.0] for original={original}, compressed={compressed}");
        }

        /// Property: bytes_saved() must equal original_bytes - compressed_bytes (with saturation).
        #[test]
        fn bytes_saved_consistency(
            original in 0u64..=u64::MAX,
            compressed in 0u64..=u64::MAX,
        ) {
            let stats = CompressionStats {
                original_bytes: original,
                compressed_bytes: compressed,
                files_processed: 1,
                files_skipped: 0,
                duration_ms: 100,
            };

            let expected = original.saturating_sub(compressed);
            prop_assert_eq!(stats.bytes_saved(), expected,
                "bytes_saved() inconsistent: got {}, expected {}", stats.bytes_saved(), expected);
        }

        /// Property: savings_ratio matches mathematical formula: (original - compressed) / original.
        #[test]
        fn savings_ratio_mathematical_relationship(
            original in 1u64..=u64::MAX, // Avoid division by zero
            compressed in 0u64..=u64::MAX,
        ) {
            prop_assume!(compressed <= original); // Beneficial compression only

            let stats = CompressionStats {
                original_bytes: original,
                compressed_bytes: compressed,
                files_processed: 1,
                files_skipped: 0,
                duration_ms: 100,
            };

            let expected_ratio = 1.0 - (compressed as f64 / original as f64);
            let actual_ratio = stats.savings_ratio();

            // Allow small floating point error
            let diff = (actual_ratio - expected_ratio).abs();
            prop_assert!(diff < 1e-10,
                "savings_ratio {actual_ratio} != expected {expected_ratio} (diff={diff})");
        }

        /// Property: savings_ratio is idempotent (calling multiple times gives same result).
        #[test]
        fn savings_ratio_idempotent(
            original in 0u64..=u64::MAX,
            compressed in 0u64..=u64::MAX,
        ) {
            let stats = CompressionStats {
                original_bytes: original,
                compressed_bytes: compressed,
                files_processed: 1,
                files_skipped: 0,
                duration_ms: 100,
            };

            let first_call = stats.savings_ratio();
            let second_call = stats.savings_ratio();
            let third_call = stats.savings_ratio();

            prop_assert_eq!(first_call, second_call, "savings_ratio not idempotent");
            prop_assert_eq!(second_call, third_call, "savings_ratio not idempotent");
        }

        /// Property: When original_bytes is zero, savings_ratio returns 0.0 (no savings).
        #[test]
        fn savings_ratio_zero_original(compressed in 0u64..=u64::MAX) {
            let stats = CompressionStats {
                original_bytes: 0,
                compressed_bytes: compressed,
                files_processed: 0,
                files_skipped: 0,
                duration_ms: 0,
            };

            prop_assert_eq!(stats.savings_ratio(), 0.0,
                "savings_ratio should be 0.0 when original_bytes is 0");
        }

        /// Property: Perfect compression (compressed = 0) gives 100% savings (ratio = 1.0).
        #[test]
        fn perfect_compression(original in 1u64..=u64::MAX) {
            let stats = CompressionStats {
                original_bytes: original,
                compressed_bytes: 0,
                files_processed: 1,
                files_skipped: 0,
                duration_ms: 100,
            };

            let ratio = stats.savings_ratio();
            prop_assert!((ratio - 1.0).abs() < 1e-10,
                "perfect compression should give ratio ~1.0, got {ratio}");
        }

        /// Property: No compression (compressed = original) gives 0% savings (ratio = 0.0).
        #[test]
        fn no_compression(size in 1u64..=u64::MAX) {
            let stats = CompressionStats {
                original_bytes: size,
                compressed_bytes: size,
                files_processed: 1,
                files_skipped: 0,
                duration_ms: 100,
            };

            let ratio = stats.savings_ratio();
            prop_assert!(ratio.abs() < 1e-10,
                "no compression should give ratio ~0.0, got {ratio}");
        }

        /// Property: bytes_saved is never greater than original_bytes.
        #[test]
        fn bytes_saved_bounded(
            original in 0u64..=u64::MAX,
            compressed in 0u64..=u64::MAX,
        ) {
            let stats = CompressionStats {
                original_bytes: original,
                compressed_bytes: compressed,
                files_processed: 1,
                files_skipped: 0,
                duration_ms: 100,
            };

            prop_assert!(stats.bytes_saved() <= original,
                "bytes_saved {} should not exceed original {}", stats.bytes_saved(), original);
        }
    }
}

// ── Cross-platform path validation tests ─────────────────────────────

#[test]
fn nonexistent_path_returns_error() {
    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    let result = engine.compress_folder(Path::new(r"C:\__nonexistent_pressplay_test__"));
    assert!(matches!(result, Err(CompressionError::PathNotFound(_))));
}

#[test]
fn file_path_returns_not_a_directory() {
    let dir = TempDir::new().unwrap();
    let file_path = create_compressible_file(dir.path(), "not_a_dir.txt", 100);
    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    let result = engine.compress_folder(&file_path);
    assert!(matches!(result, Err(CompressionError::NotADirectory(_))));
}

#[test]
fn decompress_nonexistent_path_returns_error() {
    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    let result = engine.decompress_folder(Path::new(r"C:\__nonexistent_pressplay_test__"));
    assert!(matches!(result, Err(CompressionError::PathNotFound(_))));
}

#[test]
fn ratio_nonexistent_path_returns_error() {
    let result =
        CompressionEngine::get_compression_ratio(Path::new(r"C:\__nonexistent_pressplay_test__"));
    assert!(matches!(result, Err(CompressionError::PathNotFound(_))));
}

// ── Windows-specific WOF tests ───────────────────────────────────────

#[cfg(windows)]
mod wof_tests;

// ── Safety integration tests ─────────────────────────────────────────

mod safety_tests;
