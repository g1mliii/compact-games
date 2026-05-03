import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/cover_art_proxy_config.dart';
import '../core/constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/compression_estimate.dart';
import '../models/game_info.dart';
import 'rust_bridge_service.dart';

part 'cover_art_service_steam.dart';
part 'cover_art_service_api.dart';
part 'cover_art_service_proxy.dart';
part 'cover_art_service_api_lifecycle.dart';
part 'cover_art_service_api_security.dart';
part 'cover_art_service_cache_maintenance.dart';
part 'cover_art_service_quality.dart';
part 'cover_art_service_runtime_memory.dart';

enum CoverArtSource { cache, steamLibraryCache, steamGridDbApi, exeIcon, none }

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
    _removeRuntimeEntriesForDiskCacheKey(cacheKey);
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
      if (_hasMemoryPlaceholderForDiskCacheKey(cacheKey)) {
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
    CoverArtProviderMode coverArtProviderMode =
        CoverArtProviderMode.bundledProxy,
    CoverArtProxyConfig coverArtProxyConfig = const CoverArtProxyConfig(),
    RustBridgeService? rustBridge,
  }) {
    final cacheKey = _cacheKey(game.path);
    final runtimeCacheKey = _runtimeCacheKey(
      cacheKey,
      steamGridDbApiKey: steamGridDbApiKey,
      coverArtProviderMode: coverArtProviderMode,
      coverArtProxyConfig: coverArtProxyConfig,
    );
    final memory = _readMemoryCache(runtimeCacheKey);
    if (memory != null) {
      return Future<CoverArtResult>.value(memory);
    }

    final inFlight = _inFlight[runtimeCacheKey];
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
      runtimeCacheKey: runtimeCacheKey,
      steamGridDbApiKey: steamGridDbApiKey,
      coverArtProviderMode: coverArtProviderMode,
      coverArtProxyConfig: coverArtProxyConfig,
      rustBridge: rustBridge,
    );
    _inFlight[runtimeCacheKey] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[runtimeCacheKey], future)) {
        _inFlight.remove(runtimeCacheKey);
      }
    });
  }

  Future<CoverArtResult> _resolveCoverInternal(
    GameInfo game,
    String cacheKey, {
    required String runtimeCacheKey,
    String? steamGridDbApiKey,
    required CoverArtProviderMode coverArtProviderMode,
    required CoverArtProxyConfig coverArtProxyConfig,
    RustBridgeService? rustBridge,
  }) async {
    // 1. Disk cache
    final cached = await _readCachedCover(cacheKey);
    if (cached != null) {
      final cachedNeedsUpgrade = await _needsApiUpgradeForCached(
        cached,
        apiKey: steamGridDbApiKey,
        providerMode: coverArtProviderMode,
        proxyConfig: coverArtProxyConfig,
      );
      if (cachedNeedsUpgrade) {
        final upgraded = await _resolveApiCover(
          game,
          cacheKey: cacheKey,
          apiKey: steamGridDbApiKey,
          providerMode: coverArtProviderMode,
          proxyConfig: coverArtProxyConfig,
        );
        if (upgraded != null) {
          _writeMemoryCache(runtimeCacheKey, upgraded);
          return upgraded;
        }
      }
      _writeMemoryCache(runtimeCacheKey, cached);
      return cached;
    }

    // 2. Steam library cache (Steam games only)
    if (game.platform == Platform.steam) {
      final steamCover = await _resolveSteamLibraryCover(game.path);
      if (steamCover != null) {
        try {
          final copied = await _copyIntoCache(cacheKey, steamCover);
          final revision = _bumpCoverRevision(cacheKey);
          final result = CoverArtResult(
            uri: File(copied).uri.toString(),
            source: CoverArtSource.steamLibraryCache,
            revision: revision,
          );
          _writeMemoryCache(runtimeCacheKey, result);
          return result;
        } on FileSystemException {
          // Source was empty / unreadable — fall through to API and icon.
        }
      }
    }

    // 3. SteamGridDB API
    final result = await _resolveApiCover(
      game,
      cacheKey: cacheKey,
      apiKey: steamGridDbApiKey,
      providerMode: coverArtProviderMode,
      proxyConfig: coverArtProxyConfig,
    );
    if (result != null) {
      _writeMemoryCache(runtimeCacheKey, result);
      return result;
    }

    // 4. EXE icon fallback
    final iconResult = await _resolveExeIconCover(
      game,
      cacheKey: cacheKey,
      rustBridge: rustBridge,
    );
    if (iconResult != null) {
      _writeMemoryCache(runtimeCacheKey, iconResult);
      return iconResult;
    }

    // 5. Placeholder
    const none = CoverArtResult.none();
    _writeMemoryCache(runtimeCacheKey, none);
    return none;
  }

  Future<CoverArtResult?> _resolveExeIconCover(
    GameInfo game, {
    required String cacheKey,
    RustBridgeService? rustBridge,
  }) async {
    if (rustBridge == null) return null;
    // Prefer the exe path the estimator already discovered. Falls back to
    // scanning the game folder so compressed app games (which skip the
    // estimate fetch) still get an icon.
    try {
      final hintedPath = _readEstimateHint(cacheKey);
      final exePath =
          hintedPath ?? await rustBridge.discoverPrimaryExe(game.path);
      if (exePath == null) {
        return null;
      }
      final pngBytes = rustBridge.extractExeIcon(exePath: exePath);
      if (pngBytes == null || pngBytes.isEmpty) {
        return null;
      }
      final cacheDir = await _ensureCacheDir();
      final file = File(p.join(cacheDir.path, '$cacheKey.img'));
      await file.writeAsBytes(pngBytes);
      await _writeCachedCoverSource(cacheDir, cacheKey, CoverArtSource.exeIcon);
      _scheduleCacheEviction(cacheDir);
      final revision = _bumpCoverRevision(cacheKey);
      // Prime the in-memory hint so subsequent re-resolutions (e.g. after a
      // refresh) skip the folder walk.
      _writeEstimateHint(cacheKey, exePath);
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

    final FileStat stat;
    try {
      stat = await file.stat();
    } catch (_) {
      return null;
    }
    if (stat.type == FileSystemEntityType.notFound) {
      return null;
    }
    // Drop empty cache files. A 0-byte .img can be left behind after a
    // partial write or a failed copy and would otherwise resolve to a
    // non-null URI that decodes to nothing — the user sees a blank cover
    // with no platform-icon fallback because coverImageProvider != null.
    if (stat.size <= 0) {
      try {
        await file.delete();
        await _clearCachedCoverSource(cacheDir, cacheKey);
      } catch (_) {}
      return null;
    }
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
    final source = await _readCachedCoverSource(cacheDir, cacheKey);
    return CoverArtResult(
      uri: file.uri.toString(),
      source: source,
      revision: revision,
    );
  }

  Future<CoverArtResult?> _resolveApiCover(
    GameInfo game, {
    required String cacheKey,
    required String? apiKey,
    required CoverArtProviderMode providerMode,
    required CoverArtProxyConfig proxyConfig,
  }) async {
    final apiPath = await _resolveSteamGridDbCover(
      game,
      cacheKey: cacheKey,
      apiKey: apiKey,
      providerMode: providerMode,
      proxyConfig: proxyConfig,
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
    // Refuse to copy in zero-byte sources so we never poison the cache with
    // a non-null URI that decodes to nothing.
    final sourceStat = await sourceFile.stat();
    if (sourceStat.size <= 0) {
      throw const FileSystemException('Refusing to cache empty cover source');
    }
    final target = File(p.join(cacheDir.path, '$cacheKey.img'));
    await sourceFile.copy(target.path);
    await _clearCachedCoverSource(cacheDir, cacheKey);
    _scheduleCacheEviction(cacheDir);
    return target.path;
  }

  Future<CoverArtSource> _readCachedCoverSource(
    Directory cacheDir,
    String cacheKey,
  ) async {
    final sourceFile = _cachedCoverSourceFile(cacheDir, cacheKey);
    try {
      final value = (await sourceFile.readAsString()).trim();
      if (value == CoverArtSource.exeIcon.name) {
        return CoverArtSource.exeIcon;
      }
    } catch (_) {}
    return CoverArtSource.cache;
  }

  Future<void> _writeCachedCoverSource(
    Directory cacheDir,
    String cacheKey,
    CoverArtSource source,
  ) async {
    try {
      await _cachedCoverSourceFile(
        cacheDir,
        cacheKey,
      ).writeAsString(source.name, flush: true);
    } catch (_) {}
  }

  Future<void> _clearCachedCoverSource(
    Directory cacheDir,
    String cacheKey,
  ) async {
    try {
      await _cachedCoverSourceFile(cacheDir, cacheKey).delete();
    } catch (_) {}
  }

  File _cachedCoverSourceFile(Directory cacheDir, String cacheKey) {
    return File(p.join(cacheDir.path, '$cacheKey.source'));
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
    final files = await cacheDir
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();

    final imageFiles = <File>[];
    final sourceFilesByKey = <String, File>{};
    for (final file in files) {
      final extension = p.extension(file.path);
      if (extension == '.img') {
        imageFiles.add(file);
      } else if (extension == '.source') {
        sourceFilesByKey[p.basenameWithoutExtension(file.path)] = file;
      }
    }

    final imageKeys = imageFiles
        .map((file) => p.basenameWithoutExtension(file.path))
        .toSet();
    for (final entry in sourceFilesByKey.entries) {
      if (!imageKeys.contains(entry.key)) {
        await _deleteCacheFile(entry.value);
      }
    }

    if (imageFiles.length <= _maxCacheFiles + 20) {
      return;
    }

    final withStats = <({File file, DateTime modified})>[];
    for (final file in imageFiles) {
      final stat = await file.stat();
      withStats.add((file: file, modified: stat.modified));
    }
    withStats.sort((a, b) => a.modified.compareTo(b.modified));
    final removeCount = imageFiles.length - _maxCacheFiles;
    for (var i = 0; i < removeCount; i++) {
      final imageFile = withStats[i].file;
      await _deleteCacheFile(imageFile);
      final cacheKey = p.basenameWithoutExtension(imageFile.path);
      final sourceFile = sourceFilesByKey[cacheKey];
      if (sourceFile != null) {
        await _deleteCacheFile(sourceFile);
      }
    }
  }

  Future<void> _deleteCacheFile(File file) async {
    try {
      await file.delete();
    } catch (_) {}
  }

  String _cacheKey(String path) {
    return base64UrlEncode(utf8.encode(path.toLowerCase())).replaceAll('=', '');
  }

  String _runtimeCacheKey(
    String diskCacheKey, {
    required String? steamGridDbApiKey,
    required CoverArtProviderMode coverArtProviderMode,
    required CoverArtProxyConfig coverArtProxyConfig,
  }) {
    final apiKey = steamGridDbApiKey?.trim();
    final apiKeyPart = apiKey == null || apiKey.isEmpty
        ? 'none'
        : 'set:${apiKey.hashCode}';
    final proxyUrl = coverArtProxyConfig.url.trim();
    final proxyToken = coverArtProxyConfig.token.trim();
    final proxyPart = coverArtProxyConfig.isConfigured
        ? '${proxyUrl.hashCode}:${proxyToken.hashCode}'
        : 'off';
    return '$diskCacheKey|mode=${coverArtProviderMode.name}|key=$apiKeyPart|proxy=$proxyPart';
  }

  bool _matchesRuntimeCacheKey(String runtimeCacheKey, String diskCacheKey) {
    return runtimeCacheKey == diskCacheKey ||
        runtimeCacheKey.startsWith('$diskCacheKey|');
  }

  void _removeRuntimeEntriesForDiskCacheKey(String diskCacheKey) {
    _memoryCache.removeWhere(
      (key, _) => _matchesRuntimeCacheKey(key, diskCacheKey),
    );
    _inFlight.removeWhere(
      (key, _) => _matchesRuntimeCacheKey(key, diskCacheKey),
    );
  }

  bool _hasMemoryPlaceholderForDiskCacheKey(String diskCacheKey) {
    for (final entry in _memoryCache.entries) {
      if (_matchesRuntimeCacheKey(entry.key, diskCacheKey) &&
          entry.value.source == CoverArtSource.none) {
        return true;
      }
    }
    return false;
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
