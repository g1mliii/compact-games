use std::fs::{self, File};
use std::path::Path;

use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::history::{
    record_compression, ActualStats, CompressionHistoryEntry, EstimateSnapshot,
};
use crate::discovery::cache;
use crate::discovery::hidden_paths;
use crate::discovery::install_history;
use crate::discovery::platform::{DiscoveryScanMode, Platform};
use crate::discovery::test_sync::lock_discovery_test;

use super::{build_game_info_with_mode_and_stats_path, compression_timestamp_for_game_path};

#[test]
fn quick_scan_ignores_stale_cache_for_deleted_path() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("DeletedGame");
    fs::create_dir_all(&game_dir).unwrap();
    File::create(game_dir.join("game.exe"))
        .unwrap()
        .set_len(3 * 1024 * 1024)
        .unwrap();
    File::create(game_dir.join("content.bin"))
        .unwrap()
        .set_len(700 * 1024 * 1024)
        .unwrap();

    let full_scan = build_game_info_with_mode_and_stats_path(
        "Deleted Game".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Full,
    );
    assert!(full_scan.is_some());
    assert!(
        cache::lookup_stale(&game_dir).is_some(),
        "full scan should populate cache entry",
    );

    fs::remove_dir_all(&game_dir).unwrap();

    let quick_scan = build_game_info_with_mode_and_stats_path(
        "Deleted Game".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Quick,
    );
    assert!(quick_scan.is_none());
    assert!(
        cache::lookup_stale(&game_dir).is_none(),
        "missing path should evict stale cache entry",
    );
}

#[test]
fn quick_scan_rejects_medium_folder_without_game_executable() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("MediumRemnant");
    fs::create_dir_all(&game_dir).unwrap();
    File::create(game_dir.join("content.bin"))
        .unwrap()
        .set_len(700 * 1024 * 1024)
        .unwrap();

    let quick_scan = build_game_info_with_mode_and_stats_path(
        "Medium Remnant".to_owned(),
        game_dir.clone(),
        game_dir,
        Platform::Steam,
        DiscoveryScanMode::Quick,
    );

    assert!(
        quick_scan.is_none(),
        "medium remnant without plausible game executable should be rejected",
    );
}

#[test]
fn quick_scan_accepts_medium_folder_with_game_executable() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("MediumInstalledGame");
    fs::create_dir_all(&game_dir).unwrap();
    File::create(game_dir.join("game.exe"))
        .unwrap()
        .set_len(3 * 1024 * 1024)
        .unwrap();
    File::create(game_dir.join("content.bin"))
        .unwrap()
        .set_len(700 * 1024 * 1024)
        .unwrap();

    let quick_scan = build_game_info_with_mode_and_stats_path(
        "Medium Installed Game".to_owned(),
        game_dir.clone(),
        game_dir,
        Platform::Steam,
        DiscoveryScanMode::Quick,
    );

    assert!(
        quick_scan.is_some(),
        "medium executable-backed installs should still be accepted",
    );
}

#[test]
fn quick_scan_accepts_unity_layout_with_small_bootstrap_exe() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("Cairn");
    let data_dir = game_dir.join("Cairn_Data");
    fs::create_dir_all(&data_dir).unwrap();
    File::create(game_dir.join("Cairn.exe"))
        .unwrap()
        .set_len(512 * 1024)
        .unwrap();
    fs::write(data_dir.join("globalgamemanagers"), vec![9_u8; 4096]).unwrap();

    let quick_scan = build_game_info_with_mode_and_stats_path(
        "Cairn".to_owned(),
        game_dir.clone(),
        game_dir,
        Platform::Custom,
        DiscoveryScanMode::Quick,
    );

    assert!(
        quick_scan.is_some(),
        "Unity layout should pass install-likelihood probe even with a smaller bootstrap executable",
    );
}

