use std::path::Path;
use std::sync::Arc;

use super::CompressionEngine;
use crate::compression::error::CompressionError;
use crate::safety::directstorage::is_directstorage_game;
use crate::safety::process::ProcessChecker;

#[derive(Clone)]
/// Optional runtime safety integrations used before compression starts.
pub struct SafetyConfig {
    pub process_checker: Arc<ProcessChecker>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum DirectStoragePolicy {
    Block,
    WarnOnly,
}

pub(super) fn run_safety_checks(
    folder: &Path,
    directstorage_policy: DirectStoragePolicy,
    safety: Option<&SafetyConfig>,
) -> Result<(), CompressionError> {
    if is_directstorage_game(folder) {
        if directstorage_policy == DirectStoragePolicy::Block {
            return Err(CompressionError::DirectStorageDetected);
        }
        log::warn!(
            "DirectStorage detected for {}; continuing due to explicit override",
            folder.display()
        );
    }

    if let Some(safety) = safety {
        if safety.process_checker.is_game_running(folder) {
            return Err(CompressionError::GameRunning);
        }
    }

    Ok(())
}

impl CompressionEngine {
    /// Attach optional safety dependencies used by pre-compression checks.
    pub fn with_safety(mut self, config: SafetyConfig) -> Self {
        self.safety = Some(config);
        self
    }

    /// Configure whether DirectStorage detection should hard-block compression.
    ///
    /// `allow = false` (default) keeps the safety block and returns
    /// `CompressionError::DirectStorageDetected` when detection triggers.
    ///
    /// `allow = true` allows compression to continue but emits a warning log.
    /// Callers should require explicit user confirmation before enabling this.
    pub fn with_directstorage_override(mut self, allow: bool) -> Self {
        self.directstorage_policy = if allow {
            DirectStoragePolicy::WarnOnly
        } else {
            DirectStoragePolicy::Block
        };
        self
    }
}
