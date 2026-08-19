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
import '../core/utils/bounded_lru.dart';
import '../core/utils/cover_art_utils.dart';
import '../models/app_settings.dart';
import '../models/compression_estimate.dart';
import '../models/game_info.dart';
import 'bounded_json_http.dart';
import 'packaged_app_logo.dart';
import 'game_catalog_identity_service.dart';
import 'rust_bridge_service.dart';

part 'cover_art_service_steam.dart';
part 'cover_art_service_api.dart';
part 'cover_art_service_proxy.dart';
part 'cover_art_service_api_lifecycle.dart';
part 'cover_art_service_api_security.dart';
part 'cover_art_service_cache_maintenance.dart';
part 'cover_art_service_quality.dart';
part 'cover_art_service_runtime_memory.dart';
part 'cover_art_service_store.dart';

enum CoverArtSource {
  cache,
  steamLibraryCache,
  steamGridDbApi,
  steamStoreApi,
  exeIcon,
  packagedAppLogo,
  none,
}

enum CoverArtType { poster, icon }

/// What the `.source` sidecar beside a cached cover remembers about it.
class _CachedCoverRecord {
  const _CachedCoverRecord({required this.source, required this.probedVisible});

  final CoverArtSource source;

  /// Whether these bytes have already been confirmed to paint something. Only
  /// locally-derived art is ever probed, and only once.
  final bool probedVisible;
}

