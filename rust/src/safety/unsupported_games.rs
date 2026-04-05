//! Unsupported games database: embedded + community + user-reported.
//!
//! Some games break after WOF compression but are not DirectStorage games.
//! This module provides O(1) lookup by game folder name (case-insensitive)
//! across three merged sets:
//!   1. Embedded (compile-time, from `known_unsupported_games.json`)
//!   2. Community (bundled or refreshed externally, cached to disk)
//!   3. User-reported (local user additions)
//!
//! User reports also keep lightweight local metadata so the app can prepare a
//! stable, reviewable community-candidate payload later without promoting
//! obvious false positives immediately.

use std::collections::{HashMap, HashSet};
use std::path::Path;
#[cfg(not(test))]
use std::sync::atomic::AtomicBool;
use std::sync::{LazyLock, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

mod storage;
mod submission;
#[cfg(test)]
mod tests;
mod types;

use storage::{
    load_json_set_or_default, load_report_records_or_default, load_sync_meta_or_default,
    persist_sync_meta, queue_save, resolve_path_or_log,
};
use types::{SaveTarget, UnsupportedReportRecord, UnsupportedSyncMeta};

const KNOWN_UNSUPPORTED_JSON: &str = include_str!("known_unsupported_games.json");
const MAX_ENTRIES: usize = 32_768;
const REPORT_STABILITY_WINDOW_MS: u64 = 7 * 24 * 60 * 60 * 1000;
const REPORT_SUBMISSION_INTERVAL_MS: u64 = 24 * 60 * 60 * 1000;
const COMMUNITY_FETCH_INTERVAL_MS: u64 = 24 * 60 * 60 * 1000;
#[cfg(not(test))]
const REPORT_SUBMISSION_ENDPOINT_ENV: &str = "COMPACT_GAMES_UNSUPPORTED_REPORT_ENDPOINT";
const REPORT_SUBMISSION_ENDPOINT_FILE: &str = "unsupported_report_endpoint.txt";

// Default endpoints.
#[cfg(not(test))]
const DEFAULT_REPORT_SUBMISSION_ENDPOINT: &str =
    "https://compact-games-unsupported-report-ingest.pressplay-subai.workers.dev/unsupported-reports";
// Community list is fetched from GitHub Releases (exported by the repo workflow).
pub(crate) const DEFAULT_COMMUNITY_LIST_ENDPOINT: &str =
    "https://github.com/g1mliii/compact-games/releases/latest/download/unsupported_games.json";

static EMBEDDED: LazyLock<HashSet<String>> = LazyLock::new(|| {
    serde_json::from_str::<Vec<String>>(KNOWN_UNSUPPORTED_JSON)
        .unwrap_or_else(|e| {
            log::warn!("Failed to parse known_unsupported_games.json: {e}");
            Vec::new()
        })
        .into_iter()
        .filter_map(|s| normalize_folder_name(&s))
        .collect()
});

static COMMUNITY: LazyLock<RwLock<HashSet<String>>> = LazyLock::new(|| {
    let set = resolve_path_or_log(storage::community_path(), "community unsupported list")
        .map(|path| load_json_set_or_default(&path, "community unsupported list"))
        .unwrap_or_default();
    RwLock::new(set)
});

static USER_REPORTED: LazyLock<RwLock<HashSet<String>>> = LazyLock::new(|| {
    let set = resolve_path_or_log(
        storage::user_reported_path(),
        "user-reported unsupported list",
    )
    .map(|path| load_json_set_or_default(&path, "user-reported unsupported list"))
    .unwrap_or_default();
    RwLock::new(set)
});

static REPORT_RECORDS: LazyLock<RwLock<HashMap<String, UnsupportedReportRecord>>> =
    LazyLock::new(|| {
        let records =
            resolve_path_or_log(storage::report_records_path(), "unsupported report records")
                .map(|path| load_report_records_or_default(&path, "unsupported report records"))
                .unwrap_or_default();
        RwLock::new(records)
    });

static SYNC_META: LazyLock<RwLock<UnsupportedSyncMeta>> = LazyLock::new(|| {
    let meta = resolve_path_or_log(storage::sync_meta_path(), "unsupported sync metadata")
        .map(|path| load_sync_meta_or_default(&path, "unsupported sync metadata"))
        .unwrap_or_default();
    RwLock::new(meta)
});

#[cfg(not(test))]
static CONFIG_DIR_CREATED: AtomicBool = AtomicBool::new(false);

fn normalize_folder_name(name: &str) -> Option<String> {
    let normalized = name.trim().to_ascii_lowercase();
    if normalized.is_empty() || normalized.starts_with('.') {
        return None;
    }
    Some(normalized)
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

fn note_report_record(key: &str, active: bool) {
    let current_time = now_ms();
    let mut records = match REPORT_RECORDS.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let record = records.entry(key.to_string()).or_default();
    if record.first_reported_at_ms == 0 {
        record.first_reported_at_ms = current_time;
    }

    if active {
        if !record.active || record.activated_at_ms == 0 {
            record.activated_at_ms = current_time;
        }
        record.active = true;
        record.last_reported_at_ms = current_time;
        record.report_count = record.report_count.saturating_add(1);
    } else {
        record.active = false;
        record.last_withdrawn_at_ms = Some(current_time);
    }
    drop(records);

    queue_save(SaveTarget::ReportRecords);
}

/// Check if a game at `game_path` is in any unsupported list (O(1) lookup).
pub fn is_unsupported_game(game_path: &Path) -> bool {
    let folder_name = match game_path.file_name().and_then(|n| n.to_str()) {
        Some(name) => name,
        None => return false,
    };
    let key = folder_name.to_ascii_lowercase();

    if EMBEDDED.contains(&key) {
        return true;
    }
    if let Ok(set) = COMMUNITY.read() {
        if set.contains(&key) {
            return true;
        }
    }
    if let Ok(set) = USER_REPORTED.read() {
        if set.contains(&key) {
            return true;
        }
    }
    false
}

/// Add a game to the user-reported unsupported list.
pub fn report_unsupported_game(game_path: &Path) {
    let folder_name = match game_path.file_name().and_then(|n| n.to_str()) {
        Some(name) => name,
        None => return,
    };
    let key = match normalize_folder_name(folder_name) {
        Some(k) => k,
        None => return,
    };

    if EMBEDDED.contains(&key) {
        return;
    }
    if let Ok(set) = COMMUNITY.read() {
        if set.contains(&key) {
            return;
        }
    }

    let mut set = match USER_REPORTED.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if set.contains(&key) || set.len() >= MAX_ENTRIES {
        return;
    }
    set.insert(key.clone());
    drop(set);

    note_report_record(&key, true);
    log::info!("User reported unsupported game: {key}");
    queue_save(SaveTarget::UserReported);
}

/// Remove a game from the user-reported unsupported list.
pub fn unreport_unsupported_game(game_path: &Path) {
    let folder_name = match game_path.file_name().and_then(|n| n.to_str()) {
        Some(name) => name,
        None => return,
    };
    let key = match normalize_folder_name(folder_name) {
        Some(k) => k,
        None => return,
    };

    let mut set = match USER_REPORTED.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if !set.remove(&key) {
        return;
    }
    drop(set);

    note_report_record(&key, false);
    log::info!("Removed user-reported unsupported game: {key}");
    queue_save(SaveTarget::UserReported);
}

/// Replace the community unsupported list from raw JSON bytes.
/// Called after fetching from GitHub or a packaged update.
pub fn update_community_list(games: Vec<String>) -> Result<(), String> {
    let mut new_set = HashSet::with_capacity(games.len().min(MAX_ENTRIES));
    for game in games {
        if let Some(normalized) = normalize_folder_name(&game) {
            if new_set.len() >= MAX_ENTRIES {
                break;
            }
            new_set.insert(normalized);
        }
    }

    let mut set = match COMMUNITY.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    *set = new_set;
    drop(set);

    log::info!("Updated community unsupported list");
    queue_save(SaveTarget::Community);
    Ok(())
}

/// Prepare the local unsupported-report payload and optionally best-effort
/// submit the latest stable snapshot to a configured endpoint.
pub fn sync_report_collection(app_version: &str) -> Result<u32, String> {
    submission::sync_report_collection_inner(app_version)
}

/// Returns true when the cached community list should be refreshed.
pub fn should_fetch_community_list() -> bool {
    let current_time_ms = now_ms();
    let last_fetch = match SYNC_META.read() {
        Ok(guard) => guard.last_community_fetch_at_ms,
        Err(poisoned) => poisoned.into_inner().last_community_fetch_at_ms,
    };

    match last_fetch {
        None => true,
        Some(last_fetch_at_ms) => {
            current_time_ms.saturating_sub(last_fetch_at_ms) >= COMMUNITY_FETCH_INTERVAL_MS
        }
    }
}

pub fn mark_community_list_fetched() -> Result<(), String> {
    let current_time_ms = now_ms();
    let mut meta = match SYNC_META.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    meta.last_community_fetch_at_ms = Some(current_time_ms);
    drop(meta);
    persist_sync_meta()
}

pub fn community_list_len() -> u32 {
    match COMMUNITY.read() {
        Ok(guard) => guard.len() as u32,
        Err(poisoned) => poisoned.into_inner().len() as u32,
    }
}
