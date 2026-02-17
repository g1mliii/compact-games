//! FRB-compatible type wrappers.
//!
//! Flutter Rust Bridge cannot directly handle `PathBuf`, `Duration`,
//! crossbeam `Receiver`, or trait objects. These thin wrappers use only
//! primitive types that FRB can serialize across the FFI boundary.

use std::time::UNIX_EPOCH;

use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::engine::{CompressionEstimate, CompressionStats};
use crate::compression::error::CompressionError;
use crate::discovery::platform::{GameInfo, Platform};
use crate::progress::tracker::CompressionProgress;
use thiserror::Error;

// ── FRB-compatible game info ──────────────────────────────────────────

/// Game information with String paths and i64 timestamps for FRB.
#[derive(Debug, Clone)]
pub struct FrbGameInfo {
    pub name: String,
    pub path: String,
    pub platform: FrbPlatform,
    pub size_bytes: u64,
    pub compressed_size: Option<u64>,
    pub is_compressed: bool,
    pub is_directstorage: bool,
    pub excluded: bool,
    pub last_played: Option<i64>,
}

impl From<GameInfo> for FrbGameInfo {
    fn from(g: GameInfo) -> Self {
        Self {
            name: g.name,
            path: g.path.to_string_lossy().into_owned(),
            platform: g.platform.into(),
            size_bytes: g.size_bytes,
            compressed_size: g.compressed_size,
            is_compressed: g.is_compressed,
            is_directstorage: g.is_directstorage,
            excluded: g.excluded,
            last_played: g.last_played.and_then(|t| {
                t.duration_since(UNIX_EPOCH)
                    .ok()
                    .map(|d| d.as_millis() as i64)
            }),
        }
    }
}

// ── Platform enum ─────────────────────────────────────────────────────

/// Mirror of `Platform` for FRB (generates Dart enum automatically).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrbPlatform {
    Steam,
    EpicGames,
    GogGalaxy,
    UbisoftConnect,
    EaApp,
    BattleNet,
    XboxGamePass,
    Custom,
}

impl From<Platform> for FrbPlatform {
    fn from(p: Platform) -> Self {
        match p {
            Platform::Steam => Self::Steam,
            Platform::EpicGames => Self::EpicGames,
            Platform::GogGalaxy => Self::GogGalaxy,
            Platform::UbisoftConnect => Self::UbisoftConnect,
            Platform::EaApp => Self::EaApp,
            Platform::BattleNet => Self::BattleNet,
            Platform::XboxGamePass => Self::XboxGamePass,
            Platform::Custom => Self::Custom,
        }
    }
}

impl From<FrbPlatform> for Platform {
    fn from(p: FrbPlatform) -> Self {
        match p {
            FrbPlatform::Steam => Self::Steam,
            FrbPlatform::EpicGames => Self::EpicGames,
            FrbPlatform::GogGalaxy => Self::GogGalaxy,
            FrbPlatform::UbisoftConnect => Self::UbisoftConnect,
            FrbPlatform::EaApp => Self::EaApp,
            FrbPlatform::BattleNet => Self::BattleNet,
            FrbPlatform::XboxGamePass => Self::XboxGamePass,
            FrbPlatform::Custom => Self::Custom,
        }
    }
}

// ── Compression algorithm ─────────────────────────────────────────────

/// Mirror of `CompressionAlgorithm` for FRB.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrbCompressionAlgorithm {
    Xpress4K,
    Xpress8K,
    Xpress16K,
    Lzx,
}

impl From<FrbCompressionAlgorithm> for CompressionAlgorithm {
    fn from(a: FrbCompressionAlgorithm) -> Self {
        match a {
            FrbCompressionAlgorithm::Xpress4K => Self::Xpress4K,
            FrbCompressionAlgorithm::Xpress8K => Self::Xpress8K,
            FrbCompressionAlgorithm::Xpress16K => Self::Xpress16K,
            FrbCompressionAlgorithm::Lzx => Self::Lzx,
        }
    }
}

// ── Progress snapshot ─────────────────────────────────────────────────

/// FRB-compatible progress (Duration → i64 millis).
#[derive(Debug, Clone)]
pub struct FrbCompressionProgress {
    pub game_name: String,
    pub files_total: u64,
    pub files_processed: u64,
    pub bytes_original: u64,
    pub bytes_compressed: u64,
    pub bytes_saved: u64,
    pub estimated_time_remaining_ms: Option<i64>,
    pub is_complete: bool,
}

impl From<CompressionProgress> for FrbCompressionProgress {
    fn from(p: CompressionProgress) -> Self {
        Self {
            game_name: p.game_name.to_string(),
            files_total: p.files_total,
            files_processed: p.files_processed,
            bytes_original: p.bytes_original,
            bytes_compressed: p.bytes_compressed,
            bytes_saved: p.bytes_saved,
            estimated_time_remaining_ms: p.estimated_time_remaining.map(|d| d.as_millis() as i64),
            is_complete: p.is_complete,
        }
    }
}

