use std::fs;

use crate::discovery::cache;
use crate::discovery::platform::{DiscoveryScanMode, Platform};

use super::build_game_info_with_mode_and_stats_path;

#[test]
fn quick_scan_ignores_stale_cache_for_deleted_path() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("DeletedGame");
    fs::create_dir_all(&game_dir).unwrap();
    fs::write(
        game_dir.join("game.exe"),
        vec![1_u8; (3 * 1024 * 1024) as usize],
    )
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
fn quick_scan_rejects_small_folder_without_game_executable() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("Stub");
    fs::create_dir_all(&game_dir).unwrap();
    fs::write(game_dir.join("notes.txt"), vec![1_u8; 1024]).unwrap();

    let quick_scan = build_game_info_with_mode_and_stats_path(
        "Stub".to_owned(),
        game_dir.clone(),
        game_dir,
        Platform::Steam,
        DiscoveryScanMode::Quick,
    );

    assert!(
        quick_scan.is_none(),
        "small folder without plausible game executable should be rejected",
    );
}

#[test]
fn quick_scan_accepts_small_folder_with_game_executable() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("SmallInstalledGame");
    fs::create_dir_all(&game_dir).unwrap();
    fs::write(
        game_dir.join("smallgame.exe"),
        vec![7_u8; (3 * 1024 * 1024) as usize],
    )
    .unwrap();

    let quick_scan = build_game_info_with_mode_and_stats_path(
        "Small Installed Game".to_owned(),
        game_dir.clone(),
        game_dir,
        Platform::Steam,
        DiscoveryScanMode::Quick,
    );

    assert!(
        quick_scan.is_some(),
        "small but executable-backed installs should still be accepted",
    );
}

#[test]
fn quick_scan_clears_stale_cache_when_install_shrinks_to_stub() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("ShrinkingInstall");
    fs::create_dir_all(&game_dir).unwrap();
    let exe_path = game_dir.join("game.exe");
    fs::write(&exe_path, vec![2_u8; (3 * 1024 * 1024) as usize]).unwrap();

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
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("TokenDriftGame");
    let deep_content = game_dir
        .join("content")
        .join("packs")
        .join("nested")
        .join("data");
    fs::create_dir_all(&deep_content).unwrap();

    fs::write(
        game_dir.join("game.exe"),
        vec![9_u8; (3 * 1024 * 1024) as usize],
    )
    .unwrap();
    fs::write(
        deep_content.join("bulk.pak"),
        vec![7_u8; (48 * 1024 * 1024) as usize],
    )
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
