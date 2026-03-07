use std::ffi::OsString;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::Path;
use std::time::UNIX_EPOCH;

#[cfg(windows)]
use std::os::windows::ffi::OsStrExt;

#[cfg(windows)]
use windows::core::PCWSTR;
#[cfg(windows)]
use windows::Win32::Storage::FileSystem::{
    MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
};

/// Convert a `u64` parallelism override from the FRB API to a `usize`.
/// Logs a warning and returns `None` if the value exceeds platform `usize`.
pub fn io_parallelism_override_to_usize(value: Option<u64>) -> Option<usize> {
    value.and_then(|v| match usize::try_from(v) {
        Ok(n) => Some(n),
        Err(_) => {
            log::warn!(
                "Ignoring io_parallelism_override={} because it exceeds platform usize",
                v
            );
            None
        }
    })
}

/// Current time as milliseconds since Unix epoch.
pub fn unix_now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Normalize a filesystem path for use as a case-insensitive lookup key.
///
/// On Windows: forward slashes → backslashes, strip trailing separator
/// (preserving drive root like `C:\`), lowercase.
pub fn normalize_path_key(path: &Path) -> String {
    #[cfg(windows)]
    {
        let mut normalized = path.as_os_str().to_string_lossy().replace('/', "\\");
        while normalized.len() > 3 && normalized.ends_with('\\') {
            normalized.pop();
        }
        normalized.to_ascii_lowercase()
    }

    #[cfg(not(windows))]
    {
        path.to_string_lossy().into_owned()
    }
}

/// Write a file via a sibling temp file and atomic replace where supported.
pub fn atomic_write(path: &Path, contents: &[u8]) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "path has no parent"))?;
    fs::create_dir_all(parent)?;

    let file_name = path.file_name().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "path has no terminal file name",
        )
    })?;
    let temp_name = OsString::from(format!(
        ".{}.tmp-{}-{}",
        file_name.to_string_lossy(),
        std::process::id(),
        unix_now_ms()
    ));
    let temp_path = parent.join(temp_name);

    let write_result = (|| -> io::Result<()> {
        let mut temp_file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temp_path)?;
        temp_file.write_all(contents)?;
        temp_file.sync_all()?;
        drop(temp_file);
        replace_file(&temp_path, path)
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }

    write_result
}

#[cfg(windows)]
fn replace_file(source: &Path, destination: &Path) -> io::Result<()> {
    let source_wide: Vec<u16> = source
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let destination_wide: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();

    unsafe {
        MoveFileExW(
            PCWSTR(source_wide.as_ptr()),
            PCWSTR(destination_wide.as_ptr()),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    }
    .map_err(io::Error::other)
}

#[cfg(not(windows))]
fn replace_file(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}
