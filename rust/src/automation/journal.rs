//! Crash-safe automation journal for pending compression jobs.
//!
//! Single serialized writer (Lesson 4): only one `JournalWriter` owns
//! persistence. Writes use atomic file replace (write .tmp, then rename)
//! to survive crashes.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

/// What triggered this automation job.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum JournalEventKind {
    /// New game installation detected by watcher.
    NewInstall,
    /// Game files modified (update/patch) - recompress changed files only.
    Reconcile,
    /// Opportunistic compression of uncompressed game found during scan.
    Opportunistic,
}

/// A single pending automation job entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JournalEntry {
    pub game_path: PathBuf,
    pub game_name: Option<String>,
    pub event_kind: JournalEventKind,
    /// Deduplication key: `"{canonical_path}:{update_epoch}"`.
    pub idempotency_key: String,
    pub queued_at: SystemTime,
}

impl JournalEntry {
    pub fn new(
        game_path: PathBuf,
        game_name: Option<String>,
        event_kind: JournalEventKind,
    ) -> Self {
        let epoch = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let canonical = game_path.to_string_lossy().to_ascii_lowercase();
        let idempotency_key = format!("{canonical}:{epoch}");
        Self {
            game_path,
            game_name,
            event_kind,
            idempotency_key,
            queued_at: SystemTime::now(),
        }
    }

    pub fn with_idempotency_key(
        game_path: PathBuf,
        game_name: Option<String>,
        event_kind: JournalEventKind,
        idempotency_key: String,
    ) -> Self {
        Self {
            game_path,
            game_name,
            event_kind,
            idempotency_key,
            queued_at: SystemTime::now(),
        }
    }
}

/// Durable writer for automation journal entries.
///
/// Thread-safe via interior `Mutex`. Uses atomic file replace for
/// crash safety: serialize to `.tmp`, then `fs::rename` over the real file.
pub struct JournalWriter {
    path: PathBuf,
    pending: Mutex<Vec<JournalEntry>>,
}

