import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/utils/bounded_lru.dart';
import '../models/game_info.dart';
import 'bounded_json_http.dart';
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
  // Each fold is a whole-string scan and reallocation, and almost every title
  // is pure ASCII. One codeUnit pass decides whether any of them can match.
  if (folded.codeUnits.any((unit) => unit > 0x7F)) {
    for (final entry in _diacriticFolds.entries) {
      folded = folded.replaceAll(entry.key, entry.value);
    }
  }
  return folded
      // Apostrophes close up rather than splitting the word. Steam writes
      // "Rina's Undercover" where the folder on disk says "Rinas Undercover";
      // turning the apostrophe into a space made those two fold to "rina s
      // undercover" and "rinas undercover", which match nothing in common.
      .replaceAll(_apostrophes, '')
      .replaceAll(_nonAlphanumeric, ' ')
      .replaceAll(_repeatedWhitespace, ' ')
      .trim();
}

/// The straight, curly, and modifier-letter apostrophes titles are written with.
final RegExp _apostrophes = RegExp("['’ʼ‘`]");
final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]+');
final RegExp _repeatedWhitespace = RegExp(r'\s+');

/// Words that mark a store entry as something sold *alongside* a game rather
/// than the game itself.
///
/// Steam's search returns a game's artbook, soundtrack, demo, and DLC beside
/// it, and those names are often *shorter* than the game's own — "Succubus
/// Successor - Digital Artbook" against "Succubus Successor: Delilah's Juicy
/// Journey". Any rule that prefers the closest name therefore lands on the
/// artbook, whose app id has no library capsule and no players.
const Set<String> _ancillaryStoreWords = <String>{
  'artbook',
  'soundtrack',
  'ost',
  'demo',
  'dlc',
  'wallpaper',
  'wallpapers',
  'bundle',
  'sdk',
  'trailer',
  'pass',
  'pack',
  'server',
  'beta',
  'playtest',
};

/// Whether [foldedCandidate] looks like an add-on for [foldedQuery] rather than
/// the game itself. Only the text beyond the query is examined, so a game
/// genuinely called "Pack" or "Beta" is unaffected.
///
/// Shared with cover art so the two lookups cannot disagree about which store
/// entry is the game.
bool isAncillaryStoreItem(String foldedCandidate, String foldedQuery) {
  if (!foldedCandidate.startsWith(foldedQuery)) {
    return false;
  }
  final extra = foldedCandidate.substring(foldedQuery.length);
  return extra
      .split(' ')
      .where((word) => word.isNotEmpty)
      .any(_ancillaryStoreWords.contains);
}

/// Words that make the text after a title another *release* of it, or another
/// game in the series — never a subtitle of the same thing.
const Set<String> _sequelOrEditionWords = <String>{
  'edition',
  'goty',
  'remaster',
  'remastered',
  'remake',
  'definitive',
  'complete',
  'deluxe',
  'ultimate',
  'collection',
  'anniversary',
  'enhanced',
  'redux',
  'classic',
  'hd',
  'vr',
  'reloaded',
};

/// Roman numerals a sequel is numbered with, up to the point sequels stop.
const Set<String> _romanNumerals = <String>{
  'ii',
  'iii',
  'iv',
  'v',
  'vi',
  'vii',
  'viii',
  'ix',
  'x',
};

