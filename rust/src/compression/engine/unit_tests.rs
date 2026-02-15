use std::path::Path;

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
