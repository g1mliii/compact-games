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
        // SAFETY: Calling GetLastError immediately after the Win32 API call is required
        // to detect whether `u32::MAX` from GetCompressedFileSizeW is an error.
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
