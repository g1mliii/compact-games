use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use super::*;
use crate::compression::community_db::{
    clear_database_for_tests, mark_fetching_for_tests, replace_database_for_tests,
    CommunityAlgorithmRatios, CommunityAlgorithmSamples, CommunityCompressionDatabase,
    CommunityCompressionEntry,
};
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
    assert_eq!(estimate.base_source, CompressionEstimateSource::Heuristic);
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

#[test]
fn estimate_with_context_uses_community_db_before_file_walk() {
    let dir = TempDir::new().expect("temp dir should be created");
    fs::write(dir.path().join("blob.bin"), vec![3_u8; 100_000]).expect("write fixture");

    let mut entries = BTreeMap::new();
    entries.insert(
        "steam:440".to_string(),
        CommunityCompressionEntry {
            name: "Team Fortress 2".to_string(),
            folder_name: Some("Team Fortress 2".to_string()),
            samples: 20,
            ratios: CommunityAlgorithmRatios {
                xpress4k: None,
                xpress8k: Some(0.25),
                xpress16k: None,
                lzx: None,
            },
            ratio_samples: CommunityAlgorithmSamples {
                xpress4k: None,
                xpress8k: Some(20),
                xpress16k: None,
                lzx: None,
            },
        },
    );
    replace_database_for_tests(CommunityCompressionDatabase {
        version: 1,
        generated_at: String::new(),
        source: String::new(),
        entries,
        aliases: BTreeMap::new(),
    });

    let estimate = CompressionEngine::new(CompressionAlgorithm::Xpress8K)
        .estimate_folder_savings_with_context(
            dir.path(),
            EstimateGameContext {
                game_name: Some("Team Fortress 2"),
                steam_app_id: Some(440),
                known_size_bytes: Some(100_000),
            },
        )
        .expect("estimate should succeed");

    assert_eq!(estimate.scanned_files, 0);
    assert_eq!(estimate.sampled_bytes, 100_000);
    assert_eq!(estimate.estimated_saved_bytes, 25_000);
    assert_eq!(estimate.base_source, CompressionEstimateSource::CommunityDb);
    assert_eq!(estimate.community_samples, Some(20));
    assert!(!estimate.community_lookup_pending);
}

#[test]
fn estimate_with_pending_community_db_marks_heuristic_for_retry() {
    let dir = TempDir::new().expect("temp dir should be created");
    fs::write(dir.path().join("blob.bin"), vec![3_u8; 100_000]).expect("write fixture");
    mark_fetching_for_tests();

    let estimate = CompressionEngine::new(CompressionAlgorithm::Xpress8K)
        .estimate_folder_savings_with_context(
            dir.path(),
            EstimateGameContext {
                game_name: Some("Team Fortress 2"),
                steam_app_id: Some(440),
                known_size_bytes: Some(100_000),
            },
        )
        .expect("estimate should fall back to heuristic");
    clear_database_for_tests();

    assert_eq!(estimate.base_source, CompressionEstimateSource::Heuristic);
    assert!(estimate.community_lookup_pending);
    assert!(estimate.estimated_saved_bytes > 0);
}
