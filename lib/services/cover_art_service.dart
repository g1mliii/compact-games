import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../models/compression_estimate.dart';
import '../models/game_info.dart';

part 'cover_art_service_scan.dart';
part 'cover_art_service_steam.dart';
part 'cover_art_service_api.dart';
part 'cover_art_service_api_lifecycle.dart';
part 'cover_art_service_api_security.dart';
part 'cover_art_service_cache_maintenance.dart';
part 'cover_art_service_quality.dart';
part 'cover_art_service_runtime_memory.dart';

enum CoverArtSource {
  cache,
  steamLibraryCache,
  launcherLocal,
  gameFolderImage,
  steamGridDbApi,
  none,
}

class CoverArtResult {
  const CoverArtResult({required this.uri, required this.source});

  final String? uri;
  final CoverArtSource source;

  const CoverArtResult.none() : uri = null, source = CoverArtSource.none;
}

class CoverArtService {
  const CoverArtService();

  static const int _maxCacheFiles = 600;
  static const int _maxMemoryCacheEntries = 350;
  static const int _maxEstimateHintEntries = 700;
  static const int _maxSteamManifestCacheEntries = 8;
  static const int _maxCoverQualityCacheEntries = 1200;
  static const Duration _steamManifestCacheTtl = Duration(minutes: 15);
  static final LinkedHashMap<String, CoverArtResult> _memoryCache =
      LinkedHashMap<String, CoverArtResult>();
  static const int _maxInFlightEntries = 100;
  static final Map<String, Future<CoverArtResult>> _inFlight =
      <String, Future<CoverArtResult>>{};
  static Directory? _cachedCacheDir;
  static final LinkedHashMap<
    String,
    ({String? artworkPath, String? executablePath})
  >
  _estimateHints =
      LinkedHashMap<String, ({String? artworkPath, String? executablePath})>();
  static final LinkedHashMap<String, bool> _coverQualityPathCache =
      LinkedHashMap<String, bool>();
  static final LinkedHashMap<String, _SteamManifestIndex> _steamManifestCache =
      LinkedHashMap<String, _SteamManifestIndex>();

  void primeEstimateHints(String gamePath, CompressionEstimate estimate) {
    final key = _cacheKey(gamePath);
    final next = (
      artworkPath: estimate.artworkCandidatePath,
      executablePath: estimate.executableCandidatePath,
    );
    _writeEstimateHint(key, next);
  }

  void invalidateCoverForGame(String gamePath) {
    final cacheKey = _cacheKey(gamePath);
    _memoryCache.remove(cacheKey);
    _inFlight.remove(cacheKey);
  }

  void invalidateCoverForGames(Iterable<String> gamePaths) {
    for (final path in gamePaths) {
      invalidateCoverForGame(path);
    }
  }

  List<String> placeholderRefreshCandidates(Iterable<String> gamePaths) {
    final candidates = <String>[];
    for (final path in gamePaths) {
      final cacheKey = _cacheKey(path);
      final cached = _memoryCache[cacheKey];
      if (cached?.source == CoverArtSource.none) {
        candidates.add(path);
      }
    }
    return candidates;
  }

  void clearLookupCaches() {
    _steamManifestCache.clear();
    _coverQualityPathCache.clear();
    _clearCoverArtApiLookupCaches();
  }

  static void shutdownSharedResources() {
    shutdownCoverArtSharedResources();
  }

