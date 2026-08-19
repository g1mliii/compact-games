import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/utils/bounded_list.dart';
import '../models/game_info.dart';
import '../models/game_news_item.dart';
import 'bounded_fanout.dart';
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
       // A caller-supplied identity service is shared with the app's other
       // catalog consumers, so tearing this service down must not clear a
       // lookup cache it does not own.
       _ownsIdentity = identityService == null,
       _clientFactory = clientFactory ?? http.Client.new;

  static const String _newsHost = 'api.steampowered.com';
  static const String _newsPath = '/ISteamNews/GetNewsForApp/v2/';

  /// Entries requested per game. Only the first usable one is kept; the rest are
  /// fallbacks for when the newest entries fail sanitization (a missing title
  /// or an out-of-range date).
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
  final bool _ownsIdentity;
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

    bool isCurrent() => _generation == generation;
    final collected = await collectBounded<GameInfo, GameNewsItem>(
      candidates,
      concurrency: maxConcurrency,
      isCurrent: isCurrent,
      fetch: (game) => _fetchOne(game, generation, rustBridge),
    );

    if (!isCurrent()) {
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
      // More than one entry so parseFirstNewsItem's skip-and-retry loop can
      // do its job: at count=1, a single malformed entry silently costs the
      // game its whole news slot.
      'count': '$_newsFetchCount',
      // No `maxlength`: asking Steam to shorten the body makes it strip the
      // markup itself and drop every line break with it, which arrives as one
      // unreadable run-on paragraph. The full contents keep their structure,
      // and boundedNewsBody does the shortening where the paragraphs are still
      // visible. Five full posts measure in the tens of kilobytes, well inside
      // [_maxResponseBytes].
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
    if (_ownsIdentity) {
      _identity.shutdown();
    }
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
    final date = entry['date'];
    if (id == null || title == null || date is! int) {
      continue;
    }

    // Steam's own `url` is a redirector on an untrusted host for practically
    // every entry, so the permalink built from the app id and gid is the
    // normal outcome, not the fallback. The reported link is still preferred
    // when it happens to be trusted, since that is the more specific page.
    final url =
        sanitizedNewsUrl(entry['url']) ?? steamNewsPermalink(steamAppId, id);
    if (url == null) {
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
      // Optional: an entry Steam sends with no contents is still a headline
      // worth showing, and the reader falls back to its link.
      body: boundedNewsBody(entry['contents']),
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
