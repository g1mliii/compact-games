use super::*;
use crate::automation::journal::JournalWriter;
use crate::automation::scheduler::SchedulerConfig;
use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::history::{
    record_compression, ActualStats, CompressionHistoryEntry, EstimateSnapshot,
};
use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::time::UNIX_EPOCH;

const OLDER_THAN_RECENT_WINDOW_MS: u64 = 60_000;

fn test_scheduler(journal_dir: &tempfile::TempDir) -> AutoScheduler {
    AutoScheduler::new(
        SchedulerConfig::default(),
        JournalWriter::new(journal_dir.path().join("worker_test_journal.json")),
    )
}

fn add_compression_history(path: &Path, timestamp_ms: u64) {
    record_compression(CompressionHistoryEntry {
        game_path: path.to_string_lossy().into_owned(),
        game_name: "Test Game".to_string(),
        timestamp_ms,
        estimate: EstimateSnapshot {
            scanned_files: 0,
            sampled_bytes: 0,
            estimated_saved_bytes: 0,
        },
        actual_stats: ActualStats {
            original_bytes: 10_000,
            compressed_bytes: 8_000,
            actual_saved_bytes: 2_000,
            files_processed: 10,
        },
        algorithm: CompressionAlgorithm::Xpress8K,
        duration_ms: 1,
    });
}

#[test]
fn startup_reconcile_queues_modified_game_when_last_compressed_is_older() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let watch_root = tempfile::TempDir::new().unwrap();
    let game_dir = watch_root.path().join("UpdatedGame");
    fs::create_dir_all(&game_dir).unwrap();
    fs::write(game_dir.join("game.exe"), vec![0_u8; 4096]).unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    add_compression_history(
        &game_dir,
        now_ms.saturating_sub(OLDER_THAN_RECENT_WINDOW_MS),
    );
    fs::write(game_dir.join("patch.bin"), vec![1_u8; 1024]).unwrap();

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[watch_root.path().to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert_eq!(queued.queued, 1);
    assert!(!queued.hit_cap);
    let queue = scheduler.queue_snapshot();
    assert_eq!(queue.len(), 1);
    assert_eq!(
        queue[0].kind,
        crate::automation::scheduler::JobKind::Reconcile
    );
}

#[test]
fn startup_reconcile_skips_game_without_compression_history() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let watch_root = tempfile::TempDir::new().unwrap();
    let game_dir = watch_root.path().join("NoHistoryGame");
    fs::create_dir_all(&game_dir).unwrap();
    fs::write(game_dir.join("game.exe"), vec![0_u8; 4096]).unwrap();

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[watch_root.path().to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert_eq!(queued.queued, 0);
    assert!(!queued.hit_cap);
    assert!(scheduler.queue_snapshot().is_empty());
}

#[test]
fn startup_reconcile_skips_when_folder_not_newer_than_last_compressed() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let watch_root = tempfile::TempDir::new().unwrap();
    let game_dir = watch_root.path().join("AlreadyCompressedGame");
    fs::create_dir_all(&game_dir).unwrap();
    fs::write(game_dir.join("game.exe"), vec![0_u8; 4096]).unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    add_compression_history(&game_dir, now_ms.saturating_add(60_000));

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[watch_root.path().to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert_eq!(queued.queued, 0);
    assert!(!queued.hit_cap);
    assert!(scheduler.queue_snapshot().is_empty());
}

#[test]
fn normalize_watch_paths_is_stable_and_deduped() {
    let normalized = normalize_watch_paths(&[
        r"C:\Games\".to_string(),
        r"c:/games".to_string(),
        r"D:\Library".to_string(),
    ]);
    assert_eq!(
        normalized,
        vec![r"c:\games".to_string(), r"d:\library".to_string()]
    );
}

#[test]
fn startup_reconcile_dedupes_equivalent_watch_roots() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let watch_root = tempfile::TempDir::new().unwrap();
    let game_dir = watch_root.path().join("DedupedRootGame");
    fs::create_dir_all(&game_dir).unwrap();
    fs::write(game_dir.join("game.exe"), vec![0_u8; 4096]).unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    add_compression_history(
        &game_dir,
        now_ms.saturating_sub(OLDER_THAN_RECENT_WINDOW_MS),
    );
    fs::write(game_dir.join("patch.bin"), vec![1_u8; 1024]).unwrap();

    let mut root_with_separator = watch_root.path().to_string_lossy().into_owned();
    if !root_with_separator.ends_with(std::path::MAIN_SEPARATOR) {
        root_with_separator.push(std::path::MAIN_SEPARATOR);
    }

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[
            watch_root.path().to_string_lossy().into_owned(),
            root_with_separator,
        ],
        &mut attempted,
    );

    assert_eq!(queued.queued, 1);
    assert!(!queued.hit_cap);
    assert_eq!(scheduler.queue_snapshot().len(), 1);
}

