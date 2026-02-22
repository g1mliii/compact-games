use std::path::PathBuf;
use std::time::Duration;

use super::coalescer::*;
use super::*;

#[test]
fn coalescer_single_event_settles_after_cooldown() {
    let mut coalescer = EventCoalescer::new(Duration::from_millis(50));
    coalescer.ingest(
        PathBuf::from(r"C:\Games\TestGame"),
        WatchEventKind::Installed,
        Some("TestGame".to_string()),
    );
    assert_eq!(coalescer.len(), 1);

    // Not yet settled
    let settled = coalescer.drain_settled();
    assert!(settled.is_empty());

    std::thread::sleep(Duration::from_millis(60));

    let settled = coalescer.drain_settled();
    assert_eq!(settled.len(), 1);
    assert_eq!(coalescer.len(), 0);
}

#[test]
fn coalescer_burst_events_same_path_produce_single_output() {
    let mut coalescer = EventCoalescer::new(Duration::from_millis(50));

    // Simulate burst of events for same path
    for _ in 0..10 {
        coalescer.ingest(
            PathBuf::from(r"C:\Games\TestGame"),
            WatchEventKind::Modified,
            Some("TestGame".to_string()),
        );
    }

    assert_eq!(coalescer.len(), 1);

    std::thread::sleep(Duration::from_millis(60));
    let settled = coalescer.drain_settled();
    assert_eq!(settled.len(), 1);
}

#[test]
fn coalescer_different_paths_produce_separate_events() {
    let mut coalescer = EventCoalescer::new(Duration::from_millis(50));

    coalescer.ingest(
        PathBuf::from(r"C:\Games\Game1"),
        WatchEventKind::Installed,
        Some("Game1".to_string()),
    );
    coalescer.ingest(
        PathBuf::from(r"C:\Games\Game2"),
        WatchEventKind::Modified,
        Some("Game2".to_string()),
    );

    assert_eq!(coalescer.len(), 2);

    std::thread::sleep(Duration::from_millis(60));
    let settled = coalescer.drain_settled();
    assert_eq!(settled.len(), 2);
}

#[test]
fn coalescer_reset_timer_on_new_event() {
    let mut coalescer = EventCoalescer::new(Duration::from_millis(100));

    coalescer.ingest(
        PathBuf::from(r"C:\Games\TestGame"),
        WatchEventKind::Modified,
        None,
    );

    // Wait 60ms and send another event (resets timer)
    std::thread::sleep(Duration::from_millis(60));
    coalescer.ingest(
        PathBuf::from(r"C:\Games\TestGame"),
        WatchEventKind::Modified,
        None,
    );

    // At 80ms total, not yet settled (timer was reset at 60ms)
    std::thread::sleep(Duration::from_millis(20));
    assert!(coalescer.drain_settled().is_empty());

    // Wait for full cooldown from last event
    std::thread::sleep(Duration::from_millis(90));
    assert_eq!(coalescer.drain_settled().len(), 1);
}

#[test]
fn coalescer_kind_updates_to_latest() {
    let mut coalescer = EventCoalescer::new(Duration::from_millis(50));

    coalescer.ingest(
        PathBuf::from(r"C:\Games\TestGame"),
        WatchEventKind::Installed,
        None,
    );
    coalescer.ingest(
        PathBuf::from(r"C:\Games\TestGame"),
        WatchEventKind::Modified,
        None,
    );

    std::thread::sleep(Duration::from_millis(60));
    let settled = coalescer.drain_settled();
    assert_eq!(settled.len(), 1);
    assert!(matches!(settled[0], WatchEvent::GameModified { .. }));
}

#[test]
fn noise_files_are_filtered() {
    assert!(is_noise_path(std::path::Path::new("desktop.ini")));
    assert!(is_noise_path(std::path::Path::new("foo.tmp")));
    assert!(is_noise_path(std::path::Path::new("Thumbs.db")));
    assert!(!is_noise_path(std::path::Path::new("game.exe")));
    assert!(!is_noise_path(std::path::Path::new("data.pak")));
}

#[test]
fn resolve_game_folder_returns_first_child() {
    let watch_paths = vec![PathBuf::from(r"C:\Games")];
    let event_path = PathBuf::from(r"C:\Games\MyGame\data\level1.pak");
    let result = resolve_game_folder(&event_path, &watch_paths);
    assert_eq!(result, Some(PathBuf::from(r"C:\Games\MyGame")));
}

#[test]
fn resolve_game_folder_returns_none_for_unmatched() {
    let watch_paths = vec![PathBuf::from(r"C:\Games")];
    let event_path = PathBuf::from(r"D:\Other\stuff.txt");
    assert_eq!(resolve_game_folder(&event_path, &watch_paths), None);
}

#[test]
fn game_name_extraction() {
    let path = PathBuf::from(r"C:\Games\Cyberpunk 2077");
    assert_eq!(
        game_name_from_path(&path),
        Some("Cyberpunk 2077".to_string())
    );
}

#[cfg(test)]
mod property_tests {
    use super::super::coalescer::*;
    use proptest::prelude::*;
    use std::path::PathBuf;
    use std::time::Duration;

    proptest! {
        /// P8: Event bursts for same path coalesce to at most 1 pending per settle window.
        #[test]
        fn burst_events_coalesce_to_at_most_one_per_path(
            event_count in 1usize..50,
            path_count in 1usize..5,
        ) {
            let mut coalescer = EventCoalescer::new(Duration::from_millis(10));

            let paths: Vec<PathBuf> = (0..path_count)
                .map(|i| PathBuf::from(format!(r"C:\Games\Game{i}")))
                .collect();

            for i in 0..event_count {
                let path = &paths[i % path_count];
                coalescer.ingest(path.clone(), WatchEventKind::Modified, None);
            }

            // While pending, at most path_count entries
            prop_assert!(coalescer.len() <= path_count);

            std::thread::sleep(Duration::from_millis(20));
            let settled = coalescer.drain_settled();
            prop_assert!(settled.len() <= path_count);
        }

        /// P12: Restart replays pending exactly once (via journal roundtrip).
        #[test]
        fn restart_replays_pending_exactly_once(entry_count in 1usize..10) {
            use crate::automation::journal::{JournalEntry, JournalEventKind, JournalWriter};
            use tempfile::TempDir;

            let dir = TempDir::new().unwrap();
            let writer = JournalWriter::new(dir.path().join("test.json"));

            for i in 0..entry_count {
                writer.insert(JournalEntry::with_idempotency_key(
                    PathBuf::from(format!(r"C:\Games\Game{i}")),
                    None,
                    JournalEventKind::NewInstall,
                    format!("key_{i}"),
                ));
            }
            writer.flush().unwrap();

            // Simulate restart: create new writer, load from disk
            let writer2 = JournalWriter::new(dir.path().join("test.json"));
            let added = writer2.load().unwrap();
            prop_assert_eq!(added, entry_count);
            prop_assert_eq!(writer2.len(), entry_count);

            // Loading again should add 0 (idempotent)
            let added_again = writer2.load().unwrap();
            prop_assert_eq!(added_again, 0);
            prop_assert_eq!(writer2.len(), entry_count);
        }
    }
}
