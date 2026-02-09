use std::path::PathBuf;
use thiserror::Error;

/// Errors that can occur during compression or decompression.
#[derive(Debug, Error)]
pub enum CompressionError {
    #[error("file is locked by another process: {path}")]
    LockedFile { path: PathBuf },

    #[error("insufficient permissions for {path}: {source}")]
    PermissionDenied {
        path: PathBuf,
        source: std::io::Error,
    },

    #[error("not enough disk space to complete operation")]
    DiskFull,

    #[error("path does not exist: {0}")]
    PathNotFound(PathBuf),

    #[error("path is not a directory: {0}")]
    NotADirectory(PathBuf),

    #[error("compression aborted: game is running")]
    GameRunning,

    #[error("compression aborted: DirectStorage game detected")]
    DirectStorageDetected,

    #[error("WOF API error: {message}")]
    WofApiError { message: String },

    #[error("I/O error: {source}")]
    Io {
        #[from]
        source: std::io::Error,
    },

    #[error("operation cancelled by user")]
    Cancelled,
}
