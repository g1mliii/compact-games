use std::path::Path;

use walkdir::WalkDir;

const QUICK_SCAN_MAX_DEPTH: usize = 3;
const QUICK_SCAN_MAX_FILES: usize = 256;

// Windows file attributes that signal a file *might* be smaller on disk than
// its logical size. Any other file (the overwhelming majority on a fresh game
// install) has physical == logical, so we can skip the GetCompressedFileSizeW
// syscall entirely.
//   COMPRESSED   (0x0800): NTFS LZNT1 compression
//   SPARSE_FILE  (0x0200): sparse file (holes don't consume disk)
//   REPARSE_POINT(0x0400): includes WOF-backed files (our own compression)
#[cfg(windows)]
const POSSIBLY_SHRUNK_ATTRS: u32 = 0x0800 | 0x0200 | 0x0400;

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
    use std::os::windows::fs::MetadataExt;

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

        // Skip GetCompressedFileSizeW unless the file's attributes hint that
        // it could be smaller on disk. Saves one syscall per file across the
        // huge majority of game contents.
        let physical = if metadata.file_attributes() & POSSIBLY_SHRUNK_ATTRS == 0 {
            logical
        } else {
            crate::compression::wof::get_physical_size(entry.path()).unwrap_or(logical)
        };

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

    #[cfg(windows)]
    #[test]
    fn dir_stats_plain_files_report_physical_equal_to_logical() {
        let dir = tempfile::TempDir::new().unwrap();
        // Mix of sizes so we cover both >=4096 and <4096 branches without
        // touching any compression-related attributes.
        std::fs::write(dir.path().join("small.bin"), vec![0_u8; 1024]).unwrap();
        std::fs::write(dir.path().join("medium.bin"), vec![0_u8; 8 * 1024]).unwrap();
        std::fs::write(dir.path().join("large.bin"), vec![0_u8; 64 * 1024]).unwrap();

        let stats = dir_stats(dir.path());
        let expected = 1024 + 8 * 1024 + 64 * 1024;
        assert_eq!(stats.logical_size, expected as u64);
        assert_eq!(stats.physical_size, expected as u64);
        assert!(!stats.is_compressed);
    }
}
