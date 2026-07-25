part of 'cover_art_service.dart';

const String _steamStoreSearchHost = 'store.steampowered.com';
const String _steamStoreBrowseHost = 'api.steampowered.com';
const String _steamStoreAssetHost = 'shared.akamai.steamstatic.com';

final LinkedHashMap<String, int> _steamStoreAppIdCache =
    LinkedHashMap<String, int>();
final LinkedHashMap<int, String> _steamStoreCoverUrlCache =
    LinkedHashMap<int, String>();

extension _CoverArtServiceStore on CoverArtService {
  Future<CoverArtResult?> _resolveSteamStoreCover(
    GameInfo game, {
    required String cacheKey,
    String? alternateLookupName,
    required RustBridgeService? rustBridge,
  }) async {
    try {
      int? appId = game.steamAppId;
      if (appId == null && game.platform == Platform.steam) {
        appId = int.tryParse(
          await _resolveSteamAppIdFromGamePath(game.path) ?? '',
        );
      }

      if (appId == null) {
        final lookupNames = <String>[game.name, ?alternateLookupName];
        final seen = <String>{};
        for (final lookupName in lookupNames) {
          final folded = _foldSteamStoreTitle(lookupName, rustBridge);
          if (folded.isEmpty || !seen.add(folded)) {
            continue;
          }
          appId = await _searchSteamStoreAppId(lookupName, rustBridge);
          if (appId != null) {
            break;
          }
        }
      }
      if (appId == null) {
        return null;
      }

      final imageUrl = await _findSteamStoreCoverUrl(appId);
      if (imageUrl == null) {
        return null;
      }
      final path = await _downloadRemoteImageIntoCache(
        cacheKey,
        imageUrl,
        source: CoverArtSource.steamStoreApi,
      );
      if (path == null) {
        return null;
      }
      return CoverArtResult(
        uri: File(path).uri.toString(),
        source: CoverArtSource.steamStoreApi,
        revision: _bumpCoverRevision(cacheKey),
      );
    } catch (_) {
      return null;
    }
  }

  Future<int?> _searchSteamStoreAppId(
    String gameName,
    RustBridgeService? rustBridge,
  ) async {
    final foldedName = _foldSteamStoreTitle(gameName, rustBridge);
    if (foldedName.isEmpty) {
      return null;
    }
    final cached = _readApiLru(_steamStoreAppIdCache, foldedName);
    if (cached != null) {
      return cached;
    }

    final uri = Uri.https(_steamStoreSearchHost, '/api/storesearch/', {
      'term': gameName.trim(),
      'l': 'english',
      'cc': 'US',
    });
    final json = await _steamStoreGetJson(uri);
    final items = json?['items'];
    if (items is! List) {
      return null;
    }

    final queryWordCount = foldedName
        .split(' ')
        .where((word) => word.isNotEmpty)
        .length;
    int? closestId;
    var closestExtraLength = 1 << 30;
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final name = item['name'];
      final id = _readInt(item['id']);
      if (name is! String || id == null) {
        continue;
      }
      final foldedCandidate = _foldSteamStoreTitle(name, rustBridge);
      if (foldedCandidate == foldedName) {
        _writeApiLru(_steamStoreAppIdCache, foldedName, id);
        return id;
      }
      if (queryWordCount < 2 || !foldedCandidate.contains(foldedName)) {
        continue;
      }
      final extraLength = foldedCandidate.length - foldedName.length;
      if (extraLength >= 0 && extraLength < closestExtraLength) {
        closestId = id;
        closestExtraLength = extraLength;
      }
    }
    if (closestId != null) {
      _writeApiLru(_steamStoreAppIdCache, foldedName, closestId);
    }
    return closestId;
  }

  Future<String?> _findSteamStoreCoverUrl(int appId) async {
    final cached = _readApiLru(_steamStoreCoverUrlCache, appId);
    if (cached != null) {
      return cached;
    }

    final input = jsonEncode({
      'ids': [
        {'appid': appId},
      ],
      'context': {'language': 'english', 'country_code': 'US'},
      'data_request': {'include_assets': true},
    });
    final uri = Uri.https(
      _steamStoreBrowseHost,
      '/IStoreBrowseService/GetItems/v1/',
      {'input_json': input},
    );
    final json = await _steamStoreGetJson(uri);
    final response = json?['response'];
    if (response is! Map) {
      return null;
    }
    final items = response['store_items'];
    if (items is! List) {
      return null;
    }

    for (final item in items) {
      if (item is! Map || _readInt(item['appid']) != appId) {
        continue;
      }
      final assets = item['assets'];
      if (assets is! Map) {
        continue;
      }
      final format = assets['asset_url_format'];
      final filename =
          assets['library_capsule_2x'] ?? assets['library_capsule'];
      if (format is! String ||
          filename is! String ||
          !format.contains(r'${FILENAME}')) {
        continue;
      }
      final relative = format.replaceFirst(r'${FILENAME}', filename);
      final imageUri = Uri.tryParse(
        'https://$_steamStoreAssetHost/store_item_assets/$relative',
      );
      if (imageUri == null ||
          !_isTrustedImageUri(imageUri, CoverArtSource.steamStoreApi)) {
        continue;
      }
      final resolved = imageUri.toString();
      _writeApiLru(_steamStoreCoverUrlCache, appId, resolved);
      return resolved;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _steamStoreGetJson(Uri uri) async {
    final response = await _sendGetWithRetries(
      uri: uri,
      timeout: _apiJsonRequestTimeout,
      headers: const <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'CompactGames/0.1',
      },
    );
    if (response == null ||
        response.statusCode != 200 ||
        response.body.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _foldSteamStoreTitle(String value, RustBridgeService? rustBridge) {
    var folded = _lookupName(value, rustBridge).toLowerCase();
    const replacements = <String, String>{
      '\u00e0': 'a',
      '\u00e1': 'a',
      '\u00e2': 'a',
      '\u00e3': 'a',
      '\u00e4': 'a',
      '\u00e5': 'a',
      '\u00e6': 'ae',
      '\u00e7': 'c',
      '\u00e8': 'e',
      '\u00e9': 'e',
      '\u00ea': 'e',
      '\u00eb': 'e',
      '\u00ec': 'i',
      '\u00ed': 'i',
      '\u00ee': 'i',
      '\u00ef': 'i',
      '\u00f1': 'n',
      '\u00f2': 'o',
      '\u00f3': 'o',
      '\u00f4': 'o',
      '\u00f5': 'o',
      '\u00f6': 'o',
      '\u00f8': 'o',
      '\u0153': 'oe',
      '\u00f9': 'u',
      '\u00fa': 'u',
      '\u00fb': 'u',
      '\u00fc': 'u',
      '\u00fd': 'y',
      '\u00ff': 'y',
    };
    for (final entry in replacements.entries) {
      folded = folded.replaceAll(entry.key, entry.value);
    }
    return folded
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
