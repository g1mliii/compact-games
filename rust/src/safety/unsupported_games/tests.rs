use super::*;
use std::fs;
use std::path::Path;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static TEST_MUTEX: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

fn reset_test_state() {
    match COMMUNITY.write() {
        Ok(mut guard) => guard.clear(),
        Err(poisoned) => poisoned.into_inner().clear(),
    }
    match USER_REPORTED.write() {
        Ok(mut guard) => guard.clear(),
        Err(poisoned) => poisoned.into_inner().clear(),
    }
    match REPORT_RECORDS.write() {
        Ok(mut guard) => guard.clear(),
        Err(poisoned) => poisoned.into_inner().clear(),
    }
    match SYNC_META.write() {
        Ok(mut guard) => *guard = UnsupportedSyncMeta::default(),
        Err(poisoned) => *poisoned.into_inner() = UnsupportedSyncMeta::default(),
    }

    if let Ok(path) = storage::community_path() {
        let _ = fs::remove_file(path);
    }
    if let Ok(path) = storage::user_reported_path() {
        let _ = fs::remove_file(path);
    }
    if let Ok(path) = storage::report_records_path() {
        let _ = fs::remove_file(path);
    }
    if let Ok(path) = storage::sync_meta_path() {
        let _ = fs::remove_file(path);
    }
    if let Ok(path) = storage::pending_report_payload_path() {
        let _ = fs::remove_file(path);
    }
    if let Ok(path) = storage::report_submission_endpoint_path() {
        let _ = fs::remove_file(path);
    }
}

#[test]
fn embedded_json_parses() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();
    assert!(
        !EMBEDDED.is_empty(),
        "embedded unsupported database should have entries"
    );
}

#[test]
fn known_unsupported_game_detected() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();
    assert!(is_unsupported_game(Path::new(
        r"C:\Games\Tom Clancy's Rainbow Six Siege"
    )));
    assert!(is_unsupported_game(Path::new(
        r"C:\Games\tom clancy's rainbow six siege"
    )));
}

#[test]
fn unknown_game_not_detected() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();
    assert!(!is_unsupported_game(Path::new(
        r"C:\Games\__definitely_not_unsupported__"
    )));
}

#[test]
fn report_and_unreport() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let name = format!(r"C:\Games\TestUnsupported_{nanos}");
    let path = Path::new(&name);

    assert!(!is_unsupported_game(path));
    report_unsupported_game(path);
    std::thread::sleep(std::time::Duration::from_millis(50));
    assert!(is_unsupported_game(path));

    unreport_unsupported_game(path);
    std::thread::sleep(std::time::Duration::from_millis(50));
    assert!(!is_unsupported_game(path));
}

#[test]
fn update_community_list_works() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();

    update_community_list(vec!["community_test_game_abc123".to_string()]).unwrap();
    assert!(is_unsupported_game(Path::new(
        r"C:\Games\community_test_game_abc123"
    )));
}

#[test]
fn normalize_rejects_empty_and_dot_prefix() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();

    assert_eq!(normalize_folder_name(""), None);
    assert_eq!(normalize_folder_name(".hidden"), None);
    assert_eq!(
        normalize_folder_name(" My Game "),
        Some("my game".to_string())
    );
}

#[test]
fn sync_report_collection_only_promotes_stable_reports() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let name = format!(r"C:\Games\StableCandidate_{nanos}");
    let path = Path::new(&name);
    report_unsupported_game(path);

    assert_eq!(sync_report_collection("0.1.0").unwrap(), 0);

    let key = normalize_folder_name(path.file_name().unwrap().to_str().unwrap()).unwrap();
    {
        let mut records = REPORT_RECORDS.write().unwrap();
        let record = records.get_mut(&key).unwrap();
        let stable_at = now_ms().saturating_sub(REPORT_STABILITY_WINDOW_MS + 1);
        record.first_reported_at_ms = stable_at;
        record.activated_at_ms = stable_at;
        record.last_reported_at_ms = stable_at;
    }

    assert_eq!(sync_report_collection("0.1.0").unwrap(), 1);

    let payload_path = storage::pending_report_payload_path().unwrap();
    let payload: types::UnsupportedReportPayload =
        serde_json::from_slice(&fs::read(payload_path).unwrap()).unwrap();
    assert_eq!(payload.reports.len(), 1);
    assert_eq!(payload.reports[0].folder_name, key);
}

