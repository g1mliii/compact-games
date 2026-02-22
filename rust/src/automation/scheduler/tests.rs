use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, LazyLock, Mutex};

use tempfile::TempDir;

use super::*;
use crate::automation::journal::JournalWriter;

static TEST_MUTEX: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

fn test_scheduler() -> (AutoScheduler, TempDir) {
    let dir = TempDir::new().unwrap();
    let journal = JournalWriter::new(dir.path().join("test_journal.json"));
    let config = SchedulerConfig {
        cooldown: std::time::Duration::from_millis(10),
        ..Default::default()
    };
    (AutoScheduler::new(config, journal), dir)
}

fn make_event(path: &str) -> WatchEvent {
    WatchEvent::GameInstalled {
        path: PathBuf::from(path),
        game_name: Some(path.rsplit('\\').next().unwrap_or(path).to_string()),
    }
}

fn make_modify_event(path: &str) -> WatchEvent {
    WatchEvent::GameModified {
        path: PathBuf::from(path),
        game_name: Some(path.rsplit('\\').next().unwrap_or(path).to_string()),
    }
}

#[test]
fn initial_state_is_waiting_for_events() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (scheduler, _dir) = test_scheduler();
    assert_eq!(scheduler.state(), SchedulerState::WaitingForEvents);
}

#[test]
fn event_transitions_to_waiting_for_settle() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();
    scheduler.on_event(make_event(r"C:\Games\TestGame"));
    assert_eq!(scheduler.state(), SchedulerState::WaitingForSettle);
}

#[test]
fn settle_complete_transitions_to_waiting_for_idle() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();
    scheduler.on_event(make_event(r"C:\Games\TestGame"));

    // Consume persist action
    let _ = scheduler.tick(false, false);

    std::thread::sleep(std::time::Duration::from_millis(20));
    let _ = scheduler.tick(false, false);
    assert_eq!(scheduler.state(), SchedulerState::WaitingForIdle);
}

#[test]
fn idle_detected_transitions_to_safety_check() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();
    scheduler.on_event(make_event(r"C:\Games\TestGame"));

    // Consume persist
    let _ = scheduler.tick(false, false);

    std::thread::sleep(std::time::Duration::from_millis(20));
    // Settle
    let _ = scheduler.tick(false, false);
    assert_eq!(scheduler.state(), SchedulerState::WaitingForIdle);

    // Idle detected
    let _ = scheduler.tick(true, false);
    assert_eq!(scheduler.state(), SchedulerState::SafetyCheck);
}

#[test]
fn safety_pass_transitions_to_compressing() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();
    scheduler.on_event(make_event(r"C:\Games\TestGame"));

    // Advance through states
    let _ = scheduler.tick(false, false); // persist
    std::thread::sleep(std::time::Duration::from_millis(20));
    let _ = scheduler.tick(false, false); // settle -> WaitingForIdle
    let _ = scheduler.tick(true, false); // idle -> SafetyCheck

    let action = scheduler.tick(true, false); // safety -> Compressing
    assert!(matches!(action, Some(SchedulerAction::Compress(_))));
    assert_eq!(scheduler.state(), SchedulerState::Compressing);
}

#[test]
fn completion_returns_to_waiting_or_next_job() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();
    scheduler.on_event(make_event(r"C:\Games\TestGame"));

    let _ = scheduler.tick(false, false);
    std::thread::sleep(std::time::Duration::from_millis(20));
    let _ = scheduler.tick(false, false);
    let _ = scheduler.tick(true, false);

    if let Some(SchedulerAction::Compress(job)) = scheduler.tick(true, false) {
        scheduler.job_completed(&job.idempotency_key);
    }

    assert_eq!(scheduler.state(), SchedulerState::WaitingForEvents);
}

#[test]
fn safety_fail_transitions_to_backoff() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();
    scheduler.on_event(make_event(r"C:\Games\TestGame"));
    scheduler.on_event(make_event(r"C:\Games\TestGame2"));

    let _ = scheduler.tick(false, false);
    std::thread::sleep(std::time::Duration::from_millis(20));
    let _ = scheduler.tick(false, false);
    let _ = scheduler.tick(true, false);

    if let Some(SchedulerAction::Compress(job)) = scheduler.tick(true, false) {
        scheduler.job_failed(&job.idempotency_key, "test failure".to_string());
    }

    assert_eq!(scheduler.state(), SchedulerState::Backoff);
}

