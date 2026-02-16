use std::collections::HashSet;
use std::path::Path;
#[cfg(not(windows))]
use std::path::PathBuf;

use crate::discovery::cache;
use crate::discovery::platform::GameInfo;

#[cfg(windows)]
type PathDedupKey = String;
#[cfg(not(windows))]
type PathDedupKey = PathBuf;

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
    cache::normalize_path_key(path)
}

#[cfg(not(windows))]
fn dedup_key(path: &Path) -> PathDedupKey {
    path.to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    use crate::discovery::platform::Platform;

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
