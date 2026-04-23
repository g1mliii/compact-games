use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::compression::algorithm::CompressionAlgorithm;
use crate::compression::history::{
    record_compression, ActualStats, CompressionHistoryEntry, EstimateSnapshot,
};

use super::coalescer::*;
use super::*;

fn record_test_compression(game_dir: &Path, timestamp_ms: u64) {
    record_compression(CompressionHistoryEntry {
        game_path: game_dir.to_string_lossy().into_owned(),
        game_name: game_dir
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("TestGame")
            .to_owned(),
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
        duration_ms: 10,
    });
}

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
fn user_state_paths_are_filtered() {
    assert!(is_user_state_subpath(std::path::Path::new(
        r"Save\slot1.sav"
    )));
    assert!(is_user_state_subpath(std::path::Path::new(
        r"cfg\user_keys_0_slot0.vcfg"
    )));
    assert!(is_user_state_subpath(std::path::Path::new(
        r"cache_154331883.soc"
    )));
    assert!(!is_user_state_subpath(std::path::Path::new(
        r"game\bin\win64\engine2.dll"
    )));
}

#[test]
fn resolve_game_folder_returns_first_child() {
    let watch_paths = vec![PathBuf::from(r"C:\Games")];
    let event_path = PathBuf::from(r"C:\Games\MyGame\data\level1.pak");
    let result = resolve_game_folder(&event_path, &watch_paths);
    assert_eq!(
        result.map(|resolved| resolved.path),
        Some(PathBuf::from(r"C:\Games\MyGame"))
    );
}

#[test]
fn resolve_game_folder_returns_known_watch_root_for_child_event() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("ExistingGame");
    std::fs::create_dir_all(&game_dir).unwrap();
    record_compression(CompressionHistoryEntry {
        game_path: game_dir.to_string_lossy().into_owned(),
        game_name: "ExistingGame".to_owned(),
        timestamp_ms: 1_700_000_123_456,
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
        duration_ms: 10,
    });

    let watch_paths = vec![game_dir.clone()];
    let event_path = game_dir.join("PatchFolder").join("payload.bin");
    let result = resolve_game_folder(&event_path, &watch_paths);
    assert_eq!(result.map(|resolved| resolved.path), Some(game_dir));
}

#[test]
fn create_folder_under_known_watch_root_emits_modified_for_game_root() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("WatchedGame");
    std::fs::create_dir_all(&game_dir).unwrap();
    record_compression(CompressionHistoryEntry {
        game_path: game_dir.to_string_lossy().into_owned(),
        game_name: "WatchedGame".to_owned(),
        timestamp_ms: 1_700_000_123_456,
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
        duration_ms: 10,
    });

    let new_folder = game_dir.join("PatchFolder");
    let event = notify::Event {
        kind: notify::EventKind::Create(notify::event::CreateKind::Folder),
        paths: vec![new_folder],
        attrs: notify::event::EventAttributes::new(),
    };
    let mut coalescer = EventCoalescer::new(Duration::ZERO);

    process_notify_event(&event, std::slice::from_ref(&game_dir), &mut coalescer);
    let settled = coalescer.drain_settled();

    assert_eq!(
        settled,
        vec![WatchEvent::GameModified {
            path: game_dir,
            game_name: Some("WatchedGame".to_owned()),
        }]
    );
}

#[test]
fn save_file_under_known_watch_root_is_ignored() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("WatchedGame");
    std::fs::create_dir_all(game_dir.join("Save")).unwrap();
    record_compression(CompressionHistoryEntry {
        game_path: game_dir.to_string_lossy().into_owned(),
        game_name: "WatchedGame".to_owned(),
        timestamp_ms: 1_700_000_123_456,
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
        duration_ms: 10,
    });

    let event = notify::Event {
        kind: notify::EventKind::Modify(notify::event::ModifyKind::Data(
            notify::event::DataChange::Any,
        )),
        paths: vec![game_dir.join("Save").join("slot1.sav")],
        attrs: notify::event::EventAttributes::new(),
    };
    let mut coalescer = EventCoalescer::new(Duration::ZERO);

    process_notify_event(&event, std::slice::from_ref(&game_dir), &mut coalescer);

    assert!(coalescer.drain_settled().is_empty());
}

#[test]
fn recent_self_compression_echo_is_ignored() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("RecentlyCompressedGame");
    std::fs::create_dir_all(game_dir.join("data")).unwrap();
    let payload = game_dir.join("data").join("payload.bin");
    std::fs::write(&payload, vec![1_u8; 4096]).unwrap();
    record_test_compression(&game_dir, crate::utils::unix_now_ms());

    let event = notify::Event {
        kind: notify::EventKind::Modify(notify::event::ModifyKind::Metadata(
            notify::event::MetadataKind::Any,
        )),
        paths: vec![payload],
        attrs: notify::event::EventAttributes::new(),
    };
    let mut coalescer = EventCoalescer::new(Duration::ZERO);

    process_notify_event(&event, std::slice::from_ref(&game_dir), &mut coalescer);

    assert!(coalescer.drain_settled().is_empty());
}

