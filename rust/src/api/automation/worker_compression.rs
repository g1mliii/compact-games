use std::collections::HashSet;
use std::path::{Path, PathBuf};

use crate::automation::scheduler::AutomationJob;
use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::engine::{CancellationToken, CompressionEngine};
use crate::compression::history::{record_compression, CompressionHistoryEntry};
use crate::compression::thread_policy::compute_thread_policy;
use crate::safety::directstorage::is_directstorage_game;
use crate::safety::process::ProcessChecker;

pub(super) enum CompressionResult {
    Success {
        idempotency_key: String,
    },
    Failed {
        idempotency_key: String,
        error: String,
    },
    Skipped {
        idempotency_key: String,
        reason: String,
    },
}

pub(super) struct ActiveCompressionJob {
    pub(super) result_rx: crossbeam_channel::Receiver<CompressionResult>,
    pub(super) cancel_token: CancellationToken,
    worker_handle: Option<std::thread::JoinHandle<()>>,
}

/// Spawn compression on a dedicated thread so auto_loop stays responsive.
pub(super) fn spawn_compression_job(
    job: &AutomationJob,
    process_checker: &ProcessChecker,
    algorithm: CompressionAlgorithm,
    cpu_usage_percent: f32,
    io_parallelism_override: Option<usize>,
    watch_roots: Vec<PathBuf>,
    excluded_paths: HashSet<String>,
) -> ActiveCompressionJob {
    let game_path = job.game_path.clone();
    let game_name = job.game_name.clone();
    let idempotency_key = job.idempotency_key.clone();
    let (result_tx, result_rx) = crossbeam_channel::bounded::<CompressionResult>(1);
    let cancel_token = CancellationToken::new();

    if !is_authorized_game_path(&game_path, &watch_roots, &excluded_paths) {
        log::warn!(
            "Skipping automation job outside configured library roots: {}",
            game_path.display()
        );
        let _ = result_tx.send(CompressionResult::Skipped {
            idempotency_key,
            reason: "Path is outside configured library roots".to_string(),
        });
        return ActiveCompressionJob {
            result_rx,
            cancel_token,
            worker_handle: None,
        };
    }

    if is_directstorage_game(&game_path) {
        log::info!("Skipping DirectStorage game: {}", game_path.display());
        let _ = result_tx.send(CompressionResult::Skipped {
            idempotency_key,
            reason: "DirectStorage detected".to_string(),
        });
        return ActiveCompressionJob {
            result_rx,
            cancel_token,
            worker_handle: None,
        };
    }

    if process_checker.is_game_running(&game_path) {
        log::info!("Game is running, deferring: {}", game_path.display());
        let _ = result_tx.send(CompressionResult::Failed {
            idempotency_key,
            error: "Game is currently running".to_string(),
        });
        return ActiveCompressionJob {
            result_rx,
            cancel_token,
            worker_handle: None,
        };
    }

    if !game_path.is_dir() {
        log::warn!("Game path no longer exists: {}", game_path.display());
        let _ = result_tx.send(CompressionResult::Skipped {
            idempotency_key,
            reason: "Path not found".to_string(),
        });
        return ActiveCompressionJob {
            result_rx,
            cancel_token,
            worker_handle: None,
        };
    }

    let token = cancel_token.clone();
    let spawn_fail_tx = result_tx.clone();
    let spawn_fail_key = idempotency_key.clone();
    let spawn_result = std::thread::Builder::new()
        .name("compact-games-auto-compress".to_owned())
        .spawn(move || {
            let policy = compute_thread_policy(
                &game_path,
                true,
                Some(cpu_usage_percent),
                io_parallelism_override,
            );
            let engine = CompressionEngine::new(algorithm)
                .with_thread_policy(policy)
                .with_cancel_token(token.clone());

            log::info!(
                "Auto-compressing: {} ({}) with {:?}",
                game_name.as_deref().unwrap_or("unknown"),
                game_path.display(),
                algorithm,
            );

            let result = engine.compress_folder(&game_path);

            let compression_result = match result {
                Ok(stats) => {
                    log::info!(
                        "Auto-compression complete: {} saved {:.1}% ({} bytes)",
                        game_path.display(),
                        stats.savings_ratio() * 100.0,
                        stats.bytes_saved()
                    );
                    // Auto path skips pre-flight estimate; None keeps history usable
                    // for "last compressed" without biasing adaptive estimate learning.
                    record_compression(CompressionHistoryEntry::from_compression_stats(
                        game_path.to_string_lossy().into_owned(),
                        game_name.clone().unwrap_or_else(|| "unknown".to_string()),
                        None,
                        &stats,
                        algorithm,
                    ));
                    CompressionResult::Success { idempotency_key }
                }
                Err(crate::compression::error::CompressionError::Cancelled) => {
                    log::info!("Auto-compression cancelled for: {}", game_path.display());
                    CompressionResult::Failed {
                        idempotency_key,
                        error: "Cancelled due to user activity".to_string(),
                    }
                }
                Err(e) => {
                    log::error!("Auto-compression failed for {}: {e}", game_path.display());
                    CompressionResult::Failed {
                        idempotency_key,
                        error: e.to_string(),
                    }
                }
            };

            let _ = result_tx.send(compression_result);
        });

    let worker_handle = match spawn_result {
        Ok(handle) => Some(handle),
        Err(e) => {
            log::error!("Failed to spawn auto-compression thread: {e}");
            let _ = spawn_fail_tx.send(CompressionResult::Failed {
                idempotency_key: spawn_fail_key,
                error: format!("Thread spawn failed: {e}"),
            });
            None
        }
    };

    ActiveCompressionJob {
        result_rx,
        cancel_token,
        worker_handle,
    }
}

