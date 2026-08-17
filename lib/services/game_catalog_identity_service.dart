import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/game_info.dart';
import 'rust_bridge_service.dart';

/// Folds a game title down to a comparison key.
///
/// Lowercases, strips diacritics, and collapses everything that is not
/// `[a-z0-9]` into single spaces, so "Pokémon: Legends – Z‑A" and
/// "pokemon legends z a" agree. Shared with cover art lookup so the two
/// features can never disagree about what counts as the same title.
String foldGameTitle(String value, {RustBridgeService? rustBridge}) {
  var folded = (rustBridge?.normalizeGameName(value) ?? value.trim())
      .toLowerCase();
  for (final entry in _diacriticFolds.entries) {
    folded = folded.replaceAll(entry.key, entry.value);
  }
  return folded
      .replaceAll(_nonAlphanumeric, ' ')
      .replaceAll(_repeatedWhitespace, ' ')
      .trim();
}

final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]+');
final RegExp _repeatedWhitespace = RegExp(r'\s+');

const Map<String, String> _diacriticFolds = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

/// Steam app-id lookup for a game folder.
///
/// Thin wrapper over Rust's discovery parser rather than a second ACF reader:
/// `rust/src/discovery/steam.rs` already reads `installdir` and the
/// fully-installed state flag, and a Dart copy would drift from it. There is
/// no cache here because the call is synchronous and Rust owns the manifest
/// caching.
abstract final class SteamAppIdLookup {
  /// Extracts the `steamapps` root from a game inside `steamapps\common\...`.
  ///
  /// Kept in Dart because cover art needs the path itself — it reads
  /// `appcache/librarycache` next to it — not just the id.
  static String? steamAppsPathFromGamePath(String gamePath) {
    const marker = r'\steamapps\common\';
    final lower = gamePath.toLowerCase();
    final markerIndex = lower.lastIndexOf(marker);
    if (markerIndex < 0) {
      return null;
    }
    return gamePath.substring(0, markerIndex + r'\steamapps'.length);
  }

  /// Returns the app id owning [gamePath], or null.
  ///
  /// [rustBridge] is optional so callers without a bridge (tests, or a path
  /// that is plainly not a Steam install) degrade to null rather than throw.
  static int? resolveAppId(String gamePath, RustBridgeService? rustBridge) {
    if (rustBridge == null || steamAppsPathFromGamePath(gamePath) == null) {
      return null;
    }
    try {
      final appId = rustBridge.lookupSteamAppId(gamePath);
      return appId != null && appId > 0 ? appId : null;
    } catch (_) {
      // The bridge is unavailable in some test and early-startup contexts;
      // a missing app id is a normal outcome, not an error.
      return null;
    }
  }
}

/// How a game's Steam app id was established.
enum GameCatalogIdentitySource {
  /// Discovery already knew the app id.
  nativeAppId,

  /// Read from a local `appmanifest_*.acf`.
  localManifest,

  /// A Steam catalog entry whose folded title matched exactly.
  strictCatalogMatch,

  /// No confident identity.
  none,
}

@immutable
class GameCatalogIdentity {
  const GameCatalogIdentity({
    required this.steamAppId,
    required this.foldedName,
    required this.source,
  });

  const GameCatalogIdentity.unknown(this.foldedName)
    : steamAppId = null,
      source = GameCatalogIdentitySource.none;

  final int? steamAppId;
  final String foldedName;
  final GameCatalogIdentitySource source;

  bool get isResolved => steamAppId != null;
}