#[test]
fn recent_real_content_update_after_compression_is_queued() {
    let temp = tempfile::TempDir::new().unwrap();
    let game_dir = temp.path().join("RecentlyUpdatedGame");
    std::fs::create_dir_all(game_dir.join("data")).unwrap();
    record_test_compression(&game_dir, crate::utils::unix_now_ms().saturating_sub(5_000));
    let payload = game_dir.join("data").join("patch.bin");
    std::fs::write(&payload, vec![2_u8; 4096]).unwrap();

    let event = notify::Event {
        kind: notify::EventKind::Modify(notify::event::ModifyKind::Data(
            notify::event::DataChange::Any,
        )),
        paths: vec![payload],
        attrs: notify::event::EventAttributes::new(),
    };
    let mut coalescer = EventCoalescer::new(Duration::ZERO);

    process_notify_event(&event, std::slice::from_ref(&game_dir), &mut coalescer);

    assert_eq!(
        coalescer.drain_settled(),
        vec![WatchEvent::GameModified {
            path: game_dir,
            game_name: Some("RecentlyUpdatedGame".to_owned()),
        }]
    );
}

#[test]
fn ancestor_named_cache_does_not_filter_content_event() {
    let watch_root = PathBuf::from(r"D:\cache\SteamLibrary");
    let game_root = watch_root.join("TestGame");
    let event = notify::Event {
        kind: notify::EventKind::Modify(notify::event::ModifyKind::Data(
            notify::event::DataChange::Any,
        )),
        paths: vec![game_root.join("game").join("bin").join("engine2.dll")],
        attrs: notify::event::EventAttributes::new(),
    };
    let mut coalescer = EventCoalescer::new(Duration::ZERO);

    process_notify_event(&event, std::slice::from_ref(&watch_root), &mut coalescer);

    assert_eq!(
        coalescer.drain_settled(),
        vec![WatchEvent::GameModified {
            path: game_root,
            game_name: Some("TestGame".to_owned()),
        }]
    );
}

#[test]
fn resolve_game_folder_returns_none_for_unmatched() {
    let watch_paths = vec![PathBuf::from(r"C:\Games")];
    let event_path = PathBuf::from(r"D:\Other\stuff.txt");
    assert!(resolve_game_folder(&event_path, &watch_paths).is_none());
}

#[test]
fn game_name_extraction() {
    let path = PathBuf::from(r"C:\Games\Cyberpunk 2077");
    assert_eq!(
        game_name_from_path(&path),
        Some("Cyberpunk 2077".to_string())
    );
}

#[test]
fn update_config_starts_watcher_after_initial_empty_config() {
    let temp = tempfile::TempDir::new().unwrap();
    let mut watcher = GameWatcher::new(WatcherConfig::default());

    watcher.start().unwrap();
    assert!(!watcher.is_running());

    watcher.update_config(WatcherConfig {
        watch_paths: vec![temp.path().to_path_buf()],
        cooldown: Duration::from_millis(10),
    });

    assert!(watcher.is_running());
    assert!(watcher.event_channel().is_some());
    watcher.stop();
}

#[test]
fn update_config_stops_watcher_when_paths_become_empty() {
    let temp = tempfile::TempDir::new().unwrap();
    let mut watcher = GameWatcher::new(WatcherConfig {
        watch_paths: vec![temp.path().to_path_buf()],
        cooldown: Duration::from_millis(10),
    });

    watcher.start().unwrap();
    assert!(watcher.is_running());

    watcher.update_config(WatcherConfig::default());

    assert!(!watcher.is_running());
    assert!(watcher.event_channel().is_none());
}

#[test]
fn update_config_keeps_running_watcher_when_config_is_unchanged() {
    let temp = tempfile::TempDir::new().unwrap();
    let config = WatcherConfig {
        watch_paths: vec![temp.path().to_path_buf()],
        cooldown: Duration::from_millis(10),
    };
    let mut watcher = GameWatcher::new(config.clone());

    watcher.start().unwrap();
    assert!(watcher.is_running());
    let channel_before = watcher.event_channel().unwrap() as *const _;

    watcher.update_config(config);

    assert!(watcher.is_running());
    let channel_after = watcher.event_channel().unwrap() as *const _;
    assert_eq!(channel_before, channel_after);
    watcher.stop();
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