// ── Compression stats ─────────────────────────────────────────────────

/// FRB-compatible compression result stats.
#[derive(Debug, Clone)]
pub struct FrbCompressionStats {
    pub original_bytes: u64,
    pub compressed_bytes: u64,
    pub files_processed: u64,
    pub files_skipped: u64,
    pub duration_ms: u64,
}

impl From<CompressionStats> for FrbCompressionStats {
    fn from(s: CompressionStats) -> Self {
        Self {
            original_bytes: s.original_bytes,
            compressed_bytes: s.compressed_bytes,
            files_processed: s.files_processed,
            files_skipped: s.files_skipped,
            duration_ms: s.duration_ms,
        }
    }
}

/// FRB-compatible compression estimate for pre-flight UX.
#[derive(Debug, Clone)]
pub struct FrbCompressionEstimate {
    pub scanned_files: u64,
    pub sampled_bytes: u64,
    pub estimated_compressed_bytes: u64,
    pub estimated_saved_bytes: u64,
    pub estimated_savings_ratio: f64,
    pub artwork_candidate_path: Option<String>,
    pub executable_candidate_path: Option<String>,
}

impl From<CompressionEstimate> for FrbCompressionEstimate {
    fn from(e: CompressionEstimate) -> Self {
        Self {
            scanned_files: e.scanned_files,
            sampled_bytes: e.sampled_bytes,
            estimated_compressed_bytes: e.estimated_compressed_bytes(),
            estimated_saved_bytes: e.estimated_saved_bytes,
            estimated_savings_ratio: e.estimated_savings_ratio(),
            artwork_candidate_path: e
                .artwork_candidate_path
                .as_ref()
                .map(|p| p.to_string_lossy().into_owned()),
            executable_candidate_path: e
                .executable_candidate_path
                .as_ref()
                .map(|p| p.to_string_lossy().into_owned()),
        }
    }
}

// ── Compression error ─────────────────────────────────────────────────

/// FRB-compatible error enum.
#[derive(Debug)]
pub enum FrbCompressionError {
    LockedFile { path: String },
    PermissionDenied { path: String },
    DiskFull,
    PathNotFound { path: String },
    NotADirectory { path: String },
    GameRunning,
    DirectStorageDetected,
    WofApiError { message: String },
    IoError { message: String },
    Cancelled,
}

impl From<CompressionError> for FrbCompressionError {
    fn from(e: CompressionError) -> Self {
        match e {
            CompressionError::LockedFile { path } => Self::LockedFile {
                path: path.to_string_lossy().into_owned(),
            },
            CompressionError::PermissionDenied { path, .. } => Self::PermissionDenied {
                path: path.to_string_lossy().into_owned(),
            },
            CompressionError::DiskFull => Self::DiskFull,
            CompressionError::PathNotFound(path) => Self::PathNotFound {
                path: path.to_string_lossy().into_owned(),
            },
            CompressionError::NotADirectory(path) => Self::NotADirectory {
                path: path.to_string_lossy().into_owned(),
            },
            CompressionError::GameRunning => Self::GameRunning,
            CompressionError::DirectStorageDetected => Self::DirectStorageDetected,
            CompressionError::WofApiError { message } => Self::WofApiError { message },
            CompressionError::Io { source } => Self::IoError {
                message: source.to_string(),
            },
            CompressionError::Cancelled => Self::Cancelled,
        }
    }
}

impl std::fmt::Display for FrbCompressionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::LockedFile { path } => write!(f, "File locked: {path}"),
            Self::PermissionDenied { path } => write!(f, "Permission denied: {path}"),
            Self::DiskFull => write!(f, "Not enough disk space"),
            Self::PathNotFound { path } => write!(f, "Path not found: {path}"),
            Self::NotADirectory { path } => write!(f, "Not a directory: {path}"),
            Self::GameRunning => write!(f, "Game is currently running"),
            Self::DirectStorageDetected => write!(f, "DirectStorage game detected"),
            Self::WofApiError { message } => write!(f, "WOF error: {message}"),
            Self::IoError { message } => write!(f, "I/O error: {message}"),
            Self::Cancelled => write!(f, "Operation cancelled"),
        }
    }
}

/// FRB-compatible discovery errors.
#[derive(Debug, Error)]
pub enum FrbDiscoveryError {
    #[error("Discovery failed: {message}")]
    DiscoveryFailed { message: String },
    #[error("Custom scan failed for '{path}': {message}")]
    CustomScanFailed { path: String, message: String },
    #[error("Invalid custom scan path: {message}")]
    InvalidPath { message: String },
}

/// FRB-compatible automation lifecycle errors.
#[derive(Debug, Error)]
pub enum FrbAutomationError {
    #[error("Auto-compression is already running")]
    AlreadyRunning,
    #[error("Auto-compression is not running")]
    NotRunning,
    #[error("Failed to start auto-compression: {message}")]
    StartFailed { message: String },
    #[error("Failed to stop auto-compression: {message}")]
    StopFailed { message: String },
}
