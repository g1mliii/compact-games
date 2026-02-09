use std::path::Path;

use walkdir::WalkDir;

/// Known DirectStorage DLL filenames (case-insensitive check).
const DIRECTSTORAGE_DLLS: &[&str] = &["dstorage.dll", "dstoragecore.dll"];

/// Known DirectStorage manifest patterns.
const DIRECTSTORAGE_MANIFESTS: &[&str] = &["directstorage.json", "dstorage.json"];

/// Check whether a game directory contains DirectStorage components.
///
/// Returns `true` if any DirectStorage indicator files are found.
/// Games using DirectStorage should NOT be compressed, as WOF
/// compression interferes with DirectStorage's GPU-direct I/O path.
pub fn is_directstorage_game(game_path: &Path) -> bool {
    if !game_path.is_dir() {
        return false;
    }

    for entry in WalkDir::new(game_path)
        .max_depth(3) // DStorage DLLs are typically near the root
        .into_iter()
        .filter_map(|e| e.ok())
    {
        if let Some(name) = entry.file_name().to_str() {
            let lower = name.to_ascii_lowercase();
            if DIRECTSTORAGE_DLLS.iter().any(|dll| lower == *dll) {
                log::warn!(
                    "DirectStorage detected: {} in {}",
                    name,
                    game_path.display()
                );
                return true;
            }
            if DIRECTSTORAGE_MANIFESTS.iter().any(|m| lower == *m) {
                log::warn!(
                    "DirectStorage manifest detected: {} in {}",
                    name,
                    game_path.display()
                );
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
}
