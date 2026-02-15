//! Safe Rust wrapper over Windows Overlay Filter (WOF) DeviceIoControl calls.
//!
//! Isolates all `unsafe` Windows FFI behind safe public functions.
//! Every public function returns `Result<T, CompressionError>`.

use std::fs::{File, OpenOptions};
use std::os::windows::ffi::OsStrExt;
use std::os::windows::fs::OpenOptionsExt;
use std::os::windows::io::AsRawHandle;
use std::path::Path;

use windows::core::PCWSTR;
use windows::Win32::Foundation::HANDLE;
use windows::Win32::Storage::FileSystem::GetCompressedFileSizeW;
use windows::Win32::System::Ioctl::{
    FSCTL_DELETE_EXTERNAL_BACKING, FSCTL_GET_EXTERNAL_BACKING, FSCTL_SET_EXTERNAL_BACKING,
};
use windows::Win32::System::IO::DeviceIoControl;

use super::algorithm::CompressionAlgorithm;
use super::error::CompressionError;

const WOF_CURRENT_VERSION: u32 = 1;
const WOF_PROVIDER_FILE: u32 = 2;
const FILE_PROVIDER_CURRENT_VERSION: u32 = 1;

const ERROR_ACCESS_DENIED: u32 = 5;
const ERROR_SHARING_VIOLATION: u32 = 32;
const ERROR_DISK_FULL: u32 = 112;
const ERROR_COMPRESSION_NOT_BENEFICIAL: u32 = 344;
const ERROR_OBJECT_NOT_EXTERNALLY_BACKED: u32 = 342;

// ── FFI structs ──────────────────────────────────────────────────────

#[repr(C)]
struct WofExternalInfo {
    version: u32,
    provider: u32,
}

#[repr(C)]
struct FileProviderExternalInfoV1 {
    version: u32,
    algorithm: u32,
    flags: u32,
}

/// Combined input/output buffer for FSCTL_SET/GET_EXTERNAL_BACKING.
#[repr(C)]
struct WofBackingBuffer {
    wof: WofExternalInfo,
    file: FileProviderExternalInfoV1,
}

/// Outcome of a single-file WOF compression attempt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompressFileResult {
    Compressed,
    NotBeneficial,
}

// ── Public API ───────────────────────────────────────────────────────

/// Apply WOF compression to a single file.
///
/// Returns `Compressed` on success or `NotBeneficial` if the OS
/// determines the file is incompressible (Win32 error 344).
pub fn wof_compress_file(
    path: &Path,
    algorithm: CompressionAlgorithm,
) -> Result<CompressFileResult, CompressionError> {
    let file = open_for_wof(path)?;
    let handle = file_handle(&file);

    let buf = WofBackingBuffer {
        wof: WofExternalInfo {
            version: WOF_CURRENT_VERSION,
            provider: WOF_PROVIDER_FILE,
        },
        file: FileProviderExternalInfoV1 {
            version: FILE_PROVIDER_CURRENT_VERSION,
            algorithm: algorithm.wof_algorithm_id(),
            flags: 0,
        },
    };

    let mut returned: u32 = 0;

    let result = unsafe {
        DeviceIoControl(
            handle,
            FSCTL_SET_EXTERNAL_BACKING,
            Some(std::ptr::addr_of!(buf).cast()),
            std::mem::size_of::<WofBackingBuffer>() as u32,
            None,
            0,
            Some(&mut returned),
            None,
        )
    };

    match result {
        Ok(()) => Ok(CompressFileResult::Compressed),
        Err(e) => {
            let code = win32_code(&e);
            if code == ERROR_COMPRESSION_NOT_BENEFICIAL {
                Ok(CompressFileResult::NotBeneficial)
            } else {
                Err(map_win32(code, path))
            }
        }
    }
}

pub fn wof_decompress_file(path: &Path) -> Result<(), CompressionError> {
    let file = open_for_wof(path)?;
    let handle = file_handle(&file);
    let mut returned: u32 = 0;

    let result = unsafe {
        DeviceIoControl(
            handle,
            FSCTL_DELETE_EXTERNAL_BACKING,
            None,
            0,
            None,
            0,
            Some(&mut returned),
            None,
        )
    };

    match result {
        Ok(()) => Ok(()),
        Err(e) => {
            let code = win32_code(&e);
            match code {
                // File isn't WOF-compressed: silently succeed
                ERROR_OBJECT_NOT_EXTERNALLY_BACKED => Ok(()),
                _ => Err(map_win32(code, path)),
            }
        }
    }
}

