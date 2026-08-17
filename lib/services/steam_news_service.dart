import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/utils/bounded_list.dart';
import '../models/game_info.dart';
import '../models/game_news_item.dart';
import 'bounded_json_http.dart';
import 'game_catalog_identity_service.dart';
import 'rust_bridge_service.dart';

/// Fetches at most one recent Steam Community item per candidate game.
///
/// Deliberately owns its own [http.Client] and permit queue rather than
/// sharing the cover art service's: news is optional and can be switched off,
/// and a disabled feature must cost the cover path nothing. All bounds —
/// candidate count, concurrency, per-item results, response size — are fixed
/// constants rather than tuning knobs.
class SteamNewsService {
  SteamNewsService({
    GameCatalogIdentityService? identityService,
    http.Client Function()? clientFactory,
  }) : _identity = identityService ?? GameCatalogIdentityService(),
       _clientFactory = clientFactory ?? http.Client.new;

  static const String _newsHost = 'api.steampowered.com';
  static const String _newsPath = '/ISteamNews/GetNewsForApp/v2/';

  /// Entries requested per game. Only the first usable one is kept; the rest are
  /// fallbacks for when the newest entries fail sanitization.
  static const int _newsFetchCount = 5;

  /// Games considered per refresh, ordered by [orderNewsCandidates].
  static const int maxCandidates = 16;

  /// Simultaneous in-flight requests.
  static const int maxConcurrency = 2;

  /// Items retained for display.
  static const int maxVisibleItems = 12;

  static const Duration requestTimeout = Duration(seconds: 8);
  static const int _maxResponseBytes = 256 * 1024;

  final GameCatalogIdentityService _identity;
  final http.Client Function() _clientFactory;
  http.Client? _client;

  /// Bumped by [shutdown]. Results captured under an older generation are
  /// discarded rather than published, which is what makes an offline flip or a
  /// disposed provider safe mid-flight.
  int _generation = 0;

  /// Refreshes the shelf for [games].
  ///
  /// Returns the newest [maxVisibleItems] sanitized, deduplicated items. Never
  /// throws: a total failure returns an empty list and the caller falls back to
  /// its cached snapshot.
  Future<List<GameNewsItem>> refresh(
    List<GameInfo> games, {
    RustBridgeService? rustBridge,
  }) async {
    final generation = _generation;
    final candidates = orderNewsCandidates(games);
    if (candidates.isEmpty) {
      return const <GameNewsItem>[];
    }

    final collected = <GameNewsItem>[];
    final queue = Queue<GameInfo>.of(candidates);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (_generation != generation) {
          return;
        }
        final game = queue.removeFirst();
        final item = await _fetchOne(game, generation, rustBridge);
        if (item != null && _generation == generation) {
          collected.add(item);
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < maxConcurrency; i++) worker(),
    ]);

    if (_generation != generation) {
      return const <GameNewsItem>[];
    }
    return dedupeAndTrimNews(collected);
  }

  Future<GameNewsItem?> _fetchOne(
    GameInfo game,
    int generation,
    RustBridgeService? rustBridge,
  ) async {
    final identity = await _identity.resolve(
      game,
      allowNetwork: true,
      rustBridge: rustBridge,
    );
    final appId = identity.steamAppId;
    if (appId == null || _generation != generation) {
      return null;
    }

    final uri = Uri.https(_newsHost, _newsPath, <String, String>{
      'appid': '$appId',
      // More than one entry so parseFirstNewsItem's skip-and-retry loop can do
      // its job: the newest post is often an external-RSS mirror whose URL
      // fails the trusted-host check, and at count=1 that silently costs the
      // game its whole news slot.
      'count': '$_newsFetchCount',
      // Ask Steam not to send the article body at all: the shelf shows a
      // headline, so downloading contents would be paid-for and discarded.
      'maxlength': '1',
      'format': 'json',
    });

    final json = await _getJson(uri);
    if (json == null || _generation != generation) {
      return null;
    }
    return parseFirstNewsItem(json, game: game, steamAppId: appId);
  }

  /// Timeouts, transport errors, and malformed bodies all arrive here as null,
  /// which the caller already treats as "no news".
  Future<Map<String, dynamic>?> _getJson(Uri uri) {
    return getBoundedJson(
      _client ??= _clientFactory(),
      uri,
      timeout: requestTimeout,
      maxResponseBytes: _maxResponseBytes,
    );
  }

  /// Cancels in-flight work, drops the client, and clears the identity cache.
  void shutdown() {
    _generation += 1;
    _client?.close();
    _client = null;
    _identity.shutdown();
  }
}

