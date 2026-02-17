//! DirectStorage detection for game directories.
//!
//! Games using DirectStorage must NOT be compressed, as WOF
//! compression interferes with DirectStorage's GPU-direct I/O path.

use std::path::Path;

use walkdir::WalkDir;

use super::known_games::{is_known_directstorage_game, learn_directstorage_game};

const DIRECTSTORAGE_DLLS: &[&str] = &["dstorage.dll", "dstoragecore.dll"];
const DIRECTSTORAGE_MANIFESTS: &[&str] = &["directstorage.json", "dstorage.json"];

pub fn is_directstorage_game(game_path: &Path) -> bool {
    if !game_path.is_dir() {
        return false;
    }

    if is_known_directstorage_game(game_path) {
        log::info!(
            "DirectStorage detected via known-games database: {}",
            game_path.display()
        );
        return true;
    }

    for entry in WalkDir::new(game_path)
        .max_depth(3)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        if let Some(name) = entry.file_name().to_str() {
            if DIRECTSTORAGE_DLLS
                .iter()
                .any(|dll| name.eq_ignore_ascii_case(dll))
            {
                log::info!(
                    "DirectStorage detected: {} in {}",
                    name,
                    game_path.display()
                );

                learn_directstorage_game(game_path);
                return true;
            }
            if DIRECTSTORAGE_MANIFESTS
                .iter()
                .any(|m| name.eq_ignore_ascii_case(m))
            {
                log::info!(
                    "DirectStorage manifest detected: {} in {}",
                    name,
                    game_path.display()
                );

                learn_directstorage_game(game_path);
                return true;
            }
        }
    }

    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn empty_dir_is_not_directstorage() {
        let dir = TempDir::new().unwrap();
        assert!(!is_directstorage_game(dir.path()));
    }

    #[test]
    fn dir_with_dstorage_dll_is_detected() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("dstorage.dll"), b"fake").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn detection_is_case_insensitive() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("DStorage.DLL"), b"fake").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn nonexistent_path_returns_false() {
        assert!(!is_directstorage_game(Path::new(
            r"C:\__nonexistent_pressplay_test__"
        )));
    }

    #[test]
    fn beyond_max_depth_not_detected() {
        let dir = TempDir::new().unwrap();

        let deep = dir.path().join("a").join("b").join("c");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(deep.join("dstorage.dll"), b"fake").unwrap();
        assert!(!is_directstorage_game(dir.path()));
    }

    #[test]
    fn at_max_depth_is_detected() {
        let dir = TempDir::new().unwrap();

        let deep = dir.path().join("a").join("b");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(deep.join("dstorage.dll"), b"fake").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn manifest_detection() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("directstorage.json"), b"{}").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn dstorage_json_detection() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("DStorage.JSON"), b"{}").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn dstoragecore_dll_detection() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("DStorageCore.dll"), b"fake").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn filesystem_detection_learns_game() {
        use super::super::known_games::is_known_directstorage_game;
        use std::time::{SystemTime, UNIX_EPOCH};

        let dir = TempDir::new().unwrap();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let unique_name = format!("UnknownGame_{}", nanos);
        let game_dir = dir.path().join(&unique_name);
        std::fs::create_dir(&game_dir).unwrap();
        std::fs::write(game_dir.join("dstorage.dll"), b"fake").unwrap();

        assert!(!is_known_directstorage_game(&game_dir));

        assert!(is_directstorage_game(&game_dir));

        assert!(is_known_directstorage_game(&game_dir));

        assert!(is_directstorage_game(&game_dir));
    }
}

#[cfg(test)]
mod property_tests {
    use super::*;
    use proptest::prelude::*;
    use tempfile::TempDir;

    proptest! {

        #[test]
        fn detection_is_deterministic(has_ds in proptest::bool::ANY) {
            let dir = TempDir::new().unwrap();
            if has_ds {
                std::fs::write(dir.path().join("dstorage.dll"), b"fake").unwrap();
            }
            let first = is_directstorage_game(dir.path());
            let second = is_directstorage_game(dir.path());
            prop_assert_eq!(first, second);
        }


        #[test]
        fn non_ds_files_no_false_positive(
            prefix in "[a-zA-Z]{1,8}",
        ) {
            let dir = TempDir::new().unwrap();
            let name = format!("{prefix}_other.dll");
            std::fs::write(dir.path().join(&name), b"data").unwrap();
            // Only real DS filenames should match
            let is_ds = name.eq_ignore_ascii_case("dstorage.dll")
                || name.eq_ignore_ascii_case("dstoragecore.dll");
            prop_assert_eq!(is_directstorage_game(dir.path()), is_ds);
        }
    }
}
