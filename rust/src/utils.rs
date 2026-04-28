use std::ffi::OsString;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::UNIX_EPOCH;

#[cfg(windows)]
use std::os::windows::ffi::OsStrExt;
#[cfg(windows)]
use std::time::Duration;

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

/// Encode a `&str` as a null-terminated UTF-16 buffer for Win32 PCWSTR APIs.
#[cfg(windows)]
pub fn wide_null_str(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
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
    static ATOMIC_WRITE_SEQ: AtomicU64 = AtomicU64::new(0);

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
    let sequence = ATOMIC_WRITE_SEQ.fetch_add(1, Ordering::Relaxed);
    let temp_name = OsString::from(format!(
        ".{}.tmp-{}-{}-{}",
        file_name.to_string_lossy(),
        std::process::id(),
        unix_now_ms(),
        sequence,
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

    const MAX_ATTEMPTS: usize = 8;

    for attempt in 0..MAX_ATTEMPTS {
        match unsafe {
            MoveFileExW(
                PCWSTR(source_wide.as_ptr()),
                PCWSTR(destination_wide.as_ptr()),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        } {
            Ok(()) => return Ok(()),
            Err(error) => {
                let code = windows_error_code(&error);
                let retryable = matches!(code, Some(5 | 32 | 33));
                if retryable && attempt + 1 < MAX_ATTEMPTS {
                    std::thread::sleep(Duration::from_millis(2_u64 << attempt));
                    continue;
                }
                return Err(windows_error_to_io(error));
            }
        }
    }

    Err(io::Error::other("unreachable replace_file retry state"))
}

#[cfg(not(windows))]
fn replace_file(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}

#[cfg(windows)]
fn windows_error_code(error: &windows::core::Error) -> Option<i32> {
    let hresult = error.code().0 as u32;
    if (hresult & 0xFFFF0000) == 0x80070000 {
        Some((hresult & 0xFFFF) as i32)
    } else {
        None
    }
}

#[cfg(windows)]
fn windows_error_to_io(error: windows::core::Error) -> io::Error {
    match windows_error_code(&error) {
        Some(code) => io::Error::from_raw_os_error(code),
        None => io::Error::other(error),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Barrier};
    use std::thread;

    use super::*;

    #[test]
    fn atomic_write_allows_overlapping_writes_to_same_target() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("shared.json");
        let writer_count = 8usize;
        let barrier = Arc::new(Barrier::new(writer_count));

        let handles: Vec<_> = (0..writer_count)
            .map(|i| {
                let barrier = Arc::clone(&barrier);
                let path = path.clone();
                thread::spawn(move || {
                    let payload = format!(r#"{{"writer":{i}}}"#);
                    barrier.wait();
                    atomic_write(&path, payload.as_bytes())
                })
            })
            .collect();

        for handle in handles {
            handle.join().unwrap().unwrap();
        }

        let final_contents = fs::read_to_string(&path).unwrap();
        assert!(
            (0..writer_count).any(|i| final_contents == format!(r#"{{"writer":{i}}}"#)),
            "final file should contain one complete writer payload, got {final_contents}"
        );
    }
}
