use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use walkdir::{DirEntry, WalkDir};

pub(super) fn safe_file_iter(
    folder: &Path,
    canonical_root: PathBuf,
) -> impl Iterator<Item = DirEntry> + '_ {
    let parent_path_safety_cache = RefCell::new(HashMap::<PathBuf, bool>::new());

    WalkDir::new(folder)
        .follow_links(false)
        .into_iter()
        .filter_map(|entry| match entry {
            Ok(entry) => Some(entry),
            Err(e) => {
                log::debug!(
                    "Skipping unreadable entry under {} during compression scan: {e}",
                    folder.display()
                );
                None
            }
        })
        .filter(|entry| entry.file_type().is_file())
        .filter(move |entry| is_safe_file_entry(entry, &canonical_root, &parent_path_safety_cache))
}

fn is_safe_file_entry(
    entry: &DirEntry,
    canonical_root: &Path,
    parent_cache: &RefCell<HashMap<PathBuf, bool>>,
) -> bool {
    if entry.path_is_symlink() {
        log::warn!(
            "Skipping symlink entry in compression path scan: {}",
            entry.path().display()
        );
        return false;
    }

    if !is_parent_within_root(entry.path(), canonical_root, parent_cache) {
        log::warn!(
            "Skipping file outside canonical compression root: {}",
            entry.path().display()
        );
        return false;
    }

    if let Err(e) = entry.metadata() {
        log::debug!(
            "Skipping file with unreadable metadata during compression scan {}: {e}",
            entry.path().display()
        );
        return false;
    }

    true
}

fn is_parent_within_root(
    file_path: &Path,
    canonical_root: &Path,
    parent_cache: &RefCell<HashMap<PathBuf, bool>>,
) -> bool {
    let Some(parent) = file_path.parent() else {
        return false;
    };

    if let Some(cached) = { parent_cache.borrow().get(parent).copied() } {
        return cached;
    }

    let is_within_root = fs::canonicalize(parent)
        .map(|canonical_parent| canonical_parent.starts_with(canonical_root))
        .unwrap_or(false);
    parent_cache
        .borrow_mut()
        .insert(parent.to_path_buf(), is_within_root);
    is_within_root
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn parent_containment_allows_in_root_path() {
        let dir = TempDir::new().expect("temp dir");
        let nested = dir.path().join("nested");
        fs::create_dir_all(&nested).expect("nested dir");
        let file = nested.join("game.exe");
        fs::write(&file, b"x").expect("fixture file");

        let canonical_root = fs::canonicalize(dir.path()).expect("canonical root");
        let cache = RefCell::new(HashMap::<PathBuf, bool>::new());
        assert!(is_parent_within_root(&file, &canonical_root, &cache));
    }

    #[test]
    fn parent_containment_rejects_outside_root_path() {
        let root = TempDir::new().expect("root temp dir");
        let outside = TempDir::new().expect("outside temp dir");
        let outside_file = outside.path().join("outside.exe");
        fs::write(&outside_file, b"x").expect("outside file");

        let canonical_root = fs::canonicalize(root.path()).expect("canonical root");
        let cache = RefCell::new(HashMap::<PathBuf, bool>::new());
        assert!(!is_parent_within_root(
            &outside_file,
            &canonical_root,
            &cache
        ));
    }
}
