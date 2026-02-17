part of 'cover_art_service.dart';

const int _maxApiConcurrentRequests = 3;
const int _maxPendingApiRequests = 64;
const int _maxApiLookupCacheEntries = 400;
const int _maxApiAttempts = 3;
const int _maxDownloadedImageBytes = 8 * 1024 * 1024;
const Duration _apiPermitWaitTimeout = Duration(seconds: 8);
const Duration _apiInitialRetryDelay = Duration(milliseconds: 220);
const Duration _apiJsonRequestTimeout = Duration(seconds: 4);
const Duration _apiImageRequestTimeout = Duration(seconds: 6);

int _activeApiRequests = 0;
final Queue<Completer<void>> _apiPermitQueue = Queue<Completer<void>>();
final LinkedHashMap<String, int> _apiGameIdCache = LinkedHashMap<String, int>();
final LinkedHashMap<int, String> _apiGridUrlCache =
    LinkedHashMap<int, String>();
final LinkedHashMap<String, String> _apiSteamAppGridUrlCache =
    LinkedHashMap<String, String>();

void _clearCoverArtApiLookupCaches() {
  _apiGameIdCache.clear();
  _apiGridUrlCache.clear();
  _apiSteamAppGridUrlCache.clear();
}

extension _CoverArtServiceApi on CoverArtService {
  Future<String?> _resolveSteamGridDbCover(
    GameInfo game, {
    required String cacheKey,
    required String? apiKey,
  }) async {
    final normalizedKey = apiKey?.trim();
    if (normalizedKey == null || normalizedKey.isEmpty) {
      return null;
    }

    try {
      String? imageUrl;
      if (game.platform == Platform.steam) {
        final steamAppId = await _resolveSteamAppIdFromGamePath(game.path);
        if (steamAppId != null) {
          imageUrl = await _findSteamGridDbGridUrlBySteamAppId(
            steamAppId: steamAppId,
            apiKey: normalizedKey,
          );
        }
      }
      imageUrl ??= await _resolveSteamGridDbGridUrlByName(
        gameName: game.name,
        apiKey: normalizedKey,
      );
      if (imageUrl == null) {
        return null;
      }

      return _downloadRemoteImageIntoCache(cacheKey, imageUrl);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveSteamGridDbGridUrlByName({
    required String gameName,
    required String apiKey,
  }) async {
    final gameId = await _searchSteamGridDbGameId(
      gameName: gameName,
      apiKey: apiKey,
    );
    if (gameId == null) {
      return null;
    }
    return _findSteamGridDbGridUrl(gameId: gameId, apiKey: apiKey);
  }

  Future<String?> _findSteamGridDbGridUrlBySteamAppId({
    required String steamAppId,
    required String apiKey,
  }) async {
    final cacheKey = steamAppId.trim();
    if (cacheKey.isEmpty) {
      return null;
    }
    final cached = _readApiLru(_apiSteamAppGridUrlCache, cacheKey);
    if (cached != null) {
      return cached;
    }

    final endpoint =
        '/api/v2/grids/steam/$cacheKey?types=static&dimensions=600x900';
    final json = await _steamGridDbGetJson(endpoint: endpoint, apiKey: apiKey);
    final resolved = _selectSteamGridUrl(json);
    if (resolved != null) {
      _writeApiLru(_apiSteamAppGridUrlCache, cacheKey, resolved);
    }
    return resolved;
  }

  Future<int?> _searchSteamGridDbGameId({
    required String gameName,
    required String apiKey,
  }) async {
    final cacheKey = gameName.trim().toLowerCase();
    final cached = _readApiLru(_apiGameIdCache, cacheKey);
    if (cached != null) {
      return cached;
    }

    final query = Uri.encodeComponent(gameName);
    final endpoint = '/api/v2/search/autocomplete/$query';
    final json = await _steamGridDbGetJson(endpoint: endpoint, apiKey: apiKey);
    if (json == null) {
      return null;
    }

    final data = json['data'];
    if (data is! List || data.isEmpty) {
      return null;
    }

    final normalized = gameName.toLowerCase();
    int? fallback;
    for (final item in data) {
      if (item is! Map) {
        continue;
      }
      final id = _readInt(item['id']);
      if (id == null) {
        continue;
      }
      fallback ??= id;
      final name = (item['name'] as String?)?.toLowerCase();
      if (name != null && name == normalized) {
        _writeApiLru(_apiGameIdCache, cacheKey, id);
        return id;
      }
    }
    if (fallback != null) {
      _writeApiLru(_apiGameIdCache, cacheKey, fallback);
    }
    return fallback;
  }

  Future<String?> _findSteamGridDbGridUrl({
    required int gameId,
    required String apiKey,
  }) async {
    final cached = _readApiLru(_apiGridUrlCache, gameId);
    if (cached != null) {
      return cached;
    }

    final endpoint =
        '/api/v2/grids/game/$gameId?types=static&dimensions=600x900';
    final json = await _steamGridDbGetJson(endpoint: endpoint, apiKey: apiKey);
    final resolved = _selectSteamGridUrl(json);
    if (resolved != null) {
      _writeApiLru(_apiGridUrlCache, gameId, resolved);
    }
    return resolved;
  }

  String? _selectSteamGridUrl(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final data = json['data'];
    if (data is! List || data.isEmpty) {
      return null;
    }

    String? fallbackUrl;
    String? bestPortraitUrl;
    var bestPortraitHeight = 0;
    for (final item in data) {
      if (item is! Map) {
        continue;
      }

      final url = item['url'] as String?;
      if (url == null || url.isEmpty) {
        continue;
      }
      fallbackUrl ??= url;

      final width = _readInt(item['width']) ?? 0;
      final height = _readInt(item['height']) ?? 0;
      if (height > width && height > bestPortraitHeight) {
        bestPortraitHeight = height;
        bestPortraitUrl = url;
      }
    }
    return bestPortraitUrl ?? fallbackUrl;
  }

  Future<Map<String, dynamic>?> _steamGridDbGetJson({
    required String endpoint,
    required String apiKey,
  }) async {
    final uri = Uri.parse('https://www.steamgriddb.com$endpoint');
    for (final authorization in _authorizationHeaderCandidates(apiKey)) {
      final response = await _sendGetWithRetries(
        uri: uri,
        timeout: _apiJsonRequestTimeout,
        headers: <String, String>{
          'Authorization': authorization,
          'Accept': 'application/json',
          'User-Agent': 'PressPlay/0.1',
        },
      );
      if (response == null) {
        continue;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        continue;
      }
      if (response.statusCode != 200 || response.body.isEmpty) {
        return null;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return null;
      }
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return decoded;
    }
    return null;
  }

  Future<String?> _downloadRemoteImageIntoCache(
    String cacheKey,
    String imageUrl,
  ) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) {
      return null;
    }

    final response = await _sendGetWithRetries(
      uri: uri,
      timeout: _apiImageRequestTimeout,
      headers: const <String, String>{'User-Agent': 'PressPlay/0.1'},
    );
    if (response == null || response.statusCode != 200) {
      return null;
    }
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('image/')) {
      return null;
    }
    final declaredLength = int.tryParse(
      response.headers['content-length'] ?? '',
    );
    if (declaredLength != null && declaredLength > _maxDownloadedImageBytes) {
      return null;
    }
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > _maxDownloadedImageBytes) {
      return null;
    }

    final cacheDir = await _ensureCacheDir();
    final target = File(p.join(cacheDir.path, '$cacheKey.img'));
    await target.writeAsBytes(response.bodyBytes, flush: true);
    await _evictCacheIfNeeded(cacheDir);
    return target.path;
  }

  Future<http.Response?> _sendGetWithRetries({
    required Uri uri,
    required Duration timeout,
    required Map<String, String> headers,
  }) {
    return _withApiRetries<http.Response>(() async {
      final response = await _withApiPermit(
        () => http.get(uri, headers: headers).timeout(timeout),
      );
      if (response.statusCode == 429 || response.statusCode >= 500) {
        throw const _RetryableApiException();
      }
      return response;
    });
  }

  Future<T?> _withApiRetries<T>(Future<T> Function() request) async {
    var delay = _apiInitialRetryDelay;
    for (var attempt = 0; attempt < _maxApiAttempts; attempt++) {
      try {
        return await request();
      } on _RetryableApiException {
        // transient API condition
      } on TimeoutException {
        // transient timeout
      } on SocketException {
        // transient network failure
      } on HttpException {
        // transient HTTP state
      }

      if (attempt == _maxApiAttempts - 1) {
        break;
      }
      await Future<void>.delayed(delay);
      delay = Duration(milliseconds: delay.inMilliseconds * 2);
    }
    return null;
  }

  Future<T> _withApiPermit<T>(Future<T> Function() request) async {
    if (_activeApiRequests >= _maxApiConcurrentRequests) {
      if (_apiPermitQueue.length >= _maxPendingApiRequests) {
        throw const _RetryableApiException();
      }
      final waiter = Completer<void>();
      _apiPermitQueue.addLast(waiter);
      try {
        await waiter.future.timeout(_apiPermitWaitTimeout);
      } on TimeoutException {
        _apiPermitQueue.remove(waiter);
        throw const _RetryableApiException();
      }
    }

    _activeApiRequests += 1;
    try {
      return await request();
    } finally {
      _activeApiRequests -= 1;
      _releaseNextApiPermit();
    }
  }

  void _releaseNextApiPermit() {
    while (_apiPermitQueue.isNotEmpty) {
      final next = _apiPermitQueue.removeFirst();
      if (next.isCompleted) {
        continue;
      }
      next.complete();
      return;
    }
  }

  T? _readApiLru<K, T>(LinkedHashMap<K, T> cache, K key) {
    final cached = cache.remove(key);
    if (cached != null) {
      cache[key] = cached;
    }
    return cached;
  }

  void _writeApiLru<K, T>(LinkedHashMap<K, T> cache, K key, T value) {
    cache.remove(key);
    cache[key] = value;
    CoverArtService._trimLru(cache, _maxApiLookupCacheEntries);
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  List<String> _authorizationHeaderCandidates(String apiKey) {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final lower = normalized.toLowerCase();
    if (lower.startsWith('bearer ')) {
      final raw = normalized.substring('bearer '.length).trim();
      if (raw.isEmpty) {
        return <String>[normalized];
      }
      return <String>[normalized, raw];
    }
    return <String>[normalized, 'Bearer $normalized'];
  }
}

class _RetryableApiException implements Exception {
  const _RetryableApiException();
}