#[test]
fn sync_report_collection_excludes_withdrawn_reports() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let name = format!(r"C:\Games\WithdrawnCandidate_{nanos}");
    let path = Path::new(&name);
    report_unsupported_game(path);

    let key = normalize_folder_name(path.file_name().unwrap().to_str().unwrap()).unwrap();
    {
        let mut records = REPORT_RECORDS.write().unwrap();
        let record = records.get_mut(&key).unwrap();
        let stable_at = now_ms().saturating_sub(REPORT_STABILITY_WINDOW_MS + 1);
        record.first_reported_at_ms = stable_at;
        record.activated_at_ms = stable_at;
        record.last_reported_at_ms = stable_at;
    }

    unreport_unsupported_game(path);
    assert_eq!(sync_report_collection("0.1.0").unwrap(), 0);
}

#[test]
fn sync_report_collection_does_not_rewrite_for_timestamp_only_changes() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let name = format!(r"C:\Games\StableNoRewrite_{nanos}");
    let path = Path::new(&name);
    report_unsupported_game(path);

    let key = normalize_folder_name(path.file_name().unwrap().to_str().unwrap()).unwrap();
    {
        let mut records = REPORT_RECORDS.write().unwrap();
        let record = records.get_mut(&key).unwrap();
        let stable_at = now_ms().saturating_sub(REPORT_STABILITY_WINDOW_MS + 1);
        record.first_reported_at_ms = stable_at;
        record.activated_at_ms = stable_at;
        record.last_reported_at_ms = stable_at;
    }

    assert_eq!(sync_report_collection("0.1.0").unwrap(), 1);
    let first_meta = SYNC_META.read().unwrap().clone();

    std::thread::sleep(std::time::Duration::from_millis(2));

    assert_eq!(sync_report_collection("0.1.0").unwrap(), 1);
    let second_meta = SYNC_META.read().unwrap().clone();

    assert_eq!(
        first_meta.last_prepared_payload_hash,
        second_meta.last_prepared_payload_hash
    );
    assert_eq!(
        first_meta.last_prepared_at_ms,
        second_meta.last_prepared_at_ms
    );
}

#[test]
fn should_submit_payload_requires_change_and_weekly_cadence() {
    let _guard = TEST_MUTEX.lock().unwrap();
    reset_test_state();

    let now = REPORT_SUBMISSION_INTERVAL_MS * 2;
    let unchanged_meta = UnsupportedSyncMeta {
        last_submitted_at_ms: Some(now - REPORT_SUBMISSION_INTERVAL_MS - 1),
        last_submitted_payload_hash: Some("same".to_string()),
        ..UnsupportedSyncMeta::default()
    };
    assert!(!submission::should_submit_payload(
        &unchanged_meta,
        "same",
        now
    ));

    let recent_meta = UnsupportedSyncMeta {
        last_submitted_at_ms: Some(now - REPORT_SUBMISSION_INTERVAL_MS + 10),
        last_submitted_payload_hash: Some("older".to_string()),
        ..UnsupportedSyncMeta::default()
    };
    assert!(!submission::should_submit_payload(&recent_meta, "new", now));

    let due_meta = UnsupportedSyncMeta {
        last_submitted_at_ms: Some(now - REPORT_SUBMISSION_INTERVAL_MS - 1),
        last_submitted_payload_hash: Some("older".to_string()),
        ..UnsupportedSyncMeta::default()
    };
    assert!(submission::should_submit_payload(&due_meta, "new", now));

    let first_submit_meta = UnsupportedSyncMeta::default();
    assert!(submission::should_submit_payload(
        &first_submit_meta,
        "first",
        now
    ));
}