/// Whether [foldedCandidate] is [foldedQuery] plus a subtitle — the same game
/// under the fuller name the store gives it.
///
/// Four things it must not accept, each of which is a different game or a
/// different SKU with its own app id, its own news, and its own population:
///
/// * a title that merely runs on from the query — "Portal" against
///   "PortalKnights", which the trailing space rules out;
/// * a sequel — "Portal" against "Portal 2", so a numbered continuation is out;
/// * another release of the same game — "The Witcher 3: Wild Hunt" against its
///   "Game of the Year Edition";
/// * the *next* game in a series, which is how series are usually named: one
///   word appended, no number in sight. "Portal Knights", "Half-Life Alyx",
///   and "Fallout Shelter" all fold to their predecessor plus a single word
///   and would otherwise sail through, handing a folder called "Portal" or
///   "Half Life" another game's app id.
///
/// That last one is why a subtitle has to be at least two words here. It costs
/// the odd real one-word subtitle, which leaves that game with no identity —
/// the outcome this file's header asks for over a confident wrong answer.
bool isSubtitledMatch(String foldedCandidate, String foldedQuery) {
  if (!foldedCandidate.startsWith('$foldedQuery ')) {
    return false;
  }

  final extra = foldedCandidate
      .substring(foldedQuery.length)
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();
  if (extra.length < 2) {
    return false;
  }
  // A number or numeral immediately after the title is a sequel, not a
  // subtitle. Deeper in, it is ordinary title text ("Train Operation 2000").
  final first = extra.first;
  if (int.tryParse(first) != null || _romanNumerals.contains(first)) {
    return false;
  }
  return !extra.any(_sequelOrEditionWords.contains);
}

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
/// caching: `lookup_steam_app_id_for_path` keeps a TTL-bounded folder-to-app-id
/// index per `steamapps` root, so resolving a whole refresh burst costs one
/// directory read rather than one per game.
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
  static Future<int?> resolveAppId(
    String gamePath,
    RustBridgeService? rustBridge,
  ) async {
    if (rustBridge == null || steamAppsPathFromGamePath(gamePath) == null) {
      return null;
    }
    try {
      final appId = await rustBridge.lookupSteamAppId(gamePath);
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
  const GameCatalogIdentity({required this.steamAppId, required this.source});

  static const GameCatalogIdentity unknown = GameCatalogIdentity(
    steamAppId: null,
    source: GameCatalogIdentitySource.none,
  );

  final int? steamAppId;
  final GameCatalogIdentitySource source;
}

/// Resolves a game to a Steam app id for features that must not guess.
///
/// Cover art can afford a near-miss — a slightly wrong capsule is a cosmetic
/// bug. News and player counts cannot: attributing another game's patch notes
/// or population to your library is wrong information. So the catalog step
/// accepts exactly two shapes and nothing looser — no contains, no
/// closest-length fallback:
///
/// * an exact folded title match, when only one entry has it; or
/// * a single entry that is the folded title plus a subtitle, once artbooks,
///   soundtracks, demos, and DLC are set aside.
///
/// The second exists because a folder is named more tersely than the store is
/// — "Rinas Undercover" on disk against "Rina's Undercover Train Operation" —
/// and a game whose folder disagrees with the store that way is not a game
/// this app should silently know nothing about. Two survivors is still an
/// unresolved identity: the folder name does not say which one it is.
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
        source: GameCatalogIdentitySource.nativeAppId,
      );
    }

    if (game.platform == Platform.steam) {
      final fromManifest = await SteamAppIdLookup.resolveAppId(
        game.path,
        rustBridge,
      );
      if (fromManifest != null) {
        return GameCatalogIdentity(
          steamAppId: fromManifest,
          source: GameCatalogIdentitySource.localManifest,
        );
      }
    }

    if (folded.isEmpty) {
      return GameCatalogIdentity.unknown;
    }

    final cached = _readCache(folded);
    if (cached != null) {
      return cached;
    }
    if (!allowNetwork) {
      // Not cached as unknown: offline is a temporary condition, and caching it
      // would suppress the lookup for the rest of the session.
      return GameCatalogIdentity.unknown;
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
      return GameCatalogIdentity.unknown;
    }

    int? exactAppId;
    // Candidates whose name is the folder's name plus a subtitle. Steam titles
    // an installed folder's game more fully than the folder does — "Rina's
    // Undercover Train Operation" lives in "Rinas Undercover" — so an
    // exact-only rule leaves those games with no identity at all.
    final subtitled = <int>{};
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final name = item['name'];
      final id = _readAppId(item['id']);
      if (name is! String || id == null) {
        continue;
      }
      final candidate = foldGameTitle(name, rustBridge: rustBridge);
      if (candidate != folded) {
        if (isSubtitledMatch(candidate, folded) &&
            !isAncillaryStoreItem(candidate, folded)) {
          subtitled.add(id);
        }
        continue;
      }
      if (exactAppId != null && exactAppId != id) {
        // Titles are not unique in Steam's catalog. Picking the first of two
        // exact-name results could attribute another game's patch notes to the
        // user's library, so ambiguity is an unresolved identity.
        return GameCatalogIdentity.unknown;
      }
      exactAppId = id;
    }
    if (exactAppId != null) {
      return GameCatalogIdentity(
        steamAppId: exactAppId,
        source: GameCatalogIdentitySource.strictCatalogMatch,
      );
    }
    // One survivor is an answer; several means the folder name does not say
    // which game it is, and guessing would put another game's news and player
    // count on this one.
    if (subtitled.length == 1) {
      return GameCatalogIdentity(
        steamAppId: subtitled.first,
        source: GameCatalogIdentitySource.strictCatalogMatch,
      );
    }
    return GameCatalogIdentity.unknown;
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) {
    return getBoundedJson(
      _client ??= _clientFactory(),
      uri,
      timeout: _requestTimeout,
      maxResponseBytes: _maxResponseBytes,
    );
  }

  /// A store item's id, rejecting the non-positive values Steam never uses.
  static int? _readAppId(Object? value) {
    final id = readJsonInt(value);
    return id != null && id > 0 ? id : null;
  }

  GameCatalogIdentity? _readCache(String foldedName) =>
      readLru(_cache, foldedName);

  void _writeCache(String foldedName, GameCatalogIdentity identity) =>
      writeLru(_cache, foldedName, identity, maxEntries: _maxCacheEntries);

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