const String _sidecarSeparator = '\n';
const String _visibleMarker = 'visible';

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
  static const int _maxCoverQualityCacheEntries = 1200;
  static final LinkedHashMap<String, CoverArtResult> _memoryCache =
      LinkedHashMap<String, CoverArtResult>();
  static final LinkedHashMap<String, bool> _forcedProviderRefreshCacheKeys =
      LinkedHashMap<String, bool>();
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

  void primeEstimateHints(String gamePath, CompressionEstimate estimate) {
    final exePath = estimate.executableCandidatePath;
    if (exePath == null) return;
    final key = _cacheKey(gamePath);
    _writeEstimateHint(key, exePath);
  }

  void invalidateCoverForGame(String gamePath) {
    final cacheKey = _cacheKey(gamePath);
    _removeRuntimeEntriesForDiskCacheKey(cacheKey);
    _markProviderRefresh(cacheKey);
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
    _coverQualityPathCache.clear();
    _clearCoverArtApiLookupCaches();
  }

  static void shutdownSharedResources() {
    shutdownCoverArtSharedResources();
  }

  /// The cover already resolved for [gamePath] this session, or null.
  ///
  /// Synchronous and side-effect free: it never starts a resolution, never
  /// touches disk or the network, and deliberately does not refresh the entry's
  /// LRU recency — a secondary surface peeking must not reorder the eviction
  /// queue the game grid depends on.
  ///
  /// For surfaces that want to illustrate themselves with artwork the app
  /// happens to have. Watching [resolveCover] there would make merely opening
  /// the surface fetch covers, which is a very different cost.
  CoverArtResult? peekCachedCover(
    String gamePath, {
    String? steamGridDbApiKey,
    CoverArtProviderMode coverArtProviderMode =
        CoverArtProviderMode.bundledProxy,
    CoverArtProxyConfig coverArtProxyConfig = const CoverArtProxyConfig(),
  }) {
    final cached =
        _memoryCache[_runtimeCacheKey(
          _cacheKey(gamePath),
          steamGridDbApiKey: steamGridDbApiKey,
          coverArtProviderMode: coverArtProviderMode,
          coverArtProxyConfig: coverArtProxyConfig,
        )];
    // A placeholder entry records "resolution ran and found nothing", which is
    // not something to paint.
    return cached == null || cached.uri == null ? null : cached;
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
    final refreshProviderCover =
        _isApiEnabled(steamGridDbApiKey, proxyConfig: coverArtProxyConfig) &&
        _consumeProviderRefresh(cacheKey);
    final memory = refreshProviderCover
        ? null
        : _readMemoryCache(runtimeCacheKey);
    // Every resolved result belongs to this provider configuration for the
    // current process. An explicit invalidation is the retry path.
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
      refreshProviderCover: refreshProviderCover,
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
    required bool refreshProviderCover,
  }) async {
    CoverArtResult store(CoverArtResult result) {
      _writeMemoryCache(runtimeCacheKey, result);
      return result;
    }

    var primaryExeResolved = false;
    String? primaryExePath;
    Future<String?> resolvePrimaryExe() async {
      if (primaryExeResolved) {
        return primaryExePath;
      }
      primaryExeResolved = true;
      try {
        final hintedPath = _readEstimateHint(cacheKey);
        primaryExePath =
            hintedPath ??
            (rustBridge == null
                ? null
                : await rustBridge.discoverPrimaryExe(game.path));
        if (primaryExePath != null) {
          _writeEstimateHint(cacheKey, primaryExePath!);
        }
      } catch (_) {
        primaryExePath = null;
      }
      return primaryExePath;
    }

    final apiEnabled = _isApiEnabled(
      steamGridDbApiKey,
      proxyConfig: coverArtProxyConfig,
    );
    var cached = await _readCachedCover(cacheKey);
    // A cover that already came from a catalog provider is authoritative for
    // every provider configuration, so it is reused without revalidation until
    // the game is explicitly invalidated.
    if (!refreshProviderCover &&
        (cached?.source == CoverArtSource.steamGridDbApi ||
            cached?.source == CoverArtSource.steamStoreApi)) {
      return store(cached!);
    }

    String? executableLookupName;
    var providerConfirmedNoMatch = false;
    if (apiEnabled) {
      final primaryLookup = await _resolveApiCover(
        game,
        cacheKey: cacheKey,
        apiKey: steamGridDbApiKey,
        providerMode: coverArtProviderMode,
        proxyConfig: coverArtProxyConfig,
        rustBridge: rustBridge,
      );
      if (primaryLookup.cover != null) {
        return store(primaryLookup.cover!);
      }

      executableLookupName = _executableLookupName(
        await resolvePrimaryExe(),
        currentName: game.name,
      );
      providerConfirmedNoMatch =
          primaryLookup.status == _CoverArtProviderLookupStatus.notFound;
      if (executableLookupName != null) {
        final executableLookup = await _resolveApiCover(
          game.copyWith(name: executableLookupName),
          cacheKey: cacheKey,
          apiKey: steamGridDbApiKey,
          providerMode: coverArtProviderMode,
          proxyConfig: coverArtProxyConfig,
          rustBridge: rustBridge,
        );
        if (executableLookup.cover != null) {
          return store(executableLookup.cover!);
        }
        providerConfirmedNoMatch =
            providerConfirmedNoMatch &&
            executableLookup.status == _CoverArtProviderLookupStatus.notFound;
      }
    }

    // Steam's public catalog needs neither a SteamGridDB key nor the bundled
    // proxy, so it is the fallback for every game the provider could not
    // cover: a just-released title the provider has no art for yet, a proxy
    // that is unreachable or rate limited, and a build with no provider
    // configured at all. Gating this on the provider being usable is what left
    // freshly installed games permanently showing their EXE icon.
    var steamStoreAttempted = false;
    Future<CoverArtResult?> resolveStoreCover() async {
      if (steamStoreAttempted) {
        return null;
      }
      steamStoreAttempted = true;
      executableLookupName ??= _executableLookupName(
        await resolvePrimaryExe(),
        currentName: game.name,
      );
      return _resolveSteamStoreCover(
        game,
        cacheKey: cacheKey,
        alternateLookupName: executableLookupName,
        rustBridge: rustBridge,
      );
    }

    // For a non-Steam game the public catalog outranks whatever local cache
    // entry is left over, so it runs before the fallbacks below.
    if (game.platform != Platform.steam) {
      final steamStoreCover = await resolveStoreCover();
      if (steamStoreCover != null) {
        return store(steamStoreCover);
      }
    }

    if (providerConfirmedNoMatch &&
        game.platform == Platform.custom &&
        cached?.source == CoverArtSource.cache) {
      await _deleteCachedCover(cacheKey);
      cached = null;
    }

    if (cached != null && await _isPreferredCachedCover(cached)) {
      return store(cached);
    }

    if (cached == null) {
      final steamCache = await _resolveSteamLibraryCoverResult(
        game,
        cacheKey: cacheKey,
        rustBridge: rustBridge,
      );
      if (steamCache != null) {
        return store(steamCache);
      }
    }

    if (cached != null) {
      // Avoid swapping one mediocre cached image for another unless Steam has a
      // clearly card-suitable asset.
      final steamCache = await _resolveSteamLibraryCoverResult(
        game,
        cacheKey: cacheKey,
        requirePreferred: true,
        rustBridge: rustBridge,
      );
      if (steamCache != null) {
        return store(steamCache);
      }
    }

    // A Steam install prefers its own library cache, but when that has nothing
    // card-suitable the public catalog still beats dropping to the EXE icon.
    final steamStoreCover = await resolveStoreCover();
    if (steamStoreCover != null) {
      return store(steamStoreCover);
    }

    if (cached != null) {
      return store(cached);
    }

    // A packaged app carries its own artwork, which is the only art some games
    // have anywhere: Minecraft is on Game Pass and not on Steam, so no catalog
    // above could ever answer for it. Tried before the EXE icon because a
    // manifest logo is the game's own tile, while an extracted icon is
    // whatever the launcher executable happens to embed.
    final packageLogo = await _resolvePackagedAppLogoCover(
      game,
      cacheKey: cacheKey,
    );
    if (packageLogo != null) {
      return store(packageLogo);
    }

    final iconResult = await _resolveExeIconCover(
      cacheKey: cacheKey,
      executablePath: await resolvePrimaryExe(),
      rustBridge: rustBridge,
    );
    if (iconResult != null) {
      return store(iconResult);
    }

    return store(const CoverArtResult.none());
  }

  /// The logo an MSIX/Xbox package declares in its own manifest.
  ///
  /// These are 150px tiles rather than capsules, so
  /// [coverArtTypeFromSource] draws them centred on a plate rather than
  /// stretched across the cover.
  Future<CoverArtResult?> _resolvePackagedAppLogoCover(
    GameInfo game, {
    required String cacheKey,
  }) async {
    try {
      final logo = await findPackagedAppLogo(game.path);
      if (logo == null) {
        return null;
      }
      return await _writeBytesIntoCache(
        cacheKey,
        await logo.readAsBytes(),
        source: CoverArtSource.packagedAppLogo,
      );
    } catch (_) {
      return null;
    }
  }

  Future<CoverArtResult?> _resolveSteamLibraryCoverResult(
    GameInfo game, {
    required String cacheKey,
    required RustBridgeService? rustBridge,
    bool requirePreferred = false,
  }) async {
    if (game.platform != Platform.steam) {
      return null;
    }
    final steamCover = await _resolveSteamLibraryCover(
      game.path,
      knownSteamAppId: game.steamAppId,
      rustBridge: rustBridge,
    );
    if (steamCover == null) {
      return null;
    }
    if (requirePreferred) {
      try {
        if (!await _isPreferredCardCover(steamCover)) {
          return null;
        }
      } catch (_) {
        return null;
      }
    }

    try {
      final copied = await _copyIntoCache(
        cacheKey,
        steamCover,
        source: CoverArtSource.steamLibraryCache,
      );
      final revision = _bumpCoverRevision(cacheKey);
      return CoverArtResult(
        uri: File(copied).uri.toString(),
        source: CoverArtSource.steamLibraryCache,
        revision: revision,
      );
    } on FileSystemException {
      // Source was empty / unreadable — fall through to lower-priority paths.
      return null;
    }
  }

  Future<CoverArtResult?> _resolveExeIconCover({
    required String cacheKey,
    required String? executablePath,
    required RustBridgeService? rustBridge,
  }) async {
    if (executablePath == null || rustBridge == null) return null;
    try {
      final pngBytes = rustBridge.extractExeIcon(exePath: executablePath);
      if (pngBytes == null || pngBytes.isEmpty) {
        return null;
      }
      final result = await _writeBytesIntoCache(
        cacheKey,
        pngBytes,
        source: CoverArtSource.exeIcon,
      );
      if (result == null) {
        return null;
      }
      // Prime the in-memory hint so subsequent re-resolutions (e.g. after a
      // refresh) skip the folder walk.
      _writeEstimateHint(cacheKey, executablePath);
      return result;
    } catch (_) {
      return null;
    }
  }

  String? _executableLookupName(
    String? executablePath, {
    required String currentName,
  }) {
    if (executablePath == null || executablePath.isEmpty) {
      return null;
    }
    final stem = p.basenameWithoutExtension(executablePath).trim();
    if (stem.isEmpty) {
      return null;
    }
    final spaced = stem
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (spaced.isEmpty || spaced.toLowerCase() == currentName.toLowerCase()) {
      return null;
    }
    return spaced;
  }

  /// Whether the image in [file] has any pixel the user would actually see.
  Future<bool> _hasVisiblePixels(File file) async {
    try {
      return await imageHasVisiblePixels(await file.readAsBytes());
    } catch (_) {
      // Unreadable is not "blank": leave that to the image widget, which falls
      // back to the placeholder on a decode error.
      return true;
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

    final cachedSource = await _readCachedCoverRecord(cacheDir, cacheKey);
    final source = cachedSource.source;
    // An extracted icon can be a perfectly valid PNG with nothing in it — an
    // executable that carries no icon resource yields a fully transparent
    // image. It passes the size check above, decodes without error, and paints
    // absolutely nothing, which is the one outcome the placeholder exists to
    // prevent. Only locally-derived art is checked: a store or library capsule
    // is a photograph, and decoding every one of those to count pixels would
    // cost real time on every resolve.
    if (isLocallyDerivedCoverSource(source) && !cachedSource.probedVisible) {
      if (!await _hasVisiblePixels(file)) {
        try {
          await file.delete();
          await _clearCachedCoverSource(cacheDir, cacheKey);
        } catch (_) {}
        return null;
      }
      // Record the verdict this probe just reached. Without the write-back,
      // every sidecar written before the field existed re-reads the whole
      // image and decodes it on each resolve, forever — which is the cost the
      // field was added to stop paying.
      await _writeCachedCoverSource(
        cacheDir,
        cacheKey,
        source,
        probedVisible: true,
      );
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
      source: source,
      revision: revision,
    );
  }

  /// Normalizes a game name for lookup using the Rust discovery rules.
  ///
  /// Without a bridge — unit tests — the raw name is used; that only costs
  /// query quality, never correctness.
  String _lookupName(String name, RustBridgeService? rustBridge) =>
      rustBridge?.normalizeGameName(name) ?? name.trim();

  Future<_CoverArtProviderLookup> _resolveApiCover(
    GameInfo game, {
    required String cacheKey,
    required String? apiKey,
    required CoverArtProviderMode providerMode,
    required CoverArtProxyConfig proxyConfig,
    required RustBridgeService? rustBridge,
  }) async {
    // The settings toggle chooses which SteamGridDB source is tried first; it
    // never switches the other one off. Every source that is actually
    // configured gets a turn, so a bundled-proxy miss still reaches the user's
    // own key and a failing user key still reaches the bundled proxy.
    final normalizedApiKey = apiKey?.trim();
    final hasUserKey = normalizedApiKey != null && normalizedApiKey.isNotEmpty;

    Future<_ProviderAttempt> attemptBundledProxy() async {
      if (!proxyConfig.isConfigured) {
        return const _ProviderAttempt.skipped();
      }
      final proxyLookup = await _resolveSteamGridDbCoverViaProxy(
        game,
        cacheKey: cacheKey,
        proxyConfig: proxyConfig,
        rustBridge: rustBridge,
      );
      if (proxyLookup.status == _CoverProxyLookupStatus.found) {
        return _ProviderAttempt.found(
          CoverArtResult(
            uri: File(proxyLookup.path!).uri.toString(),
            source: CoverArtSource.steamGridDbApi,
            revision: _bumpCoverRevision(cacheKey),
          ),
        );
      }
      // The proxy distinguishes a catalog miss (404) from being unreachable,
      // and it caches its misses — so a 404 can outlive SteamGridDB gaining
      // art. A user key queries SteamGridDB directly, past that cache.
      return _ProviderAttempt.missed(
        confirmedNoMatch:
            proxyLookup.status == _CoverProxyLookupStatus.notFound,
      );
    }

    Future<_ProviderAttempt> attemptUserKey() async {
      if (!hasUserKey) {
        return const _ProviderAttempt.skipped();
      }
      final apiPath = await _resolveSteamGridDbCover(
        game,
        cacheKey: cacheKey,
        apiKey: normalizedApiKey,
        rustBridge: rustBridge,
      );
      if (apiPath == null) {
        // The direct API path collapses a catalog miss and a transport failure
        // into the same null, so it can never confirm a no-match on its own.
        return const _ProviderAttempt.missed(confirmedNoMatch: false);
      }
      return _ProviderAttempt.found(
        CoverArtResult(
          uri: File(apiPath).uri.toString(),
          source: CoverArtSource.steamGridDbApi,
          revision: _bumpCoverRevision(cacheKey),
        ),
      );
    }

    final ordered = providerMode == CoverArtProviderMode.userKey
        ? <Future<_ProviderAttempt> Function()>[
            attemptUserKey,
            attemptBundledProxy,
          ]
        : <Future<_ProviderAttempt> Function()>[
            attemptBundledProxy,
            attemptUserKey,
          ];

    var ranAnySource = false;
    var everySourceConfirmedNoMatch = true;
    for (final attempt in ordered) {
      final result = await attempt();
      final cover = result.cover;
      if (cover != null) {
        return _CoverArtProviderLookup.found(cover);
      }
      if (!result.ran) {
        continue;
      }
      ranAnySource = true;
      everySourceConfirmedNoMatch =
          everySourceConfirmedNoMatch && result.confirmedNoMatch;
    }

    // "Not found" must mean every source agreed the catalog has nothing; one
    // unreachable source makes the whole answer inconclusive, so a legacy
    // cached cover is never discarded on the strength of a transport failure.
    return ranAnySource && everySourceConfirmedNoMatch
        ? const _CoverArtProviderLookup.notFound()
        : const _CoverArtProviderLookup.unavailable();
  }

  /// Stores [bytes] as the cover for [cacheKey], or returns null when they
  /// carry nothing the user would see.
  ///
  /// The blank-image guard lives here rather than at each writer so the
  /// invariant is "the cache never holds an invisible cover" instead of
  /// "every caller remembers to check".
  Future<CoverArtResult?> _writeBytesIntoCache(
    String cacheKey,
    Uint8List bytes, {
    required CoverArtSource source,
  }) async {
    if (bytes.isEmpty || !await imageHasVisiblePixels(bytes)) {
      return null;
    }
    final cacheDir = await _ensureCacheDir();
    final file = File(p.join(cacheDir.path, '$cacheKey.img'));
    await file.writeAsBytes(bytes);
    // The guard above already answered this for these exact bytes; record it so
    // the read path never decodes them again.
    await _writeCachedCoverSource(
      cacheDir,
      cacheKey,
      source,
      probedVisible: true,
    );
    _scheduleCacheEviction(cacheDir);
    return CoverArtResult(
      uri: file.uri.toString(),
      source: source,
      revision: _bumpCoverRevision(cacheKey),
    );
  }

  Future<String> _copyIntoCache(
    String cacheKey,
    String sourcePath, {
    required CoverArtSource source,
  }) async {
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
    await _writeCachedCoverSource(cacheDir, cacheKey, source);
    _scheduleCacheEviction(cacheDir);
    return target.path;
  }

  /// Reads the sidecar: where a cached cover came from, and whether it has
  /// already been confirmed to have pixels the user can see.
  ///
  /// A sidecar written before the verdict was recorded simply reports
  /// [_CachedCoverRecord.probedVisible] as false, which costs one probe; the
  /// read path then writes the verdict back, so it is paid once and not again.
  Future<_CachedCoverRecord> _readCachedCoverRecord(
    Directory cacheDir,
    String cacheKey,
  ) async {
    final sourceFile = _cachedCoverSourceFile(cacheDir, cacheKey);
    try {
      final fields = (await sourceFile.readAsString()).trim().split(
        _sidecarSeparator,
      );
      final value = fields.first.trim();
      for (final source in CoverArtSource.values) {
        if (source != CoverArtSource.none && value == source.name) {
          return _CachedCoverRecord(
            source: source,
            probedVisible:
                fields.length > 1 && fields[1].trim() == _visibleMarker,
          );
        }
      }
    } catch (_) {}
    return const _CachedCoverRecord(
      source: CoverArtSource.cache,
      probedVisible: false,
    );
  }

  Future<void> _writeCachedCoverSource(
    Directory cacheDir,
    String cacheKey,
    CoverArtSource source, {
    bool probedVisible = false,
  }) async {
    final payload = probedVisible
        ? '${source.name}$_sidecarSeparator$_visibleMarker'
        : source.name;
    try {
      await _cachedCoverSourceFile(
        cacheDir,
        cacheKey,
      ).writeAsString(payload, flush: true);
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

  Future<void> _deleteCachedCover(String cacheKey) async {
    final cacheDir = await _ensureCacheDir();
    try {
      await File(p.join(cacheDir.path, '$cacheKey.img')).delete();
    } catch (_) {}
    await _clearCachedCoverSource(cacheDir, cacheKey);
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

  void _markProviderRefresh(String cacheKey) {
    _forcedProviderRefreshCacheKeys.remove(cacheKey);
    _forcedProviderRefreshCacheKeys[cacheKey] = true;
    _trimLru(_forcedProviderRefreshCacheKeys, _maxMemoryCacheEntries);
  }

  bool _consumeProviderRefresh(String cacheKey) {
    return _forcedProviderRefreshCacheKeys.remove(cacheKey) != null;
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

  /// Kept as a static so the ~10 existing call sites in this part-library read
  /// naturally; the implementation itself lives in one place.
  static void _trimLru<K, V>(LinkedHashMap<K, V> cache, int maxEntries) =>
      trimLru(cache, maxEntries);
}
