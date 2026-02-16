use std::collections::HashMap;
use std::path::Path;
use std::sync::{LazyLock, OnceLock, RwLock};

use sysinfo::{DiskKind, Disks};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StorageClass {
    Hdd,
    Ssd,
    Unknown,
}

static STORAGE_CACHE: LazyLock<RwLock<HashMap<String, StorageClass>>> =
    LazyLock::new(|| RwLock::new(HashMap::new()));
static DISK_KIND_SUMMARY_CACHE: OnceLock<(bool, bool)> = OnceLock::new();

pub fn storage_class_for_path(path: &Path) -> StorageClass {
    let cache_key = volume_cache_key(path);

    if let Some(class) = with_cache_read(|cache| cache.get(&cache_key).copied()) {
        return class;
    }

    let class = detect_storage_class(path);
    with_cache_write(|cache| {
        cache.insert(cache_key, class);
    });
    class
}

pub fn has_any_hdd_disk() -> bool {
    disk_kind_summary().0
}

pub fn has_any_ssd_disk() -> bool {
    disk_kind_summary().1
}

fn disk_kind_summary() -> (bool, bool) {
    *DISK_KIND_SUMMARY_CACHE.get_or_init(|| {
        let disks = Disks::new_with_refreshed_list();
        let mut has_hdd = false;
        let mut has_ssd = false;
        for disk in disks.list() {
            match disk.kind() {
                DiskKind::HDD => has_hdd = true,
                DiskKind::SSD => has_ssd = true,
                DiskKind::Unknown(_) => {}
            }
            if has_hdd && has_ssd {
                break;
            }
        }
        (has_hdd, has_ssd)
    })
}

fn detect_storage_class(path: &Path) -> StorageClass {
    let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let path_norm = normalize_for_match(&canonical);

    let disks = Disks::new_with_refreshed_list();
    let mut best_match_len = 0usize;
    let mut best_class = StorageClass::Unknown;

    for disk in disks.list() {
        let mount_norm = normalize_for_match(disk.mount_point());
        if path_norm.starts_with(&mount_norm) && mount_norm.len() > best_match_len {
            best_match_len = mount_norm.len();
            best_class = disk_kind_to_class(disk.kind());
        }
    }

    best_class
}

fn disk_kind_to_class(kind: DiskKind) -> StorageClass {
    match kind {
        DiskKind::HDD => StorageClass::Hdd,
        DiskKind::SSD => StorageClass::Ssd,
        DiskKind::Unknown(_) => StorageClass::Unknown,
    }
}

fn volume_cache_key(path: &Path) -> String {
    #[cfg(windows)]
    {
        let path_str = path.as_os_str().to_string_lossy();
        let bytes = path_str.as_bytes();
        if bytes.len() >= 2 && bytes[1] == b':' {
            let drive = path_str[..2].to_ascii_lowercase();
            return format!("{drive}\\");
        }
    }

    let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let mut components = canonical.components();
    match components.next() {
        Some(root) => root.as_os_str().to_string_lossy().into_owned(),
        None => canonical.to_string_lossy().into_owned(),
    }
}

fn normalize_for_match(path: &Path) -> String {
    #[cfg(windows)]
    {
        path.as_os_str()
            .to_string_lossy()
            .replace('/', "\\")
            .to_ascii_lowercase()
    }

    #[cfg(not(windows))]
    {
        path.to_string_lossy().into_owned()
    }
}

fn with_cache_read<R>(f: impl FnOnce(&HashMap<String, StorageClass>) -> R) -> R {
    match STORAGE_CACHE.read() {
        Ok(guard) => f(&guard),
        Err(poisoned) => {
            log::warn!("Storage cache lock poisoned (read); recovering");
            let guard = poisoned.into_inner();
            f(&guard)
        }
    }
}

fn with_cache_write<R>(f: impl FnOnce(&mut HashMap<String, StorageClass>) -> R) -> R {
    match STORAGE_CACHE.write() {
        Ok(mut guard) => f(&mut guard),
        Err(poisoned) => {
            log::warn!("Storage cache lock poisoned (write); recovering");
            let mut guard = poisoned.into_inner();
            f(&mut guard)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn storage_class_detection_is_stable_for_same_path() {
        let cwd = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
        let first = storage_class_for_path(&cwd);
        let second = storage_class_for_path(&cwd);
        assert_eq!(first, second);
    }
}