/// Picks and orders the games worth asking about.
///
/// Recently compressed first (that is what the user just acted on), then
/// larger installs, with the lowered path as a final tie-break so the order is
/// stable across runs. Capped at [SteamNewsService.maxCandidates].
@visibleForTesting
List<GameInfo> orderNewsCandidates(List<GameInfo> games) {
  final candidates = List<GameInfo>.of(games)
    ..sort((a, b) {
      final aAt = a.lastCompressed;
      final bAt = b.lastCompressed;
      if (aAt != null || bAt != null) {
        if (aAt == null) return 1;
        if (bAt == null) return -1;
        final byDate = bAt.compareTo(aAt);
        if (byDate != 0) return byDate;
      }
      final bySize = b.sizeBytes.compareTo(a.sizeBytes);
      if (bySize != 0) return bySize;
      return a.normalizedPath.compareTo(b.normalizedPath);
    });

  return cappedTo(candidates, SteamNewsService.maxCandidates);
}

/// Extracts and sanitizes the first usable entry from a GetNewsForApp payload.
@visibleForTesting
GameNewsItem? parseFirstNewsItem(
  Map<String, dynamic> json, {
  required GameInfo game,
  required int steamAppId,
}) {
  final appNews = json['appnews'];
  if (appNews is! Map) {
    return null;
  }
  final newsItems = appNews['newsitems'];
  if (newsItems is! List) {
    return null;
  }

  // Loop-invariant: the path does not depend on which entry wins, and a path
  // this item could never be keyed by disqualifies the whole payload.
  final gamePath = boundedNewsGamePath(game.path);
  if (gamePath == null) {
    return null;
  }

  for (final entry in newsItems) {
    if (entry is! Map) {
      continue;
    }
    final id = boundedNewsText(entry['gid'], maxNewsIdLength);
    final title = boundedNewsText(entry['title'], maxNewsTitleLength);
    final url = sanitizedNewsUrl(entry['url']);
    final date = entry['date'];
    if (id == null || title == null || url == null || date is! int) {
      continue;
    }

    // Steam reports seconds since epoch. Apply the same bounds used when
    // reading the cache so malformed live data cannot throw or sort forever.
    final publishedAt = boundedNewsTimestampFromSeconds(date);
    if (publishedAt == null) {
      continue;
    }

    return GameNewsItem(
      id: id,
      gamePath: gamePath,
      steamAppId: steamAppId,
      title: title,
      url: url,
      publishedAt: publishedAt,
    );
  }
  return null;
}

/// Deduplicates by stable id then by URL, newest first, capped for display.
@visibleForTesting
List<GameNewsItem> dedupeAndTrimNews(List<GameNewsItem> items) {
  final sorted = List<GameNewsItem>.of(items)
    ..sort((a, b) {
      final byDate = b.publishedAt.compareTo(a.publishedAt);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });

  final seenIds = <String>{};
  final seenUrls = <String>{};
  final deduped = <GameNewsItem>[];
  for (final item in sorted) {
    if (!seenIds.add(item.id) || !seenUrls.add(item.url)) {
      continue;
    }
    deduped.add(item);
    if (deduped.length == SteamNewsService.maxVisibleItems) {
      break;
    }
  }
  return deduped;
}
