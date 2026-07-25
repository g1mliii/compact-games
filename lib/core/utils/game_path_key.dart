/// Canonical comparison key for a game folder path.
///
/// Windows paths are case-insensitive and accept either separator, so queue
/// admission, queue-position lookups, and restore failure matching must all
/// agree on one normalization. Mirrors `crate::utils::normalize_path_key` on
/// the Rust side; keep the two in sync when path edge cases (UNC, `\\?\`) are
/// handled.
String gamePathKey(String path) {
  var normalized = path.trim().replaceAll('/', r'\').toLowerCase();
  while (normalized.length > 3 && normalized.endsWith(r'\')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