#[test]
fn quick_scan_accepts_mid_size_xbox_install_without_probeable_exe() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("XboxMidSize");
    let content_dir = game_dir.join("Content");
    fs::create_dir_all(&content_dir).unwrap();
    File::create(content_dir.join("content.bin"))
        .unwrap()
        .set_len(300 * 1024 * 1024)
        .unwrap();

    let quick_scan = build_game_info_with_mode_and_stats_path(
        "Xbox Mid Size".to_owned(),
        game_dir,
        content_dir,
        Platform::XboxGamePass,
        DiscoveryScanMode::Quick,
    );

    assert!(
        quick_scan.is_some(),
        "mid-size Xbox installs should remain discoverable even without a probeable exe",
    );
}

#[test]
fn quick_scan_clears_stale_cache_when_install_shrinks_to_stub() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("ShrinkingInstall");
    fs::create_dir_all(&game_dir).unwrap();
    let exe_path = game_dir.join("game.exe");
    File::create(&exe_path)
        .unwrap()
        .set_len(3 * 1024 * 1024)
        .unwrap();
    File::create(game_dir.join("content.bin"))
        .unwrap()
        .set_len(700 * 1024 * 1024)
        .unwrap();

    let first_full = build_game_info_with_mode_and_stats_path(
        "Shrinking Install".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Full,
    );
    assert!(first_full.is_some());
    assert!(cache::lookup_stale(&game_dir).is_some());

    fs::remove_file(exe_path).unwrap();
    fs::write(game_dir.join("leftover.txt"), vec![1_u8; 2048]).unwrap();

    let second_quick = build_game_info_with_mode_and_stats_path(
        "Shrinking Install".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Quick,
    );

    assert!(second_quick.is_none());
    assert!(
        cache::lookup_stale(&game_dir).is_none(),
        "invalid candidate should clear stale cached stats",
    );
}

#[test]
fn quick_scan_keeps_authoritative_cached_size_when_token_drifts() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("TokenDriftGame");
    let deep_content = game_dir
        .join("content")
        .join("packs")
        .join("nested")
        .join("data");
    fs::create_dir_all(&deep_content).unwrap();

    File::create(game_dir.join("game.exe"))
        .unwrap()
        .set_len(3 * 1024 * 1024)
        .unwrap();
    File::create(deep_content.join("bulk.pak"))
        .unwrap()
        .set_len(700 * 1024 * 1024)
        .unwrap();

    let full = build_game_info_with_mode_and_stats_path(
        "Token Drift Game".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Full,
    )
    .expect("full scan should build game info");
    let full_size = full.size_bytes;
    assert!(full_size > 40 * 1024 * 1024);

    // Token drift at root should invalidate strict token lookup.
    fs::write(game_dir.join("drift.marker"), b"drift").unwrap();

    let quick = build_game_info_with_mode_and_stats_path(
        "Token Drift Game".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Quick,
    )
    .expect("quick scan should use stale cache fallback");

    assert_eq!(
        quick.size_bytes, full_size,
        "quick mode should preserve authoritative cached size instead of sampled overwrite"
    );
    let cached_after = cache::lookup_stale(&game_dir).expect("cache entry should remain");
    assert_eq!(cached_after.logical_size, full_size);
}

