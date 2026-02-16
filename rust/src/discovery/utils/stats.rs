use std::path::Path;

use walkdir::WalkDir;

const QUICK_SCAN_MAX_DEPTH: usize = 3;
const QUICK_SCAN_MAX_FILES: usize = 256;

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
    let mut logical_size: u64 = 0;
    let mut physical_size: u64 = 0;
    let mut found_compressed = false;

    for entry in WalkDir::new(path)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        // Query metadata once and reuse (avoids double query: file_type() + metadata())
        let Ok(metadata) = entry.metadata() else {
            continue;
        };

        if !metadata.is_file() {
            continue;
        }

        let logical = metadata.len();
        logical_size += logical;

        let physical = crate::compression::wof::get_physical_size(entry.path()).unwrap_or(logical);

        physical_size += physical;

        if !found_compressed && logical >= 4096 && physical < logical {
            found_compressed = true;
        }
    }

    let is_compressed = found_compressed || (logical_size > 0 && physical_size < logical_size);

    DirStats {
        logical_size,
        physical_size,
        is_compressed,
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

/// Fast sampling pass for quick discovery mode.
/// Uses bounded depth/file count and avoids expensive compressed-size checks.
pub fn dir_stats_quick(path: &Path) -> DirStats {
    let mut logical_size: u64 = 0;
    let mut files_seen: usize = 0;

    for entry in WalkDir::new(path)
        .max_depth(QUICK_SCAN_MAX_DEPTH)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
    {
        if files_seen >= QUICK_SCAN_MAX_FILES {
            break;
        }
        if let Ok(metadata) = entry.metadata() {
            logical_size = logical_size.saturating_add(metadata.len());
            files_seen += 1;
        }
    }

    DirStats {
        logical_size,
        physical_size: logical_size,
        is_compressed: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quick_stats_detect_non_empty_folder() {
        let dir = tempfile::TempDir::new().unwrap();
        std::fs::write(dir.path().join("test.bin"), b"abcdef").unwrap();
        let stats = dir_stats_quick(dir.path());
        assert!(stats.logical_size > 0);
    }
}
