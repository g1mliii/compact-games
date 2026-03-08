use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender, TrySendError};
use std::sync::LazyLock;

use serde::ser::{SerializeMap, Serializer as _};
use serde::Serialize;

use super::types::{SaveTarget, UnsupportedReportRecord, UnsupportedSyncMeta};
#[cfg(not(test))]
use super::CONFIG_DIR_CREATED;
use super::{
    normalize_folder_name, COMMUNITY, MAX_ENTRIES, REPORT_RECORDS, SYNC_META, USER_REPORTED,
};

pub(super) fn community_path() -> Result<PathBuf, std::io::Error> {
    Ok(config_dir()?.join("community_unsupported.json"))
}

pub(super) fn user_reported_path() -> Result<PathBuf, std::io::Error> {
    Ok(config_dir()?.join("user_reported_unsupported.json"))
}

pub(super) fn report_records_path() -> Result<PathBuf, std::io::Error> {
    Ok(config_dir()?.join("unsupported_report_records.json"))
}

pub(super) fn sync_meta_path() -> Result<PathBuf, std::io::Error> {
    Ok(config_dir()?.join("unsupported_report_meta.json"))
}

pub(super) fn pending_report_payload_path() -> Result<PathBuf, std::io::Error> {
    Ok(config_dir()?.join("unsupported_report_candidates.json"))
}

pub(super) fn report_submission_endpoint_path() -> Result<PathBuf, std::io::Error> {
    Ok(config_dir()?.join(super::REPORT_SUBMISSION_ENDPOINT_FILE))
}

pub(super) fn load_json_set(path: &Path) -> Result<HashSet<String>, Box<dyn std::error::Error>> {
    let games: Vec<String> = serde_json::from_slice(&fs::read(path)?)?;
    let mut set = HashSet::with_capacity(games.len().min(MAX_ENTRIES));
    for game in games {
        if let Some(normalized) = normalize_folder_name(&game) {
            if set.len() >= MAX_ENTRIES {
                break;
            }
            set.insert(normalized);
        }
    }
    Ok(set)
}

pub(super) fn load_report_records(
    path: &Path,
) -> Result<HashMap<String, UnsupportedReportRecord>, Box<dyn std::error::Error>> {
    let stored: BTreeMap<String, UnsupportedReportRecord> =
        serde_json::from_slice(&fs::read(path)?)?;
    let mut records = HashMap::with_capacity(stored.len().min(MAX_ENTRIES));
    for (key, record) in stored {
        if normalize_folder_name(&key).is_none() {
            continue;
        }
        if records.len() >= MAX_ENTRIES {
            break;
        }
        records.insert(key, record);
    }
    Ok(records)
}

pub(super) fn load_sync_meta(
    path: &Path,
) -> Result<UnsupportedSyncMeta, Box<dyn std::error::Error>> {
    let meta: UnsupportedSyncMeta = serde_json::from_slice(&fs::read(path)?)?;
    Ok(meta)
}

fn config_dir() -> Result<PathBuf, std::io::Error> {
    #[cfg(test)]
    {
        use std::time::{SystemTime, UNIX_EPOCH};
        static TEST_DIR: LazyLock<PathBuf> = LazyLock::new(|| {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            std::env::temp_dir().join(format!(
                "pressplay-unsupported-tests-{}-{nanos}",
                std::process::id()
            ))
        });
        fs::create_dir_all(&*TEST_DIR)?;
        Ok(TEST_DIR.clone())
    }

    #[cfg(not(test))]
    {
        let dir = dirs::config_dir()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir"))?;
        let pressplay_dir = dir.join("pressplay");
        if !CONFIG_DIR_CREATED.load(std::sync::atomic::Ordering::Relaxed) {
            fs::create_dir_all(&pressplay_dir)?;
            CONFIG_DIR_CREATED.store(true, std::sync::atomic::Ordering::Relaxed);
        }
        Ok(pressplay_dir)
    }
}

fn atomic_write_json<T: Serialize + ?Sized>(
    path: &Path,
    value: &T,
) -> Result<(), Box<dyn std::error::Error>> {
    let json = serde_json::to_vec(value)?;
    crate::utils::atomic_write(path, &json)?;
    Ok(())
}

fn save_set(
    set: &std::sync::RwLock<HashSet<String>>,
    path: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let guard = match set.read() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let mut sorted: Vec<&str> = guard.iter().map(String::as_str).collect();
    sorted.sort_unstable();
    let json = serde_json::to_vec(&sorted)?;
    crate::utils::atomic_write(path, &json)?;
    Ok(())
}

fn save_report_records(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let guard = match REPORT_RECORDS.read() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let mut ordered: Vec<(&str, &UnsupportedReportRecord)> = guard
        .iter()
        .map(|(key, value)| (key.as_str(), value))
        .collect();
    ordered.sort_unstable_by(|left, right| left.0.cmp(right.0));

    let mut serializer = serde_json::Serializer::new(Vec::new());
    let mut map = serializer.serialize_map(Some(ordered.len()))?;
    for (key, value) in ordered {
        map.serialize_entry(key, value)?;
    }
    map.end()?;

    crate::utils::atomic_write(path, &serializer.into_inner())?;
    Ok(())
}