#[test]
fn quick_scan_keeps_authoritative_xbox_cache_when_deep_content_underflows_shallow_sample() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("XboxDeepTokenDrift");
    let content_dir = game_dir.join("Content");
    let deep_content = content_dir
        .join("packs")
        .join("chunk")
        .join("deep")
        .join("data");
    fs::create_dir_all(&deep_content).unwrap();

    File::create(deep_content.join("bulk.pak"))
        .unwrap()
        .set_len(700 * 1024 * 1024)
        .unwrap();

    let full = build_game_info_with_mode_and_stats_path(
        "Xbox Deep Token Drift".to_owned(),
        game_dir.clone(),
        content_dir.clone(),
        Platform::XboxGamePass,
        DiscoveryScanMode::Full,
    )
    .expect("full scan should build xbox game info");
    let full_size = full.size_bytes;
    assert!(full_size >= 700 * 1024 * 1024);

    // Token drift at the stats root should invalidate strict token lookup while
    // leaving the deep payload outside the shallow quick-scan window.
    fs::write(content_dir.join("drift.marker"), b"drift").unwrap();

    let quick = build_game_info_with_mode_and_stats_path(
        "Xbox Deep Token Drift".to_owned(),
        game_dir,
        content_dir.clone(),
        Platform::XboxGamePass,
        DiscoveryScanMode::Quick,
    )
    .expect("quick scan should retain authoritative xbox stale cache");

    assert_eq!(
        quick.size_bytes, full_size,
        "quick mode should preserve authoritative cached size for deep Xbox installs when shallow sampling undercounts",
    );
    let cached_after = cache::lookup_stale(&content_dir).expect("cache entry should remain");
    assert_eq!(cached_after.logical_size, full_size);
}

#[test]
fn quick_scan_rejects_large_stale_cache_when_install_shrinks_to_medium_remnant() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("ShrinkingLargeInstall");
    fs::create_dir_all(&game_dir).unwrap();

    File::create(game_dir.join("game.exe"))
        .unwrap()
        .set_len(3 * 1024 * 1024)
        .unwrap();
    File::create(game_dir.join("base.pak"))
        .unwrap()
        .set_len(6 * 1024 * 1024 * 1024)
        .unwrap();

    let first_full = build_game_info_with_mode_and_stats_path(
        "Shrinking Large Install".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Full,
    );
    assert!(first_full.is_some());
    assert!(
        cache::lookup_stale(&game_dir).is_some(),
        "full scan should populate authoritative cache entry",
    );

    fs::remove_file(game_dir.join("game.exe")).unwrap();
    fs::remove_file(game_dir.join("base.pak")).unwrap();
    File::create(game_dir.join("leftover.bin"))
        .unwrap()
        .set_len(600 * 1024 * 1024)
        .unwrap();

    let quick_scan = build_game_info_with_mode_and_stats_path(
        "Shrinking Large Install".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Quick,
    );

    assert!(
        quick_scan.is_none(),
        "quick scan should reject a stale large cache entry when current quick stats only show a medium remnant",
    );
    assert!(
        cache::lookup_stale(&game_dir).is_none(),
        "rejecting a remnant through stale-cache validation should evict the stale cache entry",
    );
}

#[test]
fn full_scan_rejects_large_install_that_shrank_to_remnant_after_refresh_clear() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("Resident Evil Requiem");
    fs::create_dir_all(&game_dir).unwrap();

    File::create(game_dir.join("game.exe"))
        .unwrap()
        .set_len(3 * 1024 * 1024)
        .unwrap();
    File::create(game_dir.join("base.pak"))
        .unwrap()
        .set_len(6 * 1024 * 1024 * 1024)
        .unwrap();

    let first_full = build_game_info_with_mode_and_stats_path(
        "Resident Evil Requiem".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Full,
    )
    .expect("large install should be accepted on first full scan");
    assert!(first_full.size_bytes >= 6 * 1024 * 1024 * 1024);

    cache::clear_all();
    crate::discovery::index::clear_all();

    fs::remove_file(game_dir.join("game.exe")).unwrap();
    fs::remove_file(game_dir.join("base.pak")).unwrap();
    File::create(game_dir.join("leftover.bin"))
        .unwrap()
        .set_len(600 * 1024 * 1024)
        .unwrap();

    let second_full = build_game_info_with_mode_and_stats_path(
        "Resident Evil Requiem".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Full,
    );

    assert!(
        second_full.is_none(),
        "full refresh should reject paths that shrank from a large install to a remnant-sized leftover"
    );
}

