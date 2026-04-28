//! Windows shell helpers exposed to Flutter.

use std::path::Path;

use thiserror::Error;

/// Errors returned by shell integration helpers.
#[derive(Debug, Error)]
pub enum FrbShellError {
    #[error("Shortcut path is invalid: {message}")]
    InvalidPath { message: String },
    #[error("Shortcut resolution failed for '{path}': {message}")]
    ResolutionFailed { path: String, message: String },
}

/// Resolve a Windows `.lnk` file to its target path.
pub fn resolve_shortcut_target(shortcut_path: String) -> Result<String, FrbShellError> {
    let trimmed = shortcut_path.trim();
    if trimmed.is_empty() {
        return Err(FrbShellError::InvalidPath {
            message: "path cannot be empty".to_owned(),
        });
    }
    if !trimmed.to_ascii_lowercase().ends_with(".lnk") {
        return Err(FrbShellError::InvalidPath {
            message: "path must end with .lnk".to_owned(),
        });
    }
    if !Path::new(trimmed).is_file() {
        return Err(FrbShellError::InvalidPath {
            message: format!("'{}' is not a file", trimmed),
        });
    }

    platform::resolve_shortcut_target(trimmed).map_err(|message| FrbShellError::ResolutionFailed {
        path: trimmed.to_owned(),
        message,
    })
}

#[cfg(windows)]
mod platform {
    use windows::core::{Interface, PCWSTR};
    use windows::Win32::Storage::FileSystem::WIN32_FIND_DATAW;
    use windows::Win32::System::Com::{
        CoCreateInstance, CoInitializeEx, CoUninitialize, IPersistFile, CLSCTX_INPROC_SERVER,
        COINIT_APARTMENTTHREADED, COINIT_DISABLE_OLE1DDE, STGM_READ,
    };
    use windows::Win32::UI::Shell::{IShellLinkW, ShellLink, SLGP_UNCPRIORITY};

    use crate::utils::wide_null_str;

    /// Long-path limit on modern Windows. The classic 260-char `MAX_PATH`
    /// silently truncates targets that point inside long-path-aware game
    /// installs (e.g. Steam libraries with deep mod folders, `\\?\` paths).
    const MAX_LONG_PATH_CHARS: usize = 32_768;

    /// Resolve a `.lnk` to its target path.
    ///
    /// Thread-safety invariant: this function is synchronous from start to
    /// finish on a single thread. `ComApartment` initializes COM on the
    /// calling thread and `Drop` uninitializes it on the same thread. Do
    /// not refactor any part of this function to `await` or to hand
    /// `IShellLinkW`/`IPersistFile` to another thread — both interfaces
    /// are apartment-bound and will misbehave if marshalled implicitly.
    pub(super) fn resolve_shortcut_target(shortcut_path: &str) -> Result<String, String> {
        unsafe {
            let _com = ComApartment::init()?;
            let shell_link: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER)
                .map_err(|e| format!("create ShellLink failed: {e}"))?;
            let persist_file: IPersistFile = shell_link
                .cast()
                .map_err(|e| format!("query IPersistFile failed: {e}"))?;

            let wide_shortcut = wide_null_str(shortcut_path);
            persist_file
                .Load(PCWSTR(wide_shortcut.as_ptr()), STGM_READ)
                .map_err(|e| format!("load shortcut failed: {e}"))?;

            let mut target = vec![0u16; MAX_LONG_PATH_CHARS];
            let mut find_data = WIN32_FIND_DATAW::default();
            shell_link
                .GetPath(&mut target, &mut find_data, SLGP_UNCPRIORITY.0 as u32)
                .map_err(|e| format!("read shortcut target failed: {e}"))?;

            let len = target.iter().position(|c| *c == 0).unwrap_or(target.len());
            if len == 0 {
                return Err("shortcut target is empty".to_owned());
            }
            String::from_utf16(&target[..len])
                .map_err(|e| format!("shortcut target is not valid UTF-16: {e}"))
        }
    }

    struct ComApartment;

    impl ComApartment {
        unsafe fn init() -> Result<Self, String> {
            let hr = CoInitializeEx(None, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
            if hr.is_err() {
                return Err(format!("COM initialization failed: {hr:?}"));
            }
            Ok(Self)
        }
    }

    impl Drop for ComApartment {
        fn drop(&mut self) {
            unsafe {
                CoUninitialize();
            }
        }
    }
}

#[cfg(not(windows))]
mod platform {
    pub(super) fn resolve_shortcut_target(_shortcut_path: &str) -> Result<String, String> {
        Err("shortcut resolution is only available on Windows".to_owned())
    }
}

#[cfg(test)]
mod tests {
    use super::resolve_shortcut_target;

    #[test]
    fn rejects_empty_shortcut_path() {
        assert!(resolve_shortcut_target("  ".to_owned()).is_err());
    }

    #[test]
    fn rejects_non_shortcut_path() {
        assert!(resolve_shortcut_target(r"C:\Games\example.exe".to_owned()).is_err());
    }
}
