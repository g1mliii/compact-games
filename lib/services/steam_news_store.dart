import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_news_item.dart';

/// A persisted news snapshot plus how old it is.
@immutable
class CachedNewsSnapshot {
  const CachedNewsSnapshot({required this.items, required this.fetchedAt});

  static const CachedNewsSnapshot empty = CachedNewsSnapshot(
    items: <GameNewsItem>[],
    fetchedAt: null,
  );

  final List<GameNewsItem> items;
  final DateTime? fetchedAt;

  bool get isEmpty => items.isEmpty;

  bool isFreshAt(DateTime now) {
    final at = fetchedAt;
    if (at == null) {
      return false;
    }
    final age = now.difference(at);
    return !age.isNegative && age <= SteamNewsStore.freshness;
  }
}

/// Reads and writes the bounded news cache.
///
/// Two independent bounds apply on write — item count and encoded size —
/// because a handful of long titles can exceed the byte budget well before the
/// item cap is reached. Oldest items are dropped first.
class SteamNewsStore {
  const SteamNewsStore();

  static const String storageKey = 'compact_games_steam_news_v1';

  /// Refresh window. A snapshot older than this is shown but re-fetched.
  static const Duration freshness = Duration(hours: 6);

  /// Upper bound on persisted items.
  static const int maxPersistedItems = 24;

  /// Upper bound on the encoded payload.
  static const int maxPersistedBytes = 128 * 1024;

  Future<CachedNewsSnapshot> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decode(prefs.getString(storageKey));
    } catch (_) {
      // A corrupt or unavailable cache is not an error worth surfacing; the
      // shelf simply starts empty and refreshes.
      return CachedNewsSnapshot.empty;
    }
  }

  Future<void> save(List<GameNewsItem> items, {required DateTime now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = encode(items, now: now);
      if (encoded == null) {
        await prefs.remove(storageKey);
        return;
      }
      await prefs.setString(storageKey, encoded);
    } catch (_) {
      // Persistence is best effort; the in-memory shelf is unaffected.
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {
      // Nothing to do — the next load falls back to empty.
    }
  }

  /// Encodes at most [maxPersistedItems] newest items within
  /// [maxPersistedBytes]. Returns null when nothing is worth persisting.
  ///
  /// At the current field caps 24 items encode to roughly 30 KiB, so the byte
  /// budget never binds in practice — it is a guard against a future cap
  /// increase silently growing the payload. [maxBytes] exists so tests can
  /// still drive the shrink path.
  @visibleForTesting
  static String? encode(
    List<GameNewsItem> items, {
    required DateTime now,
    int maxBytes = maxPersistedBytes,
  }) {
    if (items.isEmpty) {
      return null;
    }

    final ordered = List<GameNewsItem>.of(items)
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    var kept = ordered.length > maxPersistedItems
        ? ordered.sublist(0, maxPersistedItems)
        : ordered;

    // Shrink from the oldest end until the encoded payload fits. Each pass
    // drops one item, so this terminates at the empty list in the worst case.
    while (kept.isNotEmpty) {
      final encoded = jsonEncode(<String, dynamic>{
        'fetchedAt': now.toUtc().millisecondsSinceEpoch,
        'items': kept.map((item) => item.toJson()).toList(),
      });
      if (encoded.length <= maxBytes) {
        return encoded;
      }
      kept = kept.sublist(0, kept.length - 1);
    }
    return null;
  }

  /// Decodes a persisted payload, dropping anything that fails revalidation.
  @visibleForTesting
  static CachedNewsSnapshot decode(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > maxPersistedBytes * 2) {
      return CachedNewsSnapshot.empty;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return CachedNewsSnapshot.empty;
    }
    if (decoded is! Map) {
      return CachedNewsSnapshot.empty;
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      return CachedNewsSnapshot.empty;
    }

    final items = <GameNewsItem>[];
    final seenIds = <String>{};
    for (final entry in rawItems) {
      if (items.length >= maxPersistedItems) {
        break;
      }
      final item = GameNewsItem.fromJson(entry);
      if (item == null || !seenIds.add(item.id)) {
        continue;
      }
      items.add(item);
    }
    if (items.isEmpty) {
      return CachedNewsSnapshot.empty;
    }

    items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    final fetchedAtMillis = decoded['fetchedAt'];
    return CachedNewsSnapshot(
      items: items,
      fetchedAt: fetchedAtMillis is int
          ? DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis, isUtc: true)
          : null,
    );
  }
}
