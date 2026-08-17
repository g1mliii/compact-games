/// Bounded least-recently-used maps over [LinkedHashMap].
///
/// [LinkedHashMap] preserves insertion order, so "touch" is remove-then-insert
/// and eviction is dropping the first key. These are the three operations every
/// in-memory lookup cache in the app needs; keeping one implementation means a
/// cache cannot accidentally be unbounded or forget to refresh recency.
library;

import 'dart:collection';

/// Reads [key], refreshing its recency so it evicts last.
V? readLru<K, V>(LinkedHashMap<K, V> cache, K key) {
  final cached = cache.remove(key);
  if (cached != null) {
    cache[key] = cached;
  }
  return cached;
}

/// Writes [value] as the most recently used entry, then trims to [maxEntries].
void writeLru<K, V>(
  LinkedHashMap<K, V> cache,
  K key,
  V value, {
  required int maxEntries,
}) {
  cache.remove(key);
  cache[key] = value;
  trimLru(cache, maxEntries);
}

/// Evicts the least recently used entries until at most [maxEntries] remain.
void trimLru<K, V>(LinkedHashMap<K, V> cache, int maxEntries) {
  while (cache.length > maxEntries) {
    cache.remove(cache.keys.first);
  }
}
