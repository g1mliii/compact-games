use std::fs::File;
use std::path::PathBuf;

use tempfile::TempDir;

use super::*;

#[test]
fn custom_scanner_empty_paths_returns_empty() {
    let scanner = CustomScanner::new(Vec::new());
    let result = scanner.scan(DiscoveryScanMode::Full).unwrap();
    assert!(result.is_empty());
}

#[test]
fn custom_scanner_nonexistent_path_returns_empty() {
    let scanner = CustomScanner::new(vec![PathBuf::from(r"C:\NonExistent\CustomGames")]);
    let result = scanner.scan(DiscoveryScanMode::Full).unwrap();
    assert!(result.is_empty());
}

#[test]
fn scan_custom_path_includes_subdirs_when_root_matches() {
    let root = TempDir::new().unwrap();
    let root_path = root.path();

    std::fs::create_dir(root_path.join("data")).unwrap();
    let root_exe = root_path.join("rootgame.exe");
    File::create(&root_exe)
        .unwrap()
        .set_len(MIN_EXE_SIZE + 1)
        .unwrap();

    let sub_game_path = root_path.join("SubGame");
    std::fs::create_dir_all(sub_game_path.join("bin")).unwrap();
    let sub_exe = sub_game_path.join("subgame.exe");
    File::create(&sub_exe)
        .unwrap()
        .set_len(MIN_EXE_SIZE + 1)
        .unwrap();

    let games = scan_custom_path(root_path, DiscoveryScanMode::Full, true).unwrap();
    assert!(games.iter().any(|g| g.path == sub_game_path));
}

#[test]
fn is_non_game_exe_filters_installers() {
    assert!(is_non_game_exe("unins000.exe"));
    assert!(is_non_game_exe("setup.exe"));
    assert!(is_non_game_exe("vcredist_x64.exe"));
    assert!(is_non_game_exe("dxsetup.exe"));
    assert!(!is_non_game_exe("game.exe"));
    assert!(!is_non_game_exe("gamelauncher.exe"));
    assert!(!is_non_game_exe("portal2.exe"));
}

#[test]
fn skip_folders_are_lowercase() {
    for folder in SKIP_FOLDERS {
        assert_eq!(*folder, folder.to_ascii_lowercase());
    }
}

#[test]
fn detects_nested_unreal_style_layout() {
    let root = TempDir::new().unwrap();
    let game_root = root.path().join("TekkenLike");
    let win64 = game_root.join("Polaris").join("Binaries").join("Win64");
    std::fs::create_dir_all(&win64).unwrap();
    std::fs::create_dir_all(game_root.join("Polaris").join("Content")).unwrap();
    File::create(win64.join("Polaris-Win64-Shipping.exe"))
        .unwrap()
        .set_len(MIN_EXE_SIZE + 1)
        .unwrap();

    assert!(is_game_folder(&game_root));
}

#[test]
fn detects_double_nested_unreal_style_layout() {
    let root = TempDir::new().unwrap();
    let game_root = root.path().join("tekken 8");
    let wrapped_root = game_root.join("TEKKEN 8");
    let win64 = wrapped_root.join("Polaris").join("Binaries").join("Win64");
    std::fs::create_dir_all(&win64).unwrap();
    std::fs::create_dir_all(wrapped_root.join("Engine")).unwrap();
    File::create(wrapped_root.join("TEKKEN 8.exe"))
        .unwrap()
        .set_len(MIN_UNITY_BOOTSTRAP_EXE_SIZE + 1)
        .unwrap();
    File::create(win64.join("Polaris-Win64-Shipping.exe"))
        .unwrap()
        .set_len(MIN_EXE_SIZE + 1)
        .unwrap();

    assert!(
        is_game_folder(&game_root),
        "wrapper-folder Unreal installs should still be detected as game folders"
    );
}

#[test]
fn library_root_mode_skips_root_candidate() {
    let root = TempDir::new().unwrap();
    let root_path = root.path();

    std::fs::create_dir(root_path.join("data")).unwrap();
    File::create(root_path.join("rootgame.exe"))
        .unwrap()
        .set_len(MIN_EXE_SIZE + 1)
        .unwrap();

    let games = scan_custom_path(root_path, DiscoveryScanMode::Full, false).unwrap();
    assert!(
        !games.iter().any(|g| g.path == root_path),
        "library-root mode should not return root path itself"
    );
}

#[test]
fn detects_unity_layout_from_library_root() {
    let root = TempDir::new().unwrap();
    let games_root = root.path().join("Games");
    let cairn = games_root.join("Cairn");
    let data = cairn.join("Cairn_Data");

    std::fs::create_dir_all(&data).unwrap();
    File::create(cairn.join("Cairn.exe"))
        .unwrap()
        .set_len(MIN_UNITY_BOOTSTRAP_EXE_SIZE + 1)
        .unwrap();
    File::create(data.join("globalgamemanagers"))
        .unwrap()
        .set_len(2 * 1024 * 1024)
        .unwrap();

    let games = scan_custom_path(&games_root, DiscoveryScanMode::Full, false).unwrap();
    assert!(
        games.iter().any(|g| g.path == cairn),
        "Unity folder under Games root should be discovered"
    );
}