pub(super) fn persist_sync_meta() -> Result<(), String> {
    let snapshot = match SYNC_META.read() {
        Ok(guard) => guard.clone(),
        Err(poisoned) => poisoned.into_inner().clone(),
    };
    let path = sync_meta_path().map_err(|e| format!("Failed to resolve sync meta path: {e}"))?;
    atomic_write_json(&path, &snapshot).map_err(|e| format!("Failed to persist sync meta: {e}"))
}

fn persist_target(target: SaveTarget) -> Result<(), Box<dyn std::error::Error>> {
    match target {
        SaveTarget::Community => {
            let path = community_path()?;
            save_set(&COMMUNITY, &path)
        }
        SaveTarget::UserReported => {
            let path = user_reported_path()?;
            save_set(&USER_REPORTED, &path)
        }
        SaveTarget::ReportRecords => {
            let path = report_records_path()?;
            save_report_records(&path)
        }
    }
}

fn save_worker(rx: Receiver<SaveTarget>) {
    while let Ok(target) = rx.recv() {
        let mut save_community = matches!(target, SaveTarget::Community);
        let mut save_user = matches!(target, SaveTarget::UserReported);
        let mut save_records = matches!(target, SaveTarget::ReportRecords);
        while let Ok(next) = rx.try_recv() {
            match next {
                SaveTarget::Community => save_community = true,
                SaveTarget::UserReported => save_user = true,
                SaveTarget::ReportRecords => save_records = true,
            }
        }
        if save_community {
            if let Err(error) = persist_target(SaveTarget::Community) {
                log::warn!("Failed to persist community unsupported list: {error}");
            }
        }
        if save_user {
            if let Err(error) = persist_target(SaveTarget::UserReported) {
                log::warn!("Failed to persist user-reported unsupported list: {error}");
            }
        }
        if save_records {
            if let Err(error) = persist_target(SaveTarget::ReportRecords) {
                log::warn!("Failed to persist unsupported report records: {error}");
            }
        }
    }
}

static SAVE_QUEUE: LazyLock<Option<SyncSender<SaveTarget>>> = LazyLock::new(|| {
    let (tx, rx) = sync_channel(8);
    match std::thread::Builder::new()
        .name("pressplay-unsupported-writer".to_string())
        .spawn(move || save_worker(rx))
    {
        Ok(_) => Some(tx),
        Err(e) => {
            log::warn!("Failed to spawn unsupported games writer thread: {e}");
            None
        }
    }
});

pub(super) fn queue_save(target: SaveTarget) {
    if let Some(tx) = SAVE_QUEUE.as_ref() {
        match tx.try_send(target) {
            Ok(()) => {}
            Err(TrySendError::Full(target)) => {
                log::warn!("Unsupported games writer queue full; persisting synchronously");
                if let Err(error) = persist_target(target) {
                    log::warn!("Synchronous unsupported-data persist failed: {error}");
                }
            }
            Err(TrySendError::Disconnected(target)) => {
                log::warn!("Unsupported games writer thread unavailable; persisting synchronously");
                if let Err(error) = persist_target(target) {
                    log::warn!("Synchronous unsupported-data persist failed: {error}");
                }
            }
        }
    } else if let Err(error) = persist_target(target) {
        log::warn!("Unsupported games writer not available; persist failed: {error}");
    }
}

pub(super) fn load_json_set_or_default(path: &Path, label: &str) -> HashSet<String> {
    match load_json_set(path) {
        Ok(set) => set,
        Err(error) => {
            log_non_missing_load_error(label, path, error.as_ref());
            HashSet::new()
        }
    }
}

pub(super) fn load_report_records_or_default(
    path: &Path,
    label: &str,
) -> HashMap<String, UnsupportedReportRecord> {
    match load_report_records(path) {
        Ok(records) => records,
        Err(error) => {
            log_non_missing_load_error(label, path, error.as_ref());
            HashMap::new()
        }
    }
}

pub(super) fn load_sync_meta_or_default(path: &Path, label: &str) -> UnsupportedSyncMeta {
    match load_sync_meta(path) {
        Ok(meta) => meta,
        Err(error) => {
            log_non_missing_load_error(label, path, error.as_ref());
            UnsupportedSyncMeta::default()
        }
    }
}

fn log_non_missing_load_error(label: &str, path: &Path, error: &(dyn std::error::Error + 'static)) {
    let missing = error
        .downcast_ref::<std::io::Error>()
        .is_some_and(|io_error| io_error.kind() == std::io::ErrorKind::NotFound);
    if !missing {
        log::warn!("Failed to load {label} from {}: {error}", path.display());
    }
}

pub(super) fn resolve_path_or_log(
    path_result: Result<PathBuf, std::io::Error>,
    label: &str,
) -> Option<PathBuf> {
    match path_result {
        Ok(path) => Some(path),
        Err(error) => {
            log::warn!("Failed to resolve {label} path: {error}");
            None
        }
    }
}
