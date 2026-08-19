import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/utils/bounded_list.dart';
import '../models/game_info.dart';
import '../models/game_player_count.dart';
import 'bounded_fanout.dart';
import 'bounded_json_http.dart';
import 'game_catalog_identity_service.dart';
import 'rust_bridge_service.dart';

/// Reads Steam's live player counter for the games in the library.
///
/// `GetNumberOfCurrentPlayers` is a keyless public endpoint that answers with a
/// single global number per app id — the same answer for everyone who asks, and
/// nothing about the person asking. No account, cookie, or API key is involved.
/// Resolving *which* app id to ask about can reach Steam by name for a game
/// with no local manifest (see [_appIdFor]); that is the same lookup cover art
/// already makes for those games, not a new one.
///
/// Shaped after [SteamNewsService]: its own client and permit queue, fixed
/// bounds rather than tuning knobs, and a generation counter so a shutdown
/// mid-flight publishes nothing.
class SteamPlayerCountService {
  SteamPlayerCountService({
    GameCatalogIdentityService? identityService,
    http.Client Function()? clientFactory,
  }) : _identity = identityService ?? GameCatalogIdentityService(),
       // A caller-supplied identity service is shared with the app's other
       // catalog consumers, so tearing this service down must not clear a
       // lookup cache it does not own.
       _ownsIdentity = identityService == null,
       _clientFactory = clientFactory ?? http.Client.new;

  static const String _host = 'api.steampowered.com';
  static const String _path = '/ISteamUserStats/GetNumberOfCurrentPlayers/v1/';

  /// Games asked about per refresh, largest install first. A reply is under
  /// fifty bytes, so this is bounded by politeness to Steam rather than by
  /// anything the app cannot afford.
  static const int maxCandidates = 32;

  /// Simultaneous in-flight requests. One notch above the news service's: the
  /// replies are a single number each, so the queue drains quickly.
  static const int maxConcurrency = 3;

  /// Rows the panel keeps. High enough to cover a whole ordinary library:
  /// a game with players is a row worth having, and cutting the list at six
  /// hid most of one.
  static const int maxVisibleItems = 20;

  static const Duration requestTimeout = Duration(seconds: 6);

  /// A well-formed reply is under 50 bytes. The bound is slack for headers of
  /// a future field, not a budget anything is expected to use.
  static const int _maxResponseBytes = 8 * 1024;

  final GameCatalogIdentityService _identity;
  final bool _ownsIdentity;
  final http.Client Function() _clientFactory;
  http.Client? _client;

  int _generation = 0;

  /// Counts for [games], busiest first, capped at [maxVisibleItems].
  ///
  /// Never throws: a total failure returns an empty list and the caller keeps
  /// whatever it was already showing.
  Future<List<GamePlayerCount>> refresh(
    List<GameInfo> games, {
    RustBridgeService? rustBridge,
  }) async {
    final generation = _generation;
    final candidates = orderPlayerCountCandidates(games);
    if (candidates.isEmpty) {
      return const <GamePlayerCount>[];
    }

    bool isCurrent() => _generation == generation;
    final collected = await collectBounded<GameInfo, GamePlayerCount>(
      candidates,
      concurrency: maxConcurrency,
      isCurrent: isCurrent,
      fetch: (game) => _fetchOne(game, rustBridge),
    );

    if (!isCurrent()) {
      return const <GamePlayerCount>[];
    }
    return rankPlayerCounts(collected);
  }

  Future<GamePlayerCount?> _fetchOne(
    GameInfo game,
    RustBridgeService? rustBridge,
  ) async {
    final generation = _generation;
    final appId = await _appIdFor(game, rustBridge);
    if (appId == null || _generation != generation) {
      return null;
    }

    final json = await getBoundedJson(
      _client ??= _clientFactory(),
      Uri.https(_host, _path, <String, String>{'appid': '$appId'}),
      timeout: requestTimeout,
      maxResponseBytes: _maxResponseBytes,
    );
    if (json == null || _generation != generation) {
      return null;
    }

    final players = parsePlayerCount(json);
    if (players == null) {
      return null;
    }
    return GamePlayerCount(gamePath: game.path, players: players);
  }

  /// The id the scanner knows, the game's own `appmanifest`, or — failing both
  /// — the Steam catalog, by name.
  ///
  /// The catalog step is what puts a game bought outside Steam on this panel:
  /// a repack in `C:\Games` has no manifest, and its only route to an app id
  /// is the same by-name lookup cover art already performs for it. That lookup
  /// sends the normalized folder name to Steam, and the identity service caches
  /// the answer, so a game resolved for its cover costs nothing here.
  Future<int?> _appIdFor(GameInfo game, RustBridgeService? rustBridge) async {
    final identity = await _identity.resolve(
      game,
      allowNetwork: true,
      rustBridge: rustBridge,
    );
    return identity.steamAppId;
  }

  /// Cancels in-flight work and drops the client.
  void shutdown() {
    _generation += 1;
    _client?.close();
    _client = null;
    if (_ownsIdentity) {
      _identity.shutdown();
    }
  }
}

/// The games worth asking Steam about, largest install first.
///
/// Every game is a candidate, not just the ones installed through Steam: a
/// title bought elsewhere is usually on Steam too, and its population is the
/// same number. The path tie-break keeps the order stable across runs so the
/// same games are asked about each time.
@visibleForTesting
List<GameInfo> orderPlayerCountCandidates(List<GameInfo> games) {
  final candidates = List<GameInfo>.of(games)
    ..sort((a, b) {
      final bySize = b.sizeBytes.compareTo(a.sizeBytes);
      if (bySize != 0) return bySize;
      return a.normalizedPath.compareTo(b.normalizedPath);
    });

  return cappedTo(candidates, SteamPlayerCountService.maxCandidates);
}

/// Busiest first, one row per game, capped for display.
@visibleForTesting
List<GamePlayerCount> rankPlayerCounts(List<GamePlayerCount> counts) {
  final sorted = List<GamePlayerCount>.of(counts)
    ..sort((a, b) {
      final byPlayers = b.players.compareTo(a.players);
      if (byPlayers != 0) return byPlayers;
      return a.gamePath.compareTo(b.gamePath);
    });

  final seen = <String>{};
  final ranked = <GamePlayerCount>[];
  for (final count in sorted) {
    if (!seen.add(count.gamePath)) {
      continue;
    }
    ranked.add(count);
    if (ranked.length == SteamPlayerCountService.maxVisibleItems) {
      break;
    }
  }
  return ranked;
}