/// Resolves a game to a Steam app id for features that must not guess.
///
/// Cover art can afford a near-miss — a slightly wrong capsule is a cosmetic
/// bug. News cannot: attributing another game's patch notes to your library is
/// wrong information, so the catalog step here accepts an **exact** folded
/// title match and nothing else. No prefix, contains, or closest-length
/// fallback.
///
/// Requests are deliberately independent of [CoverArtService]'s HTTP client so
/// a feature that is disabled or offline performs no work in the cover path.
class GameCatalogIdentityService {
  GameCatalogIdentityService({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  static const String _storeSearchHost = 'store.steampowered.com';
  static const Duration _requestTimeout = Duration(seconds: 8);
  static const int _maxCacheEntries = 256;
  static const int _maxResponseBytes = 512 * 1024;

  final http.Client Function() _clientFactory;
  http.Client? _client;

  /// Folded name to resolved identity. Bounded; unresolved lookups are cached
  /// too so a title that is genuinely not on Steam is asked about once.
  final LinkedHashMap<String, GameCatalogIdentity> _cache =
      LinkedHashMap<String, GameCatalogIdentity>();

  Future<GameCatalogIdentity> resolve(
    GameInfo game, {
    required bool allowNetwork,
    RustBridgeService? rustBridge,
  }) async {
    final folded = foldGameTitle(game.name, rustBridge: rustBridge);

    final nativeAppId = game.steamAppId;
    if (nativeAppId != null && nativeAppId > 0) {
      return GameCatalogIdentity(
        steamAppId: nativeAppId,
        foldedName: folded,
        source: GameCatalogIdentitySource.nativeAppId,
      );
    }

    if (game.platform == Platform.steam) {
      final fromManifest = SteamAppIdLookup.resolveAppId(game.path, rustBridge);
      if (fromManifest != null) {
        return GameCatalogIdentity(
          steamAppId: fromManifest,
          foldedName: folded,
          source: GameCatalogIdentitySource.localManifest,
        );
      }
    }

    if (folded.isEmpty) {
      return GameCatalogIdentity.unknown(folded);
    }

    final cached = _readCache(folded);
    if (cached != null) {
      return cached;
    }
    if (!allowNetwork) {
      // Not cached as unknown: offline is a temporary condition, and caching it
      // would suppress the lookup for the rest of the session.
      return GameCatalogIdentity.unknown(folded);
    }

    final identity = await _resolveFromCatalog(game.name, folded, rustBridge);
    _writeCache(folded, identity);
    return identity;
  }

  /// Exact-fold catalog lookup. Returns [GameCatalogIdentitySource.none] for
  /// anything short of an exact match, including a single extra word.
  Future<GameCatalogIdentity> _resolveFromCatalog(
    String rawName,
    String folded,
    RustBridgeService? rustBridge,
  ) async {
    final uri = Uri.https(_storeSearchHost, '/api/storesearch/', {
      'term': rawName.trim(),
      'l': 'english',
      'cc': 'US',
    });

    final json = await _getJson(uri);
    final items = json?['items'];
    if (items is! List) {
      return GameCatalogIdentity.unknown(folded);
    }

    int? exactAppId;
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final name = item['name'];
      final id = _readAppId(item['id']);
      if (name is! String || id == null) {
        continue;
      }
      if (foldGameTitle(name, rustBridge: rustBridge) != folded) {
        continue;
      }
      if (exactAppId != null && exactAppId != id) {
        // Titles are not unique in Steam's catalog. Picking the first of two
        // exact-name results could attribute another game's patch notes to the
        // user's library, so ambiguity is an unresolved identity.
        return GameCatalogIdentity.unknown(folded);
      }
      exactAppId = id;
    }
    return exactAppId == null
        ? GameCatalogIdentity.unknown(folded)
        : GameCatalogIdentity(
            steamAppId: exactAppId,
            foldedName: folded,
            source: GameCatalogIdentitySource.strictCatalogMatch,
          );
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final response = await (_client ??= _clientFactory())
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'User-Agent': 'CompactGames/0.1',
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200 ||
          response.bodyBytes.length > _maxResponseBytes) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static int? _readAppId(Object? value) {
    final id = switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v),
      _ => null,
    };
    return id != null && id > 0 ? id : null;
  }

  GameCatalogIdentity? _readCache(String foldedName) {
    final cached = _cache.remove(foldedName);
    if (cached != null) {
      _cache[foldedName] = cached;
    }
    return cached;
  }

  void _writeCache(String foldedName, GameCatalogIdentity identity) {
    _cache.remove(foldedName);
    _cache[foldedName] = identity;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Drops the lookup cache and closes the client. Safe to call repeatedly;
  /// the client is recreated lazily on the next request.
  void shutdown() {
    _cache.clear();
    _client?.close();
    _client = null;
  }

  @visibleForTesting
  int get debugCacheSize => _cache.length;
}
