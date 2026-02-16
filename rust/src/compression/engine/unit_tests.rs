use std::fs;
use std::path::Path;

use super::*;
use tempfile::TempDir;

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
        engine.try_operation_guard().is_none(),
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

#[test]
fn estimate_savings_uses_extension_buckets() {
    let dir = TempDir::new().expect("temp dir should be created");
    let incompressible = dir.path().join("archive.pak");
    let compressible = dir.path().join("config.txt");

    fs::write(&incompressible, vec![7_u8; 10_000]).expect("write incompressible fixture");
    fs::write(&compressible, vec![1_u8; 10_000]).expect("write compressible fixture");

    let engine = CompressionEngine::new(CompressionAlgorithm::Xpress8K);
    let estimate = engine
        .estimate_folder_savings(dir.path())
        .expect("estimate should succeed");

    assert_eq!(estimate.scanned_files, 2);
    assert_eq!(estimate.sampled_bytes, 20_000);
    assert_eq!(
        estimate.estimated_saved_bytes, 3_550,
        "0.5% of 10_000 + 35% of 10_000 should be predicted for XPRESS8K"
    );
}

#[test]
fn estimate_savings_scales_with_algorithm_strength() {
    let dir = TempDir::new().expect("temp dir should be created");
    let unknown = dir.path().join("blob.bin");
    fs::write(&unknown, vec![3_u8; 100_000]).expect("write unknown fixture");

    let saved_4k = CompressionEngine::new(CompressionAlgorithm::Xpress4K)
        .estimate_folder_savings(dir.path())
        .expect("estimate should succeed")
        .estimated_saved_bytes;
    let saved_8k = CompressionEngine::new(CompressionAlgorithm::Xpress8K)
        .estimate_folder_savings(dir.path())
        .expect("estimate should succeed")
        .estimated_saved_bytes;
    let saved_16k = CompressionEngine::new(CompressionAlgorithm::Xpress16K)
        .estimate_folder_savings(dir.path())
        .expect("estimate should succeed")
        .estimated_saved_bytes;
    let saved_lzx = CompressionEngine::new(CompressionAlgorithm::Lzx)
        .estimate_folder_savings(dir.path())
        .expect("estimate should succeed")
        .estimated_saved_bytes;

    assert!(saved_4k < saved_8k);
    assert!(saved_8k < saved_16k);
    assert!(saved_16k < saved_lzx);
}