impl JournalWriter {
    /// Create a new writer targeting the given journal file path.
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            pending: Mutex::new(Vec::new()),
        }
    }

    /// Create a writer using the default `%APPDATA%/pressplay/automation_journal.json` path.
    pub fn default_path() -> Result<Self, std::io::Error> {
        let config_dir = dirs::config_dir().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::NotFound, "no config directory found")
        })?;
        let pressplay_dir = config_dir.join("pressplay");
        fs::create_dir_all(&pressplay_dir)?;
        Ok(Self::new(pressplay_dir.join("automation_journal.json")))
    }

    /// Insert an entry, deduplicating by idempotency key.
    pub fn insert(&self, entry: JournalEntry) {
        let mut pending = self.pending.lock().unwrap_or_else(|p| {
            log::warn!("Journal lock poisoned during insert; recovering");
            p.into_inner()
        });

        if pending
            .iter()
            .any(|e| e.idempotency_key == entry.idempotency_key)
        {
            return;
        }

        pending.push(entry);
    }

    /// Remove a completed or skipped entry by idempotency key.
    pub fn remove(&self, idempotency_key: &str) {
        let mut pending = self.pending.lock().unwrap_or_else(|p| {
            log::warn!("Journal lock poisoned during remove; recovering");
            p.into_inner()
        });
        pending.retain(|e| e.idempotency_key != idempotency_key);
    }

    /// Remove all entries whose idempotency key starts with the given prefix.
    /// Used for GameUninstalled events where we need to remove all jobs for a path
    /// regardless of the epoch suffix.
    pub fn remove_by_prefix(&self, prefix: &str) {
        let mut pending = self.pending.lock().unwrap_or_else(|p| {
            log::warn!("Journal lock poisoned during remove_by_prefix; recovering");
            p.into_inner()
        });
        pending.retain(|e| !e.idempotency_key.starts_with(prefix));
    }

    /// Get a snapshot of all pending entries.
    pub fn snapshot(&self) -> Vec<JournalEntry> {
        let pending = self.pending.lock().unwrap_or_else(|p| {
            log::warn!("Journal lock poisoned during snapshot; recovering");
            p.into_inner()
        });
        pending.clone()
    }

    /// Number of pending entries.
    pub fn len(&self) -> usize {
        let pending = self.pending.lock().unwrap_or_else(|p| {
            log::warn!("Journal lock poisoned during len; recovering");
            p.into_inner()
        });
        pending.len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Flush pending entries to disk using atomic file replace.
    ///
    /// Writes to a `.tmp` file first, then renames over the target path.
    pub fn flush(&self) -> Result<(), std::io::Error> {
        let snapshot = self.snapshot();
        let json = serde_json::to_string_pretty(&snapshot)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))?;

        let tmp_path = self.path.with_extension("json.tmp");

        // Ensure parent directory exists
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }

        fs::write(&tmp_path, &json)?;
        fs::rename(&tmp_path, &self.path)?;

        Ok(())
    }

    /// Load entries from disk into this writer, deduplicating with any
    /// entries already in memory.
    pub fn load(&self) -> Result<usize, std::io::Error> {
        let loaded = Self::load_from_path(&self.path)?;
        let mut pending = self.pending.lock().unwrap_or_else(|p| {
            log::warn!("Journal lock poisoned during load; recovering");
            p.into_inner()
        });

        let mut added = 0;
        for entry in loaded {
            if !pending
                .iter()
                .any(|e| e.idempotency_key == entry.idempotency_key)
            {
                pending.push(entry);
                added += 1;
            }
        }

        Ok(added)
    }

    /// Load entries from a specific path (static, no lock needed).
    pub fn load_from_path(path: &Path) -> Result<Vec<JournalEntry>, std::io::Error> {
        let contents = fs::read_to_string(path)?;
        let entries: Vec<JournalEntry> = serde_json::from_str(&contents)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))?;
        Ok(entries)
    }

    /// Replace all pending entries (used during restore from journal).
    pub fn replace_all(&self, entries: Vec<JournalEntry>) {
        let mut pending = self.pending.lock().unwrap_or_else(|p| {
            log::warn!("Journal lock poisoned during replace_all; recovering");
            p.into_inner()
        });
        *pending = entries;
    }

    /// Clear all pending entries.
    pub fn clear(&self) {
        let mut pending = self.pending.lock().unwrap_or_else(|p| {
            log::warn!("Journal lock poisoned during clear; recovering");
            p.into_inner()
        });
        pending.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn test_journal(dir: &TempDir) -> JournalWriter {
        JournalWriter::new(dir.path().join("test_journal.json"))
    }

    #[test]
    fn roundtrip_serialize_deserialize() {
        let dir = TempDir::new().unwrap();
        let writer = test_journal(&dir);

        let entry = JournalEntry::with_idempotency_key(
            PathBuf::from(r"C:\Games\TestGame"),
            Some("Test Game".to_string()),
            JournalEventKind::NewInstall,
            "c:\\games\\testgame:12345".to_string(),
        );
        writer.insert(entry.clone());
        writer.flush().unwrap();

        let loaded = JournalWriter::load_from_path(&dir.path().join("test_journal.json")).unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].idempotency_key, entry.idempotency_key);
        assert_eq!(loaded[0].game_path, entry.game_path);
        assert_eq!(loaded[0].game_name, entry.game_name);
        assert_eq!(loaded[0].event_kind, entry.event_kind);
    }

    #[test]
    fn burst_writes_produce_correct_output() {
        let dir = TempDir::new().unwrap();
        let writer = test_journal(&dir);

        for i in 0..20 {
            writer.insert(JournalEntry::with_idempotency_key(
                PathBuf::from(format!(r"C:\Games\Game{i}")),
                Some(format!("Game {i}")),
                JournalEventKind::NewInstall,
                format!("key_{i}"),
            ));
        }

        writer.flush().unwrap();
        let loaded = JournalWriter::load_from_path(&dir.path().join("test_journal.json")).unwrap();
        assert_eq!(loaded.len(), 20);
    }

    #[test]
    fn idempotency_key_deduplicates() {
        let dir = TempDir::new().unwrap();
        let writer = test_journal(&dir);

        let entry1 = JournalEntry::with_idempotency_key(
            PathBuf::from(r"C:\Games\TestGame"),
            Some("Test Game".to_string()),
            JournalEventKind::NewInstall,
            "same_key".to_string(),
        );
        let entry2 = JournalEntry::with_idempotency_key(
            PathBuf::from(r"C:\Games\TestGame"),
            Some("Test Game".to_string()),
            JournalEventKind::Reconcile,
            "same_key".to_string(),
        );

        writer.insert(entry1);
        writer.insert(entry2);

        assert_eq!(writer.len(), 1);
    }

    #[test]
    fn atomic_replace_survives_simulated_crash() {
        let dir = TempDir::new().unwrap();
        let writer = test_journal(&dir);

        // Write initial data
        writer.insert(JournalEntry::with_idempotency_key(
            PathBuf::from(r"C:\Games\Game1"),
            None,
            JournalEventKind::NewInstall,
            "key_1".to_string(),
        ));
        writer.flush().unwrap();

        // Simulate crash by leaving a .tmp file
        let tmp_path = dir.path().join("test_journal.json.tmp");
        fs::write(&tmp_path, "corrupted data").unwrap();

        // The real file should still be valid
        let loaded = JournalWriter::load_from_path(&dir.path().join("test_journal.json")).unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].idempotency_key, "key_1");
    }

    #[test]
    fn remove_entry() {
        let dir = TempDir::new().unwrap();
        let writer = test_journal(&dir);

        writer.insert(JournalEntry::with_idempotency_key(
            PathBuf::from(r"C:\Games\Game1"),
            None,
            JournalEventKind::NewInstall,
            "key_1".to_string(),
        ));
        writer.insert(JournalEntry::with_idempotency_key(
            PathBuf::from(r"C:\Games\Game2"),
            None,
            JournalEventKind::NewInstall,
            "key_2".to_string(),
        ));

        assert_eq!(writer.len(), 2);
        writer.remove("key_1");
        assert_eq!(writer.len(), 1);

        let snapshot = writer.snapshot();
        assert_eq!(snapshot[0].idempotency_key, "key_2");
    }

    #[test]
    fn load_merges_with_dedup() {
        let dir = TempDir::new().unwrap();
        let writer = test_journal(&dir);

        writer.insert(JournalEntry::with_idempotency_key(
            PathBuf::from(r"C:\Games\Game1"),
            None,
            JournalEventKind::NewInstall,
            "key_1".to_string(),
        ));
        writer.flush().unwrap();

        // Insert an in-memory entry with different key
        writer.insert(JournalEntry::with_idempotency_key(
            PathBuf::from(r"C:\Games\Game2"),
            None,
            JournalEventKind::NewInstall,
            "key_2".to_string(),
        ));

        // Load should not duplicate key_1 but should keep key_2
        let added = writer.load().unwrap();
        // key_1 already exists from insert, so load adds 0 from disk that are new
        assert_eq!(added, 0);
        assert_eq!(writer.len(), 2);
    }
}