#[test]
fn startup_reconcile_handles_watch_path_that_is_itself_a_game_folder() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let game_dir = tempfile::TempDir::new().unwrap();
    fs::write(game_dir.path().join("game.exe"), vec![0_u8; 4096]).unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    add_compression_history(
        game_dir.path(),
        now_ms.saturating_sub(OLDER_THAN_RECENT_WINDOW_MS),
    );
    fs::write(game_dir.path().join("patch.bin"), vec![1_u8; 1024]).unwrap();

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[game_dir.path().to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert_eq!(queued.queued, 1);
    assert!(!queued.hit_cap);
    let queue = scheduler.queue_snapshot();
    assert_eq!(queue.len(), 1);
    assert_eq!(queue[0].game_path, game_dir.path());
}

#[test]
fn startup_change_marker_ignores_save_only_changes() {
    let game_dir = tempfile::TempDir::new().unwrap();
    fs::create_dir_all(game_dir.path().join("Save")).unwrap();
    fs::write(game_dir.path().join("game.exe"), vec![0_u8; 4096]).unwrap();

    let before = game_change_marker_ms(game_dir.path());
    fs::write(
        game_dir.path().join("Save").join("slot1.sav"),
        vec![1_u8; 1024],
    )
    .unwrap();
    let after = game_change_marker_ms(game_dir.path());

    assert_eq!(after, before);
}

#[test]
fn startup_reconcile_skips_recent_self_compression_echo() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let game_dir = tempfile::TempDir::new().unwrap();
    fs::write(game_dir.path().join("game.exe"), vec![0_u8; 4096]).unwrap();

    add_compression_history(game_dir.path(), crate::utils::unix_now_ms());

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[game_dir.path().to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert_eq!(queued.queued, 0);
    assert!(!queued.hit_cap);
    assert!(scheduler.queue_snapshot().is_empty());
}

#[test]
fn startup_reconcile_queues_recent_content_change_after_compression() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let game_dir = tempfile::TempDir::new().unwrap();
    fs::create_dir_all(game_dir.path().join("game").join("bin")).unwrap();
    add_compression_history(
        game_dir.path(),
        crate::utils::unix_now_ms().saturating_sub(5_000),
    );
    fs::write(
        game_dir.path().join("game").join("bin").join("patch.bin"),
        vec![1_u8; 4096],
    )
    .unwrap();

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[game_dir.path().to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert_eq!(queued.queued, 1);
    assert!(!queued.hit_cap);
    assert_eq!(scheduler.queue_snapshot().len(), 1);
}

#[test]
fn startup_reconcile_still_queues_content_changes() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let game_dir = tempfile::TempDir::new().unwrap();
    fs::create_dir_all(game_dir.path().join("game").join("bin")).unwrap();
    fs::write(
        game_dir.path().join("game").join("bin").join("engine2.dll"),
        vec![0_u8; 4096],
    )
    .unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    add_compression_history(
        game_dir.path(),
        now_ms.saturating_sub(OLDER_THAN_RECENT_WINDOW_MS),
    );
    fs::write(
        game_dir.path().join("game").join("bin").join("engine2.dll"),
        vec![1_u8; 8192],
    )
    .unwrap();

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[game_dir.path().to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert_eq!(queued.queued, 1);
    assert!(!queued.hit_cap);
    assert_eq!(scheduler.queue_snapshot().len(), 1);
}

#[test]
fn startup_reconcile_allows_content_change_under_ancestor_named_cache_dir() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let ancestor_dir = tempfile::TempDir::new().unwrap();
    let game_dir = ancestor_dir.path().join("cache").join("RealGame");
    fs::create_dir_all(game_dir.join("game").join("bin")).unwrap();
    fs::write(
        game_dir.join("game").join("bin").join("engine2.dll"),
        vec![0_u8; 4096],
    )
    .unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    add_compression_history(
        &game_dir,
        now_ms.saturating_sub(OLDER_THAN_RECENT_WINDOW_MS),
    );
    fs::write(
        game_dir.join("game").join("bin").join("engine2.dll"),
        vec![1_u8; 8192],
    )
    .unwrap();

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[game_dir.to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert_eq!(queued.queued, 1);
    assert!(!queued.hit_cap);
    assert_eq!(scheduler.queue_snapshot().len(), 1);
}

