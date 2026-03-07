use std::path::Path;
use std::time::UNIX_EPOCH;

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
