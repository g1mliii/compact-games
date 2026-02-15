use std::collections::HashSet;
use std::path::{Path, PathBuf};

use walkdir::WalkDir;

use super::platform::{GameInfo, Platform};

#[cfg(windows)]
type PathDedupKey = String;
#[cfg(not(windows))]
type PathDedupKey = PathBuf;

/// Directory size statistics collected in a single walk.
pub struct DirStats {
    pub logical_size: u64,
    pub physical_size: u64,
    pub is_compressed: bool,
}

/// Collect logical size, physical (compressed) size, and compression status
/// in a single directory walk. Avoids the 3-pass pattern of calling
/// dir_size + is_dir_compressed + dir_compressed_size separately.
#[cfg(windows)]
pub fn dir_stats(path: &Path) -> DirStats {
    use std::os::windows::ffi::OsStrExt;
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::{GetLastError, NO_ERROR};
    use windows::Win32::Storage::FileSystem::GetCompressedFileSizeW;

    let mut logical_size: u64 = 0;
    let mut physical_size: u64 = 0;
    let mut found_compressed = false;

    for entry in WalkDir::new(path)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
    {
        let logical = entry.metadata().map(|m| m.len()).unwrap_or(0);
        logical_size += logical;

        let wide: Vec<u16> = entry
            .path()
            .as_os_str()
            .encode_wide()
            .chain(Some(0))
            .collect();
        let mut high: u32 = 0;
        // SAFETY: `wide` is a null-terminated UTF-16 path buffer that lives
        // for the duration of this call, and `high` is a valid out pointer.
        let low = unsafe { GetCompressedFileSizeW(PCWSTR(wide.as_ptr()), Some(&mut high)) };
        let last_error = unsafe { GetLastError() };

        let physical = if low == u32::MAX && last_error != NO_ERROR {
            logical
        } else {
            u64::from(high) << 32 | u64::from(low)
        };

        physical_size += physical;

        if !found_compressed && logical >= 4096 && physical < logical {
            found_compressed = true;
        }
    }

    DirStats {
        logical_size,
        physical_size,
        is_compressed: found_compressed,
    }
}

#[cfg(not(windows))]
pub fn dir_stats(path: &Path) -> DirStats {
    let logical_size: u64 = WalkDir::new(path)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .filter_map(|e| e.metadata().ok())
        .map(|m| m.len())
        .sum();

    DirStats {
        logical_size,
        physical_size: logical_size,
        is_compressed: false,
    }
}

/// Build a GameInfo from a name, path, and platform.
/// Returns None if the directory is empty.
/// Single walk for all size/compression/DirectStorage checks.
pub fn build_game_info(name: String, game_path: PathBuf, platform: Platform) -> Option<GameInfo> {
    let stats = dir_stats(&game_path);
    if stats.logical_size == 0 {
        return None;
    }

    let is_directstorage = crate::safety::directstorage::is_directstorage_game(&game_path);

    Some(GameInfo {
        name,
        path: game_path,
        platform,
        size_bytes: stats.logical_size,
        compressed_size: if stats.is_compressed {
            Some(stats.physical_size)
        } else {
            None
        },
        is_compressed: stats.is_compressed,
        is_directstorage,
        excluded: false,
        last_played: None,
    })
}

/// Scan a directory's immediate subdirectories for games.
/// Each subdirectory name is used as the game name.
pub fn scan_game_subdirs(games_path: &Path, platform: Platform) -> Vec<GameInfo> {
    let entries = match std::fs::read_dir(games_path) {
        Ok(e) => e,
        Err(e) => {
            log::warn!("Cannot read directory {}: {}", games_path.display(), e);
            return Vec::new();
        }
    };

    entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .filter_map(|e| {
            let game_path = e.path();
            let name = e.file_name().to_string_lossy().into_owned();
            build_game_info(name, game_path, platform)
        })
        .collect()
}

/// Merge new games into existing list, deduplicating by path.
/// Uses a HashSet for O(n) performance instead of O(n^2) linear scan.
pub fn merge_games(existing: &mut Vec<GameInfo>, new_games: Vec<GameInfo>) {
    let mut seen: HashSet<PathDedupKey> = existing.iter().map(|g| dedup_key(&g.path)).collect();
    for game in new_games {
        let key = dedup_key(&game.path);
        if seen.insert(key) {
            existing.push(game);
        }
    }
}

#[cfg(windows)]
fn dedup_key(path: &Path) -> PathDedupKey {
    let mut normalized = path.as_os_str().to_string_lossy().replace('/', "\\");
    while normalized.len() > 3 && normalized.ends_with('\\') {
        normalized.pop();
    }
    normalized.to_ascii_lowercase()
}

#[cfg(not(windows))]
fn dedup_key(path: &Path) -> PathDedupKey {
    path.to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_game(name: &str, path: PathBuf) -> GameInfo {
        GameInfo {
            name: name.to_owned(),
            path,
            platform: Platform::Custom,
            size_bytes: 1,
            compressed_size: None,
            is_compressed: false,
            is_directstorage: false,
            excluded: false,
            last_played: None,
        }
    }

    #[test]
    fn merge_games_dedupes_existing_and_incoming_batch() {
        let shared_path = PathBuf::from(r"C:\Games\Shared");
        let unique_path = PathBuf::from(r"C:\Games\Unique");

        let mut existing = vec![make_game("existing", shared_path.clone())];
        let new_games = vec![
            make_game("duplicate-1", shared_path.clone()),
            make_game("unique", unique_path.clone()),
            make_game("duplicate-2", unique_path.clone()),
        ];

        merge_games(&mut existing, new_games);

        assert_eq!(existing.len(), 2);
        assert_eq!(existing.iter().filter(|g| g.path == shared_path).count(), 1);
        assert_eq!(existing.iter().filter(|g| g.path == unique_path).count(), 1);
    }

    #[cfg(windows)]
    #[test]
    fn merge_games_dedupes_windows_path_case_and_separator_variants() {
        let mut existing = vec![make_game("existing", PathBuf::from(r"C:\Games\Shared"))];
        let new_games = vec![
            make_game("duplicate-variant", PathBuf::from(r"c:/games/shared/")),
            make_game("unique", PathBuf::from(r"C:\Games\Different")),
        ];

        merge_games(&mut existing, new_games);

        assert_eq!(existing.len(), 2);
        assert_eq!(
            existing
                .iter()
                .filter(|g| dedup_key(&g.path) == dedup_key(Path::new(r"C:\Games\Shared")))
                .count(),
            1
        );
    }
}
