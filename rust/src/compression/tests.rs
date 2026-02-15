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
    CancellationToken, CompressionEngine, CompressionProgressHandle, CompressionStats,
};
use super::error::CompressionError;

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
mod wof_tests {
    use super::*;
    use crate::compression::wof;
    use crossbeam_channel::TryRecvError;

    #[test]
    fn compress_empty_folder_returns_zero_stats() {
        let dir = TempDir::new().unwrap();
        let engine = CompressionEngine::new(CompressionAlgorithm::default());
        let stats = engine.compress_folder(dir.path()).unwrap();
        assert_eq!(stats.files_processed, 0);
        assert_eq!(stats.original_bytes, 0);
        assert_eq!(stats.compressed_bytes, 0);
        assert_eq!(stats.files_skipped, 0);
    }

    #[test]
    fn compress_reduces_or_maintains_size_xpress4k() {
        let dir = TempDir::new().unwrap();
        create_compressible_file(dir.path(), "zeros.dat", 1_048_576);

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        let stats = engine.compress_folder(dir.path()).unwrap();
        assert!(
            stats.compressed_bytes <= stats.original_bytes,
            "Xpress4K: compressed {} > original {}",
            stats.compressed_bytes,
            stats.original_bytes,
        );
    }

    #[test]
    fn compress_reduces_or_maintains_size_xpress8k() {
        let dir = TempDir::new().unwrap();
        create_compressible_file(dir.path(), "zeros.dat", 1_048_576);

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress8K);
        let stats = engine.compress_folder(dir.path()).unwrap();
        assert!(
            stats.compressed_bytes <= stats.original_bytes,
            "Xpress8K: compressed {} > original {}",
            stats.compressed_bytes,
            stats.original_bytes,
        );
    }

    #[test]
    fn compress_reduces_or_maintains_size_xpress16k() {
        let dir = TempDir::new().unwrap();
        create_compressible_file(dir.path(), "zeros.dat", 1_048_576);

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress16K);
        let stats = engine.compress_folder(dir.path()).unwrap();
        assert!(
            stats.compressed_bytes <= stats.original_bytes,
            "Xpress16K: compressed {} > original {}",
            stats.compressed_bytes,
            stats.original_bytes,
        );
    }

    #[test]
    fn compress_reduces_or_maintains_size_lzx() {
        let dir = TempDir::new().unwrap();
        create_compressible_file(dir.path(), "zeros.dat", 1_048_576);

        let engine = CompressionEngine::new(CompressionAlgorithm::Lzx);
        let stats = engine.compress_folder(dir.path()).unwrap();
        assert!(
            stats.compressed_bytes <= stats.original_bytes,
            "LZX: compressed {} > original {}",
            stats.compressed_bytes,
            stats.original_bytes,
        );
    }

    #[test]
    fn roundtrip_preserves_file_content() {
        let dir = TempDir::new().unwrap();
        let path = create_compressible_file(dir.path(), "data.dat", 1_048_576);
        let original = fs::read(&path).unwrap();

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        engine.compress_folder(dir.path()).unwrap();

        // WOF is transparent: file content is identical while compressed
        let during = fs::read(&path).unwrap();
        assert_eq!(original, during, "content changed during compression");

        // After decompression, content must still match
        let engine2 = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        engine2.decompress_folder(dir.path()).unwrap();
        let after = fs::read(&path).unwrap();
        assert_eq!(original, after, "content changed after roundtrip");
    }

    #[test]
    fn decompression_restores_logical_size() {
        let dir = TempDir::new().unwrap();
        let path = create_compressible_file(dir.path(), "data.dat", 1_048_576);
        let original_size = fs::metadata(&path).unwrap().len();

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        engine.compress_folder(dir.path()).unwrap();

        let engine2 = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        engine2.decompress_folder(dir.path()).unwrap();

        let restored_size = fs::metadata(&path).unwrap().len();
        assert_eq!(original_size, restored_size);
    }

    #[test]
    fn cancellation_stops_compression() {
        let dir = TempDir::new().unwrap();
        for i in 0..50 {
            create_compressible_file(dir.path(), &format!("file_{i}.dat"), 8192);
        }

        let engine = CompressionEngine::new(CompressionAlgorithm::default());
        let token = engine.cancel_token();
        token.cancel();

        let result = engine.compress_folder(dir.path());
        assert!(matches!(result, Err(CompressionError::Cancelled)));
    }

    #[test]
    fn cancellation_stops_decompression() {
        let dir = TempDir::new().unwrap();
        for i in 0..50 {
            create_compressible_file(dir.path(), &format!("file_{i}.dat"), 8192);
        }

        let engine = CompressionEngine::new(CompressionAlgorithm::default());
        let token = engine.cancel_token();
        token.cancel();

        let result = engine.decompress_folder(dir.path());
        assert!(matches!(result, Err(CompressionError::Cancelled)));
    }

    #[test]
    fn compress_with_progress_empty_folder_sends_completion_snapshot() {
        let dir = TempDir::new().unwrap();
        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress4K);

        let streams = engine
            .compress_folder_with_progress(dir.path(), "Empty".into())
            .unwrap();

        let result = streams.result.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(result.is_ok(), "empty folder compression should succeed");

        let final_snapshot = streams
            .progress
            .recv_timeout(Duration::from_secs(1))
            .unwrap();
        assert!(
            final_snapshot.is_complete,
            "empty-folder operation should still send a completion snapshot"
        );
        assert_eq!(final_snapshot.files_total, 0);
        assert_eq!(final_snapshot.files_processed, 0);
    }

    #[test]
    fn compress_with_progress_is_async_for_nontrivial_workload() {
        let dir = TempDir::new().unwrap();
        for i in 0..64 {
            create_compressible_file(dir.path(), &format!("big_{i}.dat"), 1_048_576);
        }

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        let started = Instant::now();
        let streams = engine
            .compress_folder_with_progress(dir.path(), "Async".into())
            .unwrap();
        assert!(
            started.elapsed() < Duration::from_secs(2),
            "starting async compression should return quickly"
        );
        assert!(
            matches!(streams.result.try_recv(), Err(TryRecvError::Empty)),
            "result channel should not be complete immediately for a non-trivial workload"
        );

        let progress = streams
            .progress
            .recv_timeout(Duration::from_secs(3))
            .unwrap();
        assert_eq!(progress.game_name, "Async");

        let result = streams
            .result
            .recv_timeout(Duration::from_secs(60))
            .unwrap();
        let stats = result.expect("compression should succeed");
        assert!(stats.files_processed > 0);
    }

    #[test]
    fn compress_with_progress_can_complete_without_progress_consumer() {
        let dir = TempDir::new().unwrap();
        for i in 0..8 {
            create_compressible_file(dir.path(), &format!("file_{i}.dat"), 131_072);
        }

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        let streams = engine
            .compress_folder_with_progress(dir.path(), "NoProgressConsumer".into())
            .unwrap();
        let CompressionProgressHandle { progress, result } = streams;
        drop(progress);

        let stats = result
            .recv_timeout(Duration::from_secs(60))
            .unwrap()
            .expect("compression should still complete when progress stream is dropped");
        assert!(stats.files_processed > 0);
    }

    #[test]
    fn small_files_are_skipped() {
        let dir = TempDir::new().unwrap();
        // All files below 4096 bytes
        create_compressible_file(dir.path(), "tiny1.dat", 100);
        create_compressible_file(dir.path(), "tiny2.dat", 2048);
        create_compressible_file(dir.path(), "tiny3.dat", 4095);

        let engine = CompressionEngine::new(CompressionAlgorithm::default());
        let stats = engine.compress_folder(dir.path()).unwrap();
        assert_eq!(stats.files_skipped, 3, "all tiny files should be skipped");
        assert_eq!(stats.original_bytes, 0);
    }

    #[test]
    fn nested_directory_structure() {
        let dir = TempDir::new().unwrap();
        create_nested_structure(dir.path());

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        let stats = engine.compress_folder(dir.path()).unwrap();

        // Should have processed all files (5 total: big_zeros, nested_zeros, tiny, random, empty)
        assert!(stats.files_processed > 0, "should process files");
        // tiny.dat and empty.txt should be skipped (< 4096 bytes)
        assert!(
            stats.files_skipped >= 2,
            "tiny and empty files should be skipped"
        );
    }

    #[test]
    fn already_compressed_files_handled_gracefully() {
        let dir = TempDir::new().unwrap();
        create_compressible_file(dir.path(), "data.dat", 1_048_576);

        // Compress once
        let engine1 = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        engine1.compress_folder(dir.path()).unwrap();

        // Compress again -- should not error
        let engine2 = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        let result = engine2.compress_folder(dir.path());
        assert!(result.is_ok(), "re-compressing should not error");
    }

    #[test]
    fn get_compression_ratio_reflects_compression() {
        let dir = TempDir::new().unwrap();
        create_compressible_file(dir.path(), "zeros.dat", 1_048_576);

        // Ratio before compression
        let ratio_before = CompressionEngine::get_compression_ratio(dir.path()).unwrap();
        // Should be close to 1.0 (no compression)
        assert!(
            ratio_before > 0.9,
            "uncompressed ratio should be near 1.0, got {ratio_before}"
        );

        let engine = CompressionEngine::new(CompressionAlgorithm::Xpress4K);
        engine.compress_folder(dir.path()).unwrap();

        // Ratio after compression
        let ratio_after = CompressionEngine::get_compression_ratio(dir.path()).unwrap();
        assert!(
            ratio_after < ratio_before,
            "compressed ratio {ratio_after} should be less than uncompressed {ratio_before}"
        );
    }

    #[test]
    fn wof_single_file_compress_and_query() {
        let dir = TempDir::new().unwrap();
        let path = create_compressible_file(dir.path(), "test.dat", 1_048_576);

        let algo = CompressionAlgorithm::Xpress4K;
        let result = wof::wof_compress_file(&path, algo).unwrap();
        assert_eq!(result, wof::CompressFileResult::Compressed);

        // Query should return the algorithm we used
        let detected = wof::wof_get_compression(&path).unwrap();
        assert_eq!(detected, Some(algo));

        // Physical size should be less than logical
        let phys = wof::get_physical_size(&path).unwrap();
        let logical = fs::metadata(&path).unwrap().len();
        assert!(
            phys < logical,
            "physical {phys} should be less than logical {logical}"
        );

        // Decompress
        wof::wof_decompress_file(&path).unwrap();
        let detected_after = wof::wof_get_compression(&path).unwrap();
        assert_eq!(
            detected_after, None,
            "should be uncompressed after decompress"
        );
    }

    #[test]
    fn wof_decompress_uncompressed_file_is_noop() {
        let dir = TempDir::new().unwrap();
        let path = create_compressible_file(dir.path(), "uncompressed.dat", 8192);
        // Should not error
        let result = wof::wof_decompress_file(&path);
        assert!(result.is_ok());
    }

    #[test]
    fn wof_get_compression_uncompressed_returns_none() {
        let dir = TempDir::new().unwrap();
        let path = create_compressible_file(dir.path(), "plain.dat", 8192);
        let result = wof::wof_get_compression(&path).unwrap();
        assert_eq!(result, None);
    }
}