#[test]
fn user_activity_pauses_compression() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();
    scheduler.on_event(make_event(r"C:\Games\TestGame"));

    let _ = scheduler.tick(false, false);
    std::thread::sleep(std::time::Duration::from_millis(20));
    let _ = scheduler.tick(false, false);
    let _ = scheduler.tick(true, false);
    let _ = scheduler.tick(true, false); // starts compressing

    // User becomes active
    let _ = scheduler.tick(false, false);
    assert_eq!(scheduler.state(), SchedulerState::Paused);
}

#[test]
fn resume_from_paused() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();
    scheduler.on_event(make_event(r"C:\Games\TestGame"));

    let _ = scheduler.tick(false, false);
    std::thread::sleep(std::time::Duration::from_millis(20));
    let _ = scheduler.tick(false, false);
    let _ = scheduler.tick(true, false);
    let _ = scheduler.tick(true, false);
    let _ = scheduler.tick(false, false); // paused

    assert_eq!(scheduler.state(), SchedulerState::Paused);
    scheduler.resume();
    assert_eq!(scheduler.state(), SchedulerState::WaitingForIdle);
}

#[test]
fn excluded_path_is_skipped() {
    let _g = TEST_MUTEX.lock().unwrap();
    let dir = TempDir::new().unwrap();
    let journal = JournalWriter::new(dir.path().join("test.json"));
    let mut excluded = HashSet::new();
    excluded.insert(r"c:\games\excluded".to_string());
    let config = SchedulerConfig {
        cooldown: std::time::Duration::from_millis(10),
        excluded_paths: excluded,
        ..Default::default()
    };
    let mut scheduler = AutoScheduler::new(config, journal);

    scheduler.on_event(WatchEvent::GameInstalled {
        path: PathBuf::from(r"C:\Games\Excluded"),
        game_name: Some("Excluded".to_string()),
    });

    assert_eq!(scheduler.pending_queue_len(), 0);
    assert_eq!(scheduler.state(), SchedulerState::WaitingForEvents);
}

#[test]
fn duplicate_idempotency_key_rejected() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();

    scheduler.on_event(make_event(r"C:\Games\TestGame"));
    let initial_len = scheduler.pending_queue_len();

    // Same event again (same path should be deduped)
    scheduler.on_event(make_event(r"C:\Games\TestGame"));
    assert_eq!(scheduler.pending_queue_len(), initial_len);
}

#[test]
fn crash_recovery_replays_pending_jobs() {
    let _g = TEST_MUTEX.lock().unwrap();
    let dir = TempDir::new().unwrap();
    let journal_path = dir.path().join("test.json");

    // First scheduler: add jobs and persist
    {
        let journal = JournalWriter::new(journal_path.clone());
        let config = SchedulerConfig::default();
        let mut scheduler = AutoScheduler::new(config, journal);
        scheduler.on_event(make_event(r"C:\Games\Game1"));
        scheduler.on_event(make_event(r"C:\Games\Game2"));
        scheduler.persist().unwrap();
    }

    // Second scheduler: restore from journal
    {
        let journal = JournalWriter::new(journal_path);
        let config = SchedulerConfig::default();
        let scheduler = AutoScheduler::restore_or_new(config, journal);
        assert_eq!(scheduler.pending_queue_len(), 2);
        assert_eq!(scheduler.state(), SchedulerState::WaitingForIdle);
    }
}

#[test]
fn game_modified_creates_reconcile_job() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();

    scheduler.on_event(make_modify_event(r"C:\Games\TestGame"));

    let snapshot = scheduler.queue_snapshot();
    assert_eq!(snapshot.len(), 1);
    assert_eq!(snapshot[0].kind, JobKind::Reconcile);
}

