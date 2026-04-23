use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};

use walkdir::WalkDir;

use crate::automation::scheduler::{AutoScheduler, JobStatus};
use crate::automation::watcher::coalescer::{is_noise_path, is_user_state_subpath};
use crate::compression::history::with_latest_compression_timestamps_by_path;
use crate::discovery::cache::{has_entry as has_discovery_cache_entry, normalize_path_key};

const MAX_RECONCILE_JOBS_PER_PASS: usize = 256;
const RECONCILE_PROBE_MAX_DEPTH: usize = 6;
const RECONCILE_PROBE_MAX_FILES: usize = 96;

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
    let mut max_mtime = filtered_child_max_mtime_ms(path);

    if has_discovery_cache_entry(path) {
        let mut files_seen = 0usize;
        for entry in WalkDir::new(path)
            .max_depth(RECONCILE_PROBE_MAX_DEPTH)
            .follow_links(false)
            .into_iter()
            .filter_entry(|entry| {
                let relative_path = entry.path().strip_prefix(path).unwrap_or(entry.path());
                !is_noise_path(relative_path) && !is_user_state_subpath(relative_path)
            })
            .filter_map(|entry| entry.ok())
        {
            let relative_path = entry.path().strip_prefix(path).unwrap_or(entry.path());
            if is_noise_path(relative_path) || is_user_state_subpath(relative_path) {
                continue;
            }

            let Ok(metadata) = entry.metadata() else {
                continue;
            };

            max_mtime = max_optional_u64(max_mtime, metadata_modified_ms(&metadata));

            if metadata.is_file() {
                files_seen = files_seen.saturating_add(1);
                if files_seen >= RECONCILE_PROBE_MAX_FILES {
                    break;
                }
            }
        }
    }

    max_mtime
}

fn filtered_child_max_mtime_ms(path: &Path) -> Option<u64> {
    let mut child_max_mtime_ms: Option<u64> = None;

    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            let child_path = entry.path();
            let relative_path = child_path
                .strip_prefix(path)
                .unwrap_or(child_path.as_path());
            if is_noise_path(relative_path) || is_user_state_subpath(relative_path) {
                continue;
            }
            let child_mtime = entry.metadata().ok().and_then(|m| metadata_modified_ms(&m));
            child_max_mtime_ms = max_optional_u64(child_max_mtime_ms, child_mtime);
        }
    }

    child_max_mtime_ms
}

fn metadata_modified_ms(metadata: &fs::Metadata) -> Option<u64> {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as u64)
}

fn max_optional_u64(left: Option<u64>, right: Option<u64>) -> Option<u64> {
    match (left, right) {
        (Some(left), Some(right)) => Some(left.max(right)),
        (Some(left), None) => Some(left),
        (None, Some(right)) => Some(right),
        (None, None) => None,
    }
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
