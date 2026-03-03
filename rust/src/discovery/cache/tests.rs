use std::path::Path;

use super::*;

#[test]
fn change_token_detects_child_count_changes() {
    let dir = tempfile::TempDir::new().unwrap();
    let token_before = compute_change_token(dir.path(), true);
    std::fs::write(dir.path().join("test.bin"), b"data").unwrap();
    let token_after = compute_change_token(dir.path(), true);
    assert_ne!(token_before.child_count, token_after.child_count);
}

#[test]
fn change_token_probe_detects_nested_file_changes() {
    let dir = tempfile::TempDir::new().unwrap();
    let nested = dir.path().join("a").join("b");
    std::fs::create_dir_all(&nested).unwrap();
    let file = nested.join("probe.bin");
    std::fs::write(&file, b"v1").unwrap();

    let before = compute_change_token(dir.path(), true);
    std::fs::write(&file, b"v2-more-data").unwrap();
    let after = compute_change_token(dir.path(), true);
    assert_ne!(before.probe_total_size, after.probe_total_size);
}

#[test]
fn upsert_is_visible_before_persist_via_pending_map() {
    let dir = tempfile::TempDir::new().unwrap();
    let token = compute_change_token(dir.path(), false);
    upsert(
        dir.path(),
        token.clone(),
        CachedGameStats::from_parts(10, 10, false, false),
    );
    let hit = lookup(dir.path(), &token);
    assert!(hit.is_some());
}

#[test]
fn lookup_with_ttl_rejects_expired_entries() {
    let dir = tempfile::TempDir::new().unwrap();
    let token = compute_change_token(dir.path(), false);

    // Insert an entry with a timestamp far in the past.
    let old_stats = CachedGameStats {
        logical_size: 100,
        physical_size: 100,
        is_compressed: false,
        is_directstorage: false,
        updated_at_ms: 1_000, // ancient timestamp
    };
    upsert(dir.path(), token.clone(), old_stats);

    // Regular lookup (no TTL) should find it.
    assert!(lookup(dir.path(), &token).is_some());

    // TTL lookup with a 1ms max age should reject it.
    assert!(lookup_with_ttl(dir.path(), &token, 1).is_none());

    // TTL lookup with a very large max age should find it.
    assert!(lookup_with_ttl(dir.path(), &token, u64::MAX).is_some());
}

#[test]
fn lookup_fresh_accepts_recent_entries() {
    let dir = tempfile::TempDir::new().unwrap();
    let token = compute_change_token(dir.path(), false);
    upsert(
        dir.path(),
        token.clone(),
        CachedGameStats::from_parts(200, 200, false, false),
    );
    // Entry was just created, so lookup_fresh should find it.
    assert!(lookup_fresh(dir.path(), &token).is_some());
}

#[cfg(windows)]
#[test]
fn normalize_path_key_windows_is_case_insensitive() {
    let a = normalize_path_key(Path::new(r"C:\Games\Test\"));
    let b = normalize_path_key(Path::new(r"c:/games/test"));
    assert_eq!(a, b);
}