#[test]
fn queue_bounded_at_64() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();

    for i in 0..70 {
        scheduler.on_event(WatchEvent::GameInstalled {
            path: PathBuf::from(format!(r"C:\Games\Game{i}")),
            game_name: Some(format!("Game{i}")),
        });
    }

    assert!(scheduler.queue.len() <= MAX_QUEUE_SIZE);
}

#[test]
fn backoff_exponential_with_cap() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();

    // Simulate multiple failures
    for i in 0..10 {
        scheduler.on_event(WatchEvent::GameInstalled {
            path: PathBuf::from(format!(r"C:\Games\FailGame{i}")),
            game_name: None,
        });
        let _ = scheduler.tick(false, false); // persist
        std::thread::sleep(std::time::Duration::from_millis(20));
        let _ = scheduler.tick(false, false); // settle
        let _ = scheduler.tick(true, false); // idle -> safety
        if let Some(SchedulerAction::Compress(job)) = scheduler.tick(true, false) {
            scheduler.job_failed(&job.idempotency_key, "test".to_string());
        }
    }

    // Backoff should exist and not exceed MAX_BACKOFF
    if let Some(until) = scheduler.backoff_until {
        let remaining = until.saturating_duration_since(std::time::Instant::now());
        assert!(remaining <= MAX_BACKOFF);
    }
}

#[test]
fn pause_resume_does_not_deadlock() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();

    for _ in 0..100 {
        scheduler.pause();
        scheduler.resume();
    }
    // Should complete without deadlock
    assert_eq!(scheduler.state(), SchedulerState::WaitingForEvents);
}

#[test]
fn concurrent_event_ingestion_safe() {
    let _g = TEST_MUTEX.lock().unwrap();
    let dir = TempDir::new().unwrap();
    let journal = JournalWriter::new(dir.path().join("test.json"));
    let config = SchedulerConfig {
        cooldown: std::time::Duration::from_millis(10),
        ..Default::default()
    };
    let scheduler = Arc::new(Mutex::new(AutoScheduler::new(config, journal)));

    let s1 = scheduler.clone();
    let h1 = std::thread::spawn(move || {
        for i in 0..20 {
            let mut s = s1.lock().unwrap();
            s.on_event(WatchEvent::GameInstalled {
                path: PathBuf::from(format!(r"C:\Games\Thread1Game{i}")),
                game_name: None,
            });
        }
    });

    let s2 = scheduler.clone();
    let h2 = std::thread::spawn(move || {
        for i in 0..20 {
            let mut s = s2.lock().unwrap();
            s.on_event(WatchEvent::GameInstalled {
                path: PathBuf::from(format!(r"C:\Games\Thread2Game{i}")),
                game_name: None,
            });
        }
    });

    h1.join().unwrap();
    h2.join().unwrap();

    let s = scheduler.lock().unwrap();
    assert!(s.pending_queue_len() > 0);
}

#[test]
fn prune_finished_removes_old_completed_jobs() {
    let _g = TEST_MUTEX.lock().unwrap();
    let (mut scheduler, _dir) = test_scheduler();

    // Add and complete many jobs
    for i in 0..20 {
        scheduler.on_event(WatchEvent::GameInstalled {
            path: PathBuf::from(format!(r"C:\Games\PruneGame{i}")),
            game_name: None,
        });
        let _ = scheduler.tick(false, false); // persist
        std::thread::sleep(std::time::Duration::from_millis(15));
        let _ = scheduler.tick(false, false); // settle
        let _ = scheduler.tick(true, false); // idle -> safety
        if let Some(SchedulerAction::Compress(job)) = scheduler.tick(true, false) {
            scheduler.job_completed(&job.idempotency_key);
            // Consume the persist action from job_completed
            let _ = scheduler.tick(true, false);
        }
    }

    // Finished jobs should be capped at MAX_FINISHED_JOBS
    let finished = scheduler
        .queue
        .iter()
        .filter(|j| {
            matches!(
                j.status,
                JobStatus::Completed | JobStatus::Failed | JobStatus::Skipped
            )
        })
        .count();
    assert!(finished <= MAX_FINISHED_JOBS);
}