  Future<CoverArtResult> resolveCover(
    GameInfo game, {
    String? steamGridDbApiKey,
  }) {
    final cacheKey = _cacheKey(game.path);
    final memory = _readMemoryCache(cacheKey);
    if (memory != null) {
      return Future<CoverArtResult>.value(memory);
    }

    final inFlight = _inFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    // Prevent unbounded in-flight growth under burst conditions.
    if (_inFlight.length >= _maxInFlightEntries) {
      return Future<CoverArtResult>.value(const CoverArtResult.none());
    }

    final future = _resolveCoverInternal(
      game,
      cacheKey,
      steamGridDbApiKey: steamGridDbApiKey,
    );
    _inFlight[cacheKey] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[cacheKey], future)) {
        _inFlight.remove(cacheKey);
      }
    });
  }

  Future<CoverArtResult> _resolveCoverInternal(
    GameInfo game,
    String cacheKey, {
    String? steamGridDbApiKey,
  }) async {
    final cached = await _readCachedCover(cacheKey);
    if (cached != null) {
      final cachedNeedsUpgrade = await _needsApiUpgradeForCached(
        cached,
        apiKey: steamGridDbApiKey,
      );
      if (cachedNeedsUpgrade) {
        final upgraded = await _resolveApiCover(
          game,
          cacheKey: cacheKey,
          apiKey: steamGridDbApiKey,
        );
        if (upgraded != null) {
          _writeMemoryCache(cacheKey, upgraded);
          return upgraded;
        }
      }
      _writeMemoryCache(cacheKey, cached);
      return cached;
    }

    final sourcePath = await _resolveLocalSourcePath(game);
    if (sourcePath != null) {
      final localNeedsUpgrade = await _needsApiUpgradeForPath(
        sourcePath,
        apiKey: steamGridDbApiKey,
      );
      if (localNeedsUpgrade) {
        final upgraded = await _resolveApiCover(
          game,
          cacheKey: cacheKey,
          apiKey: steamGridDbApiKey,
        );
        if (upgraded != null) {
          _writeMemoryCache(cacheKey, upgraded);
          return upgraded;
        }
      }

      final copied = await _copyIntoCache(cacheKey, sourcePath);
      final result = CoverArtResult(
        uri: File(copied).uri.toString(),
        source: _sourceForPath(game, sourcePath),
      );
      _writeMemoryCache(cacheKey, result);
      return result;
    }

    final result = await _resolveApiCover(
      game,
      cacheKey: cacheKey,
      apiKey: steamGridDbApiKey,
    );
    if (result != null) {
      _writeMemoryCache(cacheKey, result);
      return result;
    }

    const none = CoverArtResult.none();
    _writeMemoryCache(cacheKey, none);
    return none;
  }

  CoverArtSource _sourceForPath(GameInfo game, String sourcePath) {
    final lower = sourcePath.toLowerCase();
    if (lower.contains(r'\appcache\librarycache\')) {
      return CoverArtSource.steamLibraryCache;
    }
    if (lower.contains(r'\.egstore\') || lower.contains('launcher')) {
      return CoverArtSource.launcherLocal;
    }
    if (p.isWithin(game.path, sourcePath) ||
        p.dirname(sourcePath).startsWith(game.path)) {
      return CoverArtSource.gameFolderImage;
    }
    return CoverArtSource.launcherLocal;
  }

  Future<CoverArtResult?> _readCachedCover(String cacheKey) async {
    final cacheDir = await _ensureCacheDir();
    final file = File(p.join(cacheDir.path, '$cacheKey.img'));
    if (!await file.exists()) {
      return null;
    }

    final stat = await file.stat();
    final now = DateTime.now();
    final age = now.difference(stat.modified);
    if (age.inDays > AppConstants.coverCacheDays) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }

    try {
      await file.setLastModified(now);
    } catch (_) {}
    return CoverArtResult(
      uri: file.uri.toString(),
      source: CoverArtSource.cache,
    );
  }

  Future<CoverArtResult?> _resolveApiCover(
    GameInfo game, {
    required String cacheKey,
    required String? apiKey,
  }) async {
    final apiPath = await _resolveSteamGridDbCover(
      game,
      cacheKey: cacheKey,
      apiKey: apiKey,
    );
    if (apiPath == null) {
      return null;
    }
    return CoverArtResult(
      uri: File(apiPath).uri.toString(),
      source: CoverArtSource.steamGridDbApi,
    );
  }

  Future<String> _copyIntoCache(String cacheKey, String sourcePath) async {
    final cacheDir = await _ensureCacheDir();
    final sourceFile = File(sourcePath);
    final target = File(p.join(cacheDir.path, '$cacheKey.img'));
    await sourceFile.copy(target.path);
    _scheduleCacheEviction(cacheDir);
    return target.path;
  }

  Future<Directory> _ensureCacheDir() async {
    final cached = _cachedCacheDir;
    if (cached != null) {
      return cached;
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory(
      p.join(base.path, 'PressPlay', AppConstants.coverCacheDir),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedCacheDir = dir;
    return dir;
  }

  Future<void> _evictCacheIfNeeded(Directory cacheDir) async {
    final entries = await cacheDir
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    if (entries.length <= _maxCacheFiles + 20) {
      return;
    }

    final withStats = <({File file, DateTime modified})>[];
    for (final file in entries) {
      final stat = await file.stat();
      withStats.add((file: file, modified: stat.modified));
    }
    withStats.sort((a, b) => a.modified.compareTo(b.modified));
    final removeCount = withStats.length - _maxCacheFiles;
    for (var i = 0; i < removeCount; i++) {
      try {
        await withStats[i].file.delete();
      } catch (_) {}
    }
  }

  Future<String?> _resolveLocalSourcePath(GameInfo game) async {
    final hinted = await _resolveEstimateHintPath(game);
    if (hinted != null) {
      return hinted;
    }

    if (game.platform == Platform.steam) {
      final steamCover = await _resolveSteamLibraryCover(game.path);
      if (steamCover != null) {
        return steamCover;
      }
    }

    final launcherLocal = await _resolveLauncherSpecificCover(game);
    if (launcherLocal != null) {
      return launcherLocal;
    }

    return _findFolderImageCandidate(game.path);
  }

  Future<String?> _resolveEstimateHintPath(GameInfo game) async {
    final hint = _readEstimateHint(_cacheKey(game.path));
    final artworkPath = hint?.artworkPath;
    if (artworkPath != null && await File(artworkPath).exists()) {
      return artworkPath;
    }

    final executablePath = hint?.executablePath;
    if (executablePath == null) {
      return null;
    }
    final exeFile = File(executablePath);
    if (!await exeFile.exists()) {
      return null;
    }

    final exeDir = p.dirname(executablePath);
    return _findImageCandidate(rootPath: exeDir, maxDepth: 1, maxFiles: 120);
  }

  String _cacheKey(String path) {
    return base64UrlEncode(utf8.encode(path.toLowerCase())).replaceAll('=', '');
  }

  CoverArtResult? _readMemoryCache(String cacheKey) {
    final cached = _memoryCache.remove(cacheKey);
    if (cached != null) {
      _memoryCache[cacheKey] = cached;
    }
    return cached;
  }

  void _writeMemoryCache(String cacheKey, CoverArtResult result) {
    _memoryCache.remove(cacheKey);
    _memoryCache[cacheKey] = result;
    _trimLru(_memoryCache, _maxMemoryCacheEntries);
  }

  ({String? artworkPath, String? executablePath})? _readEstimateHint(
    String cacheKey,
  ) {
    final cached = _estimateHints.remove(cacheKey);
    if (cached != null) {
      _estimateHints[cacheKey] = cached;
    }
    return cached;
  }

  void _writeEstimateHint(
    String cacheKey,
    ({String? artworkPath, String? executablePath}) hint,
  ) {
    _estimateHints.remove(cacheKey);
    _estimateHints[cacheKey] = hint;
    _trimLru(_estimateHints, _maxEstimateHintEntries);
  }

  static void _trimLru<K, V>(LinkedHashMap<K, V> cache, int maxEntries) {
    while (cache.length > maxEntries) {
      cache.remove(cache.keys.first);
    }
  }
}
