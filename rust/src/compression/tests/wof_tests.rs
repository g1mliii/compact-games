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
fn cancellation_does_not_stick_across_engine_reuse_or_clone() {
    let dir = TempDir::new().unwrap();
    create_compressible_file(dir.path(), "single.dat", 8192);

    let engine = CompressionEngine::new(CompressionAlgorithm::default());
    let clone = engine.clone();
    clone.cancel_token().cancel();

    let cancelled = clone.compress_folder(dir.path());
    assert!(matches!(cancelled, Err(CompressionError::Cancelled)));

    let second_run = engine.compress_folder(dir.path());
    assert!(
        second_run.is_ok(),
        "cancellation should reset after cancelled operation, got {second_run:?}"
    );
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
