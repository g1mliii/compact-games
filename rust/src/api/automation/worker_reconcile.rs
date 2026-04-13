use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};

use crate::automation::scheduler::{AutoScheduler, JobStatus};
use crate::compression::history::with_latest_compression_timestamps_by_path;
use crate::discovery::cache::{
    compute_change_token, has_entry as has_discovery_cache_entry, normalize_path_key,
};

const MAX_RECONCILE_JOBS_PER_PASS: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct ReconcileEnqueueResult {
    pub queued: usize,
    pub hit_cap: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct ReconcileCandidate {
    game_name: String,
    game_path: PathBuf,
}

pub(super) fn normalize_watch_paths(watch_paths: &[String]) -> Vec<String> {
    let mut normalized = watch_paths
        .iter()
        .map(|raw| normalize_watch_path(raw))
        .collect::<Vec<_>>();
    normalized.sort_unstable();
    normalized.dedup();
    normalized
}

fn normalize_watch_path(raw: &str) -> String {
    crate::utils::normalize_path_key(std::path::Path::new(raw))
}

fn unique_watch_paths(watch_paths: &[String]) -> Vec<PathBuf> {
    let mut seen = HashSet::new();
    let mut unique = Vec::new();
    for raw in watch_paths {
        let normalized = normalize_watch_path(raw);
        if seen.insert(normalized) {
            unique.push(PathBuf::from(raw));
        }
    }
    unique
}

fn game_change_marker_ms(path: &Path) -> Option<u64> {
    let include_probe = has_discovery_cache_entry(path);
    let token = compute_change_token(path, include_probe);
    [
        token.root_mtime_ms,
        token.child_max_mtime_ms,
        token.probe_max_mtime_ms,
    ]
    .into_iter()
    .flatten()
    .max()
}

fn collect_game_folder_candidates(watch_root: &Path) -> Vec<(String, PathBuf)> {
    let entries = match fs::read_dir(watch_root) {
        Ok(entries) => entries,
        Err(e) => {
            log::debug!(
                "Startup reconcile: failed to read watch root {}: {}",
                watch_root.display(),
                e
            );
            return Vec::new();
        }
    };

    let mut candidates: Vec<(String, String, PathBuf)> = entries
        .filter_map(|entry| entry.ok())
        .filter_map(|entry| {
            let path = entry.path();
            if !path.is_dir() {
                return None;
            }
            let normalized = normalize_path_key(&path);
            let name = entry.file_name().to_string_lossy().into_owned();
            Some((normalized, name, path))
        })
        .collect();
    candidates.sort_unstable_by(|left, right| left.0.cmp(&right.0));
    candidates
        .into_iter()
        .map(|(_, name, path)| (name, path))
        .collect()
}

fn watch_root_candidate_name(watch_root: &Path) -> String {
    watch_root
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| watch_root.display().to_string())
}

pub(super) fn build_startup_reconcile_candidates(
    watch_paths: &[String],
) -> VecDeque<ReconcileCandidate> {
    let mut candidates = VecDeque::new();
    for root in unique_watch_paths(watch_paths) {
        if !root.is_dir() {
            continue;
        }

        candidates.push_back(ReconcileCandidate {
            game_name: watch_root_candidate_name(&root),
            game_path: root.clone(),
        });

        for (name, game_path) in collect_game_folder_candidates(&root) {
            candidates.push_back(ReconcileCandidate {
                game_name: name,
                game_path,
            });
        }
    }

    candidates
}

fn maybe_enqueue_reconcile_candidate(
    scheduler: &mut AutoScheduler,
    history_by_path: &HashMap<String, u64>,
    attempted_paths: &mut HashSet<String>,
    candidate: ReconcileCandidate,
) -> bool {
    use crate::automation::watcher::WatchEvent;

    let ReconcileCandidate {
        game_name,
        game_path,
    } = candidate;
    let path_key = normalize_path_key(&game_path);
    if attempted_paths.contains(&path_key) {
        return false;
    }
    let Some(last_compressed_ms) = history_by_path.get(&path_key).copied() else {
        return false;
    };
    let Some(modified_ms) = game_change_marker_ms(&game_path) else {
        return false;
    };
    if modified_ms <= last_compressed_ms {
        return false;
    }

    let had_pending_job_before = scheduler.queue.iter().any(|job| {
        job.game_path == game_path
            && matches!(
                job.status,
                JobStatus::Pending | JobStatus::WaitingForSettle | JobStatus::WaitingForIdle
            )
    });
    scheduler.on_event(WatchEvent::GameModified {
        path: game_path.clone(),
        game_name: Some(game_name),
    });
    let has_pending_job_after = scheduler.queue.iter().any(|job| {
        job.game_path == game_path
            && matches!(
                job.status,
                JobStatus::Pending | JobStatus::WaitingForSettle | JobStatus::WaitingForIdle
            )
    });
    if had_pending_job_before || !has_pending_job_after {
        return false;
    }

    attempted_paths.insert(path_key);
    log::debug!(
        "[automation][reconcile] queued modified game path=\"{}\" modified_ms={} last_compressed_ms={}",
        game_path.display(),
        modified_ms,
        last_compressed_ms
    );
    true
}

pub(super) fn enqueue_startup_reconcile_candidate_batch(
    scheduler: &mut AutoScheduler,
    candidates: &mut VecDeque<ReconcileCandidate>,
    attempted_paths: &mut HashSet<String>,
) -> ReconcileEnqueueResult {
    let queued = with_latest_compression_timestamps_by_path(|history_by_path| {
        if history_by_path.is_empty() {
            candidates.clear();
            return 0;
        }

        let mut queued = 0_usize;
        while queued < MAX_RECONCILE_JOBS_PER_PASS {
            let Some(candidate) = candidates.pop_front() else {
                break;
            };
            if maybe_enqueue_reconcile_candidate(
                scheduler,
                history_by_path,
                attempted_paths,
                candidate,
            ) {
                queued = queued.saturating_add(1);
            }
        }
        queued
    });

    let hit_cap = queued >= MAX_RECONCILE_JOBS_PER_PASS && !candidates.is_empty();
    if hit_cap {
        log::debug!(
            "Startup reconcile: queued job cap ({}) reached; deferring remaining candidates",
            MAX_RECONCILE_JOBS_PER_PASS
        );
    }

    ReconcileEnqueueResult { queued, hit_cap }
}

#[cfg(test)]
pub(super) fn enqueue_closed_session_reconcile_jobs(
    scheduler: &mut AutoScheduler,
    watch_paths: &[String],
    attempted_paths: &mut HashSet<String>,
) -> ReconcileEnqueueResult {
    let mut candidates = build_startup_reconcile_candidates(watch_paths);
    enqueue_startup_reconcile_candidate_batch(scheduler, &mut candidates, attempted_paths)
}

#[cfg(test)]
mod tests;
