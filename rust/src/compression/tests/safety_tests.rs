use std::sync::Arc;

use super::*;

#[test]
fn directstorage_game_rejected() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("dstorage.dll"), b"fake").unwrap();
    create_compressible_file(dir.path(), "data.dat", 8192);

    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    let result = engine.compress_folder(dir.path());
    assert!(
        matches!(result, Err(CompressionError::DirectStorageDetected)),
        "should reject DirectStorage game, got {result:?}"
    );
}

#[test]
fn non_directstorage_game_not_rejected() {
    let dir = TempDir::new().unwrap();
    create_compressible_file(dir.path(), "game.exe", 8192);

    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    let result = engine.compress_folder(dir.path());
    assert!(
        !matches!(result, Err(CompressionError::DirectStorageDetected)),
        "should not reject non-DirectStorage game"
    );
}

#[test]
fn directstorage_game_rejected_with_progress() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("dstorage.dll"), b"fake").unwrap();
    create_compressible_file(dir.path(), "data.dat", 8192);

    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    let result = engine.compress_folder_with_progress(dir.path(), Arc::from("DS Game"));
    assert!(
        result.is_err(),
        "progress variant should reject DirectStorage game"
    );
}

#[test]
fn directstorage_override_allows_compression() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("dstorage.dll"), b"fake").unwrap();
    create_compressible_file(dir.path(), "data.dat", 8192);

    let engine =
        CompressionEngine::new(CompressionAlgorithm::default()).with_directstorage_override(true);
    let result = engine.compress_folder(dir.path());
    assert!(
        !matches!(result, Err(CompressionError::DirectStorageDetected)),
        "override should bypass DirectStorage block, got {result:?}"
    );
}

#[test]
fn directstorage_override_allows_progress_start() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("dstorage.dll"), b"fake").unwrap();
    create_compressible_file(dir.path(), "data.dat", 8192);

    let engine =
        CompressionEngine::new(CompressionAlgorithm::default()).with_directstorage_override(true);
    let handle = engine.compress_folder_with_progress(dir.path(), Arc::from("DS Override"));
    assert!(
        handle.is_ok(),
        "override should allow progress compression to start"
    );

    if let Ok(streams) = handle {
        let _ = streams.result.recv_timeout(Duration::from_secs(5));
    }
}

#[test]
fn running_game_detected_via_engine() {
    let checker = Arc::new(ProcessChecker::new());
    let exe = std::env::current_exe().unwrap();
    let exe_dir = exe.parent().unwrap();

    let engine =
        CompressionEngine::new(CompressionAlgorithm::default()).with_safety(SafetyConfig {
            process_checker: checker,
        });

    let result = engine.compress_folder(exe_dir);
    assert!(
        matches!(result, Err(CompressionError::GameRunning)),
        "should detect running process in exe directory, got {result:?}"
    );
}

#[cfg(windows)]
#[test]
fn safety_config_allows_safe_folder() {
    let dir = TempDir::new().unwrap();
    create_compressible_file(dir.path(), "data.dat", 8192);

    let checker = Arc::new(ProcessChecker::new());
    let engine =
        CompressionEngine::new(CompressionAlgorithm::default()).with_safety(SafetyConfig {
            process_checker: checker,
        });

    let result = engine.compress_folder(dir.path());
    assert!(
        result.is_ok(),
        "should compress when no game running and no DS"
    );
}