fn is_authorized_game_path(
    game_path: &Path,
    watch_roots: &[PathBuf],
    excluded_paths: &HashSet<String>,
) -> bool {
    let Ok(metadata) = std::fs::symlink_metadata(game_path) else {
        return false;
    };
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return false;
    }

    let normalized_path = crate::utils::normalize_path_key(game_path);
    if excluded_paths.contains(&normalized_path) {
        return false;
    }

    let Ok(canonical_game_path) = std::fs::canonicalize(game_path) else {
        return false;
    };
    watch_roots.iter().any(|root| {
        let Ok(root_metadata) = std::fs::symlink_metadata(root) else {
            return false;
        };
        if !root_metadata.is_dir() || root_metadata.file_type().is_symlink() {
            return false;
        }
        std::fs::canonicalize(root)
            .ok()
            .is_some_and(|canonical_root| {
                canonical_game_path == canonical_root
                    || canonical_game_path.parent() == Some(canonical_root.as_path())
            })
    })
}

pub(super) fn join_compression_worker(job: &mut ActiveCompressionJob, context: &str) {
    let Some(handle) = job.worker_handle.take() else {
        return;
    };
    if handle.join().is_err() {
        log::error!("Auto-compression worker thread panicked during {context}");
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, SystemTime};

    use super::*;
    use crate::automation::scheduler::{JobKind, JobStatus};
    use tempfile::TempDir;

    fn make_job(path: &std::path::Path) -> AutomationJob {
        AutomationJob {
            game_path: path.to_path_buf(),
            game_name: Some("DirectStorage Test".to_string()),
            kind: JobKind::Reconcile,
            status: JobStatus::Pending,
            idempotency_key: "test-idempotency-key".to_string(),
            queued_at: SystemTime::now(),
            started_at: None,
            error: None,
        }
    }

    #[test]
    fn directstorage_job_skips_automatically() {
        let dir = TempDir::new().expect("temp dir should be created");
        std::fs::write(dir.path().join("dstorage.dll"), b"fake")
            .expect("dstorage marker should be created");
        let job = make_job(dir.path());
        let process_checker = ProcessChecker::new();

        let active = spawn_compression_job(
            &job,
            &process_checker,
            CompressionAlgorithm::Xpress8K,
            0.0,
            None,
            vec![dir.path().parent().expect("temp parent").to_path_buf()],
            HashSet::new(),
        );

        let result = active
            .result_rx
            .recv_timeout(Duration::from_secs(2))
            .expect("worker should emit a result");

        assert!(
            matches!(
                result,
                CompressionResult::Skipped { reason, .. } if reason == "DirectStorage detected"
            ),
            "expected DirectStorage skip when override is disabled"
        );
    }

    #[test]
    fn directstorage_job_skips_even_when_manual_override_is_enabled() {
        let dir = TempDir::new().expect("temp dir should be created");
        std::fs::write(dir.path().join("dstorage.dll"), b"fake")
            .expect("dstorage marker should be created");
        std::fs::write(dir.path().join("data.bin"), vec![0_u8; 4096])
            .expect("sample file should be created");
        let job = make_job(dir.path());
        let process_checker = ProcessChecker::new();

        let active = spawn_compression_job(
            &job,
            &process_checker,
            CompressionAlgorithm::Xpress8K,
            0.0,
            None,
            vec![dir.path().parent().expect("temp parent").to_path_buf()],
            HashSet::new(),
        );

        let result = active
            .result_rx
            .recv_timeout(Duration::from_secs(10))
            .expect("worker should emit a result");

        assert!(
            matches!(
                result,
                CompressionResult::Skipped { reason, .. } if reason == "DirectStorage detected"
            ),
            "manual overrides must not bypass the unattended DirectStorage safety gate"
        );
    }

    #[test]
    fn authorization_rejects_paths_outside_the_configured_library_root() {
        let root = TempDir::new().expect("library root");
        let game = root.path().join("Game");
        let outside = TempDir::new().expect("outside path");
        std::fs::create_dir_all(&game).expect("game directory");

        assert!(is_authorized_game_path(
            &game,
            &[root.path().to_path_buf()],
            &HashSet::new(),
        ));
        assert!(!is_authorized_game_path(
            outside.path(),
            &[root.path().to_path_buf()],
            &HashSet::new(),
        ));
    }

    #[test]
    fn authorization_allows_a_discovered_game_root() {
        let game = TempDir::new().expect("discovered game root");

        assert!(is_authorized_game_path(
            game.path(),
            &[game.path().to_path_buf()],
            &HashSet::new(),
        ));
    }
}
