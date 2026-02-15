use std::path::PathBuf;

/// Errors that can occur during game discovery scanning.
#[derive(Debug, thiserror::Error)]
pub enum ScanError {
    #[error("permission denied accessing path: {0}")]
    PermissionDenied(PathBuf),

    #[error("path not found: {0}")]
    PathNotFound(PathBuf),

    #[error("failed to parse {file_type}: {message}")]
    ParseError {
        file_type: &'static str,
        message: String,
    },

    #[error("registry error: {0}")]
    Registry(String),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}
