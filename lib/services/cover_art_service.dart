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
import 'rust_bridge_service.dart';

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
  steamGridDbApi,
  exeIcon,
  none,
}

enum CoverArtType { poster, icon }

class CoverArtResult {
  const CoverArtResult({
    required this.uri,
    required this.source,
    this.revision = 0,
  });

  final String? uri;
  final CoverArtSource source;
  final int revision;

  const CoverArtResult.none()
    : uri = null,
      source = CoverArtSource.none,
      revision = 0;
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
  static final LinkedHashMap<String, int> _coverRevisions =
      LinkedHashMap<String, int>();
  static const int _maxInFlightEntries = 100;
  static final Map<String, Future<CoverArtResult>> _inFlight =
      <String, Future<CoverArtResult>>{};
  static Directory? _cachedCacheDir;
  static final LinkedHashMap<String, String> _estimateHints =
      LinkedHashMap<String, String>();
  static final LinkedHashMap<String, bool> _coverQualityPathCache =
      LinkedHashMap<String, bool>();
  static final LinkedHashMap<String, _SteamManifestIndex> _steamManifestCache =
      LinkedHashMap<String, _SteamManifestIndex>();

  void primeEstimateHints(String gamePath, CompressionEstimate estimate) {
    final exePath = estimate.executableCandidatePath;
    if (exePath == null) return;
    final key = _cacheKey(gamePath);
    _writeEstimateHint(key, exePath);
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
    RustBridgeService? rustBridge,
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
      rustBridge: rustBridge,
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
    RustBridgeService? rustBridge,
  }) async {
    final isApp = game.platform == Platform.application;

    // 1. Disk cache
    final cached = await _readCachedCover(cacheKey);
    if (cached != null) {
      if (!isApp) {
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
      }
      _writeMemoryCache(cacheKey, cached);
      return cached;
    }

    // 2. Steam library cache (Steam games only)
    if (game.platform == Platform.steam) {
      final steamCover = await _resolveSteamLibraryCover(game.path);
      if (steamCover != null) {
        final copied = await _copyIntoCache(cacheKey, steamCover);
        final revision = _bumpCoverRevision(cacheKey);
        final result = CoverArtResult(
          uri: File(copied).uri.toString(),
          source: CoverArtSource.steamLibraryCache,
          revision: revision,
        );
        _writeMemoryCache(cacheKey, result);
        return result;
      }
    }

    // 3. SteamGridDB API (non-apps)
    if (!isApp) {
      final result = await _resolveApiCover(
        game,
        cacheKey: cacheKey,
        apiKey: steamGridDbApiKey,
      );
      if (result != null) {
        _writeMemoryCache(cacheKey, result);
        return result;
      }
    }

    // 4. EXE icon fallback
    final iconResult = await _resolveExeIconCover(
      game,
      cacheKey: cacheKey,
      rustBridge: rustBridge,
    );
    if (iconResult != null) {
      _writeMemoryCache(cacheKey, iconResult);
      return iconResult;
    }

    // 5. Placeholder
    const none = CoverArtResult.none();
    _writeMemoryCache(cacheKey, none);
    return none;
  }

  Future<CoverArtResult?> _resolveExeIconCover(
    GameInfo game, {
    required String cacheKey,
    RustBridgeService? rustBridge,
  }) async {
    if (rustBridge == null) return null;
    final exePath = _readEstimateHint(cacheKey);
    if (exePath == null) return null;
    try {
      final pngBytes = rustBridge.extractExeIcon(exePath: exePath);
      if (pngBytes == null || pngBytes.isEmpty) return null;
      final cacheDir = await _ensureCacheDir();
      final file = File(p.join(cacheDir.path, '$cacheKey.img'));
      await file.writeAsBytes(pngBytes);
      _scheduleCacheEviction(cacheDir);
      final revision = _bumpCoverRevision(cacheKey);
      return CoverArtResult(
        uri: file.uri.toString(),
        source: CoverArtSource.exeIcon,
        revision: revision,
      );
    } catch (_) {
      return null;
    }
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
    final revision = _coverRevisionForRead(
      cacheKey,
      fallbackModified: stat.modified,
    );
    return CoverArtResult(
      uri: file.uri.toString(),
      source: CoverArtSource.cache,
      revision: revision,
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
    final revision = _bumpCoverRevision(cacheKey);
    return CoverArtResult(
      uri: File(apiPath).uri.toString(),
      source: CoverArtSource.steamGridDbApi,
      revision: revision,
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
      p.join(base.path, 'Compact Games', AppConstants.coverCacheDir),
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

  int _coverRevisionForRead(
    String cacheKey, {
    required DateTime fallbackModified,
  }) {
    final existing = _coverRevisions.remove(cacheKey);
    if (existing != null) {
      _coverRevisions[cacheKey] = existing;
      return existing;
    }

    final seeded = fallbackModified.microsecondsSinceEpoch;
    _coverRevisions[cacheKey] = seeded;
    _trimLru(_coverRevisions, _maxMemoryCacheEntries);
    return seeded;
  }

  int _bumpCoverRevision(String cacheKey) {
    final current = _coverRevisions.remove(cacheKey) ?? 0;
    final next = current + 1;
    _coverRevisions[cacheKey] = next;
    _trimLru(_coverRevisions, _maxMemoryCacheEntries);
    return next;
  }

  String? _readEstimateHint(String cacheKey) {
    final cached = _estimateHints.remove(cacheKey);
    if (cached != null) {
      _estimateHints[cacheKey] = cached;
    }
    return cached;
  }

  void _writeEstimateHint(String cacheKey, String exePath) {
    _estimateHints.remove(cacheKey);
    _estimateHints[cacheKey] = exePath;
    _trimLru(_estimateHints, _maxEstimateHintEntries);
  }

  static void _trimLru<K, V>(LinkedHashMap<K, V> cache, int maxEntries) {
    while (cache.length > maxEntries) {
      cache.remove(cache.keys.first);
    }
  }
}