#[test]
fn full_scan_accepts_medium_install_with_game_executable() {
    let _guard = lock_discovery_test();
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("Fresh Medium Install");
    fs::create_dir_all(&game_dir).unwrap();
    File::create(game_dir.join("game.exe"))
        .unwrap()
        .set_len(3 * 1024 * 1024)
        .unwrap();
    File::create(game_dir.join("content.bin"))
        .unwrap()
        .set_len(700 * 1024 * 1024)
        .unwrap();

    let full = build_game_info_with_mode_and_stats_path(
        "Fresh Medium Install".to_owned(),
        game_dir.clone(),
        game_dir,
        Platform::Steam,
        DiscoveryScanMode::Full,
    );

    assert!(
        full.is_some(),
        "medium installs should still be accepted when a plausible game executable exists"
    );
}

#[test]
fn manual_hide_clears_old_history_and_rediscovers_reinstall_on_same_path() {
    let _guard = lock_discovery_test();
    cache::clear_all();
    crate::discovery::index::clear_all();
    hidden_paths::clear_all();

    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("ReinstallSamePath");
    fs::create_dir_all(&game_dir).unwrap();

    File::create(game_dir.join("game.exe"))
        .unwrap()
        .set_len(3 * 1024 * 1024)
        .unwrap();
    File::create(game_dir.join("base.pak"))
        .unwrap()
        .set_len(6 * 1024 * 1024 * 1024)
        .unwrap();

    let first_full = build_game_info_with_mode_and_stats_path(
        "Reinstall Same Path".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Full,
    );
    assert!(first_full.is_some());
    assert!(
        install_history::max_observed_size(&game_dir).is_some(),
        "first full scan should record authoritative install history",
    );

    hidden_paths::hide_path(&game_dir);
    install_history::remove(&game_dir);
    cache::remove(&game_dir);
    crate::discovery::index::remove(&game_dir);

    fs::remove_file(game_dir.join("base.pak")).unwrap();
    File::create(game_dir.join("content.bin"))
        .unwrap()
        .set_len(700 * 1024 * 1024)
        .unwrap();

    let reinstall = build_game_info_with_mode_and_stats_path(
        "Reinstall Same Path".to_owned(),
        game_dir.clone(),
        game_dir.clone(),
        Platform::Steam,
        DiscoveryScanMode::Full,
    );

    assert!(
        reinstall.is_some(),
        "manual removal should not suppress a legitimate medium reinstall on the same path",
    );
    assert!(
        !hidden_paths::should_hide(
            &game_dir,
            &cache::compute_change_token(&game_dir, cache::has_entry(&game_dir)),
        ),
        "changed reinstall should auto-clear the hidden-path tombstone",
    );
}

#[test]
fn compression_timestamp_only_exposed_for_compressed_games() {
    let _guard = lock_discovery_test();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path_buf = std::path::PathBuf::from(format!(r"C:\Games\CompressionStamp_{nanos}"));
    let path = Path::new(&path_buf);

    record_compression(CompressionHistoryEntry {
        game_path: path.to_string_lossy().into_owned(),
        game_name: "Compression Stamp".to_string(),
        timestamp_ms: 1_700_000_123_456,
        estimate: EstimateSnapshot {
            scanned_files: 0,
            sampled_bytes: 0,
            estimated_saved_bytes: 0,
        },
        actual_stats: ActualStats {
            original_bytes: 10_000,
            compressed_bytes: 8_000,
            actual_saved_bytes: 2_000,
            files_processed: 10,
        },
        algorithm: CompressionAlgorithm::Xpress8K,
        duration_ms: 10,
    });

    assert!(
        compression_timestamp_for_game_path(path, true).is_some(),
        "compressed entries should expose last-compressed timestamp"
    );
    assert_eq!(
        compression_timestamp_for_game_path(path, false),
        None,
        "non-compressed entries should hide last-compressed timestamp"
    );
}