#[test]
fn startup_reconcile_caps_jobs_per_pass() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let watch_root = tempfile::TempDir::new().unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;

    for i in 0..(MAX_RECONCILE_JOBS_PER_PASS + 32) {
        let game_dir = watch_root.path().join(format!("ReconcileCapGame_{i}"));
        fs::create_dir_all(&game_dir).unwrap();
        fs::write(game_dir.join("game.exe"), vec![0_u8; 4096]).unwrap();
        add_compression_history(
            &game_dir,
            now_ms.saturating_sub(OLDER_THAN_RECENT_WINDOW_MS),
        );
        fs::write(game_dir.join("patch.bin"), vec![1_u8; 1024]).unwrap();
    }

    let mut scheduler = test_scheduler(&journal_dir);
    let mut attempted = HashSet::new();
    let queued = enqueue_closed_session_reconcile_jobs(
        &mut scheduler,
        &[watch_root.path().to_string_lossy().into_owned()],
        &mut attempted,
    );

    assert!(
        queued.queued <= MAX_RECONCILE_JOBS_PER_PASS,
        "queued jobs should never exceed per-pass cap"
    );
    assert!(
        queued.hit_cap,
        "expected cap marker when cap scenario is hit"
    );
    let queued_snapshot_len = scheduler.queue_snapshot().len();
    assert!(
        queued_snapshot_len > 0,
        "at least one reconcile job should be queued in cap scenario"
    );
    assert!(
        queued_snapshot_len <= queued.queued,
        "scheduler queue length should not exceed reported queued count"
    );
}

#[test]
fn startup_reconcile_skips_paths_already_attempted_in_prior_passes() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let watch_root = tempfile::TempDir::new().unwrap();
    let game_dir = watch_root.path().join("AttemptedPathGame");
    fs::create_dir_all(&game_dir).unwrap();
    fs::write(game_dir.join("game.exe"), vec![0_u8; 4096]).unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    add_compression_history(
        &game_dir,
        now_ms.saturating_sub(OLDER_THAN_RECENT_WINDOW_MS),
    );
    fs::write(game_dir.join("patch.bin"), vec![1_u8; 1024]).unwrap();

    let mut attempted = HashSet::new();
    let mut scheduler_first = test_scheduler(&journal_dir);
    let first = enqueue_closed_session_reconcile_jobs(
        &mut scheduler_first,
        &[watch_root.path().to_string_lossy().into_owned()],
        &mut attempted,
    );
    assert_eq!(first.queued, 1);
    assert!(!first.hit_cap);

    let mut scheduler_second = test_scheduler(&journal_dir);
    let second = enqueue_closed_session_reconcile_jobs(
        &mut scheduler_second,
        &[watch_root.path().to_string_lossy().into_owned()],
        &mut attempted,
    );
    assert_eq!(
        second.queued, 0,
        "already-attempted paths should not be requeued in later startup passes"
    );
    assert!(!second.hit_cap);
}

#[test]
fn startup_reconcile_reaches_candidates_beyond_first_capped_batch() {
    let journal_dir = tempfile::TempDir::new().unwrap();
    let watch_root = tempfile::TempDir::new().unwrap();

    let now_ms = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;

    for i in 0..(MAX_RECONCILE_JOBS_PER_PASS + 32) {
        let game_dir = watch_root.path().join(format!("LaterPassGame_{i:03}"));
        fs::create_dir_all(&game_dir).unwrap();
        fs::write(game_dir.join("game.exe"), vec![0_u8; 4096]).unwrap();
        add_compression_history(
            &game_dir,
            now_ms.saturating_sub(OLDER_THAN_RECENT_WINDOW_MS),
        );
        fs::write(game_dir.join("patch.bin"), vec![1_u8; 1024]).unwrap();
    }

    let mut candidates =
        build_startup_reconcile_candidates(&[watch_root.path().to_string_lossy().into_owned()]);
    assert!(
        candidates.len() > MAX_RECONCILE_JOBS_PER_PASS,
        "candidate queue should contain enough entries to require a second pass"
    );

    let mut attempted = HashSet::new();
    let mut scheduler_first = test_scheduler(&journal_dir);
    let first = enqueue_startup_reconcile_candidate_batch(
        &mut scheduler_first,
        &mut candidates,
        &mut attempted,
    );
    assert_eq!(first.queued, MAX_RECONCILE_JOBS_PER_PASS);
    assert!(first.hit_cap);
    assert_eq!(candidates.len(), 32);

    let mut scheduler_second = test_scheduler(&journal_dir);
    let second = enqueue_startup_reconcile_candidate_batch(
        &mut scheduler_second,
        &mut candidates,
        &mut attempted,
    );
    assert_eq!(second.queued, 32);
    assert!(!second.hit_cap);
    assert_eq!(scheduler_second.queue_snapshot().len(), 32);
    assert!(candidates.is_empty());
}