pub fn wof_get_compression(path: &Path) -> Result<Option<CompressionAlgorithm>, CompressionError> {
    let file = File::open(path).map_err(|e| map_io(e, path))?;
    let handle = file_handle(&file);

    let mut buf = WofBackingBuffer {
        wof: WofExternalInfo {
            version: 0,
            provider: 0,
        },
        file: FileProviderExternalInfoV1 {
            version: 0,
            algorithm: 0,
            flags: 0,
        },
    };
    let mut returned: u32 = 0;

    let result = unsafe {
        DeviceIoControl(
            handle,
            FSCTL_GET_EXTERNAL_BACKING,
            None,
            0,
            Some(std::ptr::addr_of_mut!(buf).cast()),
            std::mem::size_of::<WofBackingBuffer>() as u32,
            Some(&mut returned),
            None,
        )
    };

    match result {
        Ok(()) if buf.wof.provider == WOF_PROVIDER_FILE => {
            Ok(CompressionAlgorithm::from_wof_id(buf.file.algorithm))
        }
        Ok(()) => Ok(None),
        Err(e) => {
            let code = win32_code(&e);
            // File is not externally backed - not an error
            if code == ERROR_OBJECT_NOT_EXTERNALLY_BACKED {
                Ok(None)
            } else {
                Err(map_win32(code, path))
            }
        }
    }
}

pub fn get_physical_size(path: &Path) -> Result<u64, CompressionError> {
    let wide: Vec<u16> = path
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let mut high: u32 = 0;

    let low = unsafe { GetCompressedFileSizeW(PCWSTR(wide.as_ptr()), Some(&mut high)) };

    if low == u32::MAX {
        let err = std::io::Error::last_os_error();
        if err.raw_os_error().unwrap_or(0) != 0 {
            return Err(map_io(err, path));
        }
    }

    Ok(((high as u64) << 32) | (low as u64))
}

fn open_for_wof(path: &Path) -> Result<File, CompressionError> {
    OpenOptions::new()
        .access_mode(0x0001 | 0x0002)
        .share_mode(0x0001 | 0x0004)
        .open(path)
        .map_err(|e| map_io(e, path))
}

fn file_handle(file: &File) -> HANDLE {
    HANDLE(file.as_raw_handle() as _)
}

fn win32_code(e: &windows::core::Error) -> u32 {
    (e.code().0 & 0xFFFF) as u32
}

fn map_win32(code: u32, path: &Path) -> CompressionError {
    match code {
        ERROR_ACCESS_DENIED => CompressionError::PermissionDenied {
            path: path.to_path_buf(),
            source: std::io::Error::from_raw_os_error(code as i32),
        },
        ERROR_SHARING_VIOLATION => CompressionError::LockedFile {
            path: path.to_path_buf(),
        },
        ERROR_DISK_FULL => CompressionError::DiskFull,
        _ => CompressionError::WofApiError {
            message: format!("Win32 error {code} on {}", path.display()),
        },
    }
}

fn map_io(e: std::io::Error, path: &Path) -> CompressionError {
    match e.raw_os_error() {
        Some(raw) if raw == ERROR_ACCESS_DENIED as i32 => CompressionError::PermissionDenied {
            path: path.to_path_buf(),
            source: e,
        },
        Some(raw) if raw == ERROR_SHARING_VIOLATION as i32 => CompressionError::LockedFile {
            path: path.to_path_buf(),
        },
        _ if e.kind() == std::io::ErrorKind::NotFound => {
            CompressionError::PathNotFound(path.to_path_buf())
        }
        _ if e.kind() == std::io::ErrorKind::PermissionDenied => {
            CompressionError::PermissionDenied {
                path: path.to_path_buf(),
                source: e,
            }
        }
        _ => CompressionError::Io { source: e },
    }
}

// ── Tests ────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn struct_sizes() {
        assert_eq!(std::mem::size_of::<WofExternalInfo>(), 8);
        assert_eq!(std::mem::size_of::<FileProviderExternalInfoV1>(), 12);
        assert_eq!(std::mem::size_of::<WofBackingBuffer>(), 20);
    }

    #[test]
    fn struct_alignment() {
        assert_eq!(std::mem::align_of::<WofBackingBuffer>(), 4);
    }
}
