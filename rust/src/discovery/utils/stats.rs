use std::path::Path;

use walkdir::WalkDir;

const QUICK_SCAN_MAX_DEPTH: usize = 3;
const QUICK_SCAN_MAX_FILES: usize = 256;
const FULL_SCAN_MAX_FILES: usize = 250_000;

/// Directory size statistics collected in a single walk.
pub struct DirStats {
    pub logical_size: u64,
    pub physical_size: u64,
    pub is_compressed: bool,
    pub scan_limit_reached: bool,
}

/// Collect logical size, physical (compressed) size, and compression status
/// in a single directory walk. Avoids the 3-pass pattern of calling
/// dir_size + is_dir_compressed + dir_compressed_size separately.
#[cfg(windows)]
pub fn dir_stats(path: &Path) -> DirStats {
    let mut logical_size: u64 = 0;
    let mut physical_size: u64 = 0;
    let mut found_compressed = false;
    let mut files_seen: usize = 0;
    let mut scan_limit_reached = false;

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
        if files_seen >= FULL_SCAN_MAX_FILES {
            scan_limit_reached = true;
            break;
        }
        files_seen += 1;

        let logical = metadata.len();
        logical_size += logical;

        // WOF-compressed files do not reliably expose shrinkage through file
        // attributes, so full discovery must query the physical size.
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
        scan_limit_reached,
    }
}

#[cfg(not(windows))]
pub fn dir_stats(path: &Path) -> DirStats {
    let mut logical_size: u64 = 0;
    let mut files_seen: usize = 0;
    let mut scan_limit_reached = false;
    for entry in WalkDir::new(path)
        .follow_links(false)
        .into_iter()
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.file_type().is_file())
    {
        if files_seen >= FULL_SCAN_MAX_FILES {
            scan_limit_reached = true;
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
        scan_limit_reached,
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
        scan_limit_reached: false,
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

    #[cfg(windows)]
    #[test]
    fn dir_stats_detects_wof_compressed_files_after_app_compression() {
        use crate::compression::algorithm::CompressionAlgorithm;
        use crate::compression::wof::{self, CompressFileResult};

        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("zeros.bin");
        std::fs::write(&path, vec![0_u8; 1024 * 1024]).unwrap();

        let result = wof::wof_compress_file(&path, CompressionAlgorithm::Xpress4K).unwrap();
        assert_eq!(result, CompressFileResult::Compressed);
        assert!(wof::get_physical_size(&path).unwrap() < std::fs::metadata(&path).unwrap().len());

        let stats = dir_stats(dir.path());
        assert_eq!(stats.logical_size, 1024 * 1024);
        assert!(
            stats.physical_size < stats.logical_size,
            "full discovery must preserve WOF physical size after app compression"
        );
        assert!(stats.is_compressed);
    }
}
