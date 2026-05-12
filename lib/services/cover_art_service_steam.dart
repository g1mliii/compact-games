part of 'cover_art_service.dart';

extension _CoverArtServiceSteam on CoverArtService {
  Future<String?> _resolveSteamLibraryCover(String gamePath) async {
    final steamAppsPath = _steamAppsPathFromGamePath(gamePath);
    if (steamAppsPath == null) {
      return null;
    }

    final steamRootPath = p.dirname(steamAppsPath);
    final appId = await _resolveSteamAppIdFromGamePath(gamePath);
    if (appId == null) {
      return null;
    }

    final libraryCache = Directory(
      p.join(steamRootPath, 'appcache', 'librarycache'),
    );
    if (!await libraryCache.exists()) {
      return null;
    }

    // Modern Steam (post-2024 client revamp) stores cover art in a per-appid
    // subdirectory with stable filenames like library_600x900.jpg.
    final perAppDir = Directory(p.join(libraryCache.path, appId));
    if (await perAppDir.exists()) {
      const perAppCandidates = <String>[
        'library_600x900.jpg',
        'library_capsule.jpg',
        'header.jpg',
        'library_hero.jpg',
        'logo.png',
      ];
      for (final name in perAppCandidates) {
        final path = p.join(perAppDir.path, name);
        if (await File(path).exists()) {
          return path;
        }
      }
      final fallback = await _resolveSteamLibraryCoverByScanInDir(perAppDir);
      if (fallback != null) {
        return fallback;
      }
    }

    // Legacy flat layout (older Steam clients): <appid>_library_600x900.jpg.
    final legacyCandidates = <String>[
      '${appId}_library_600x900_2x.jpg',
      '${appId}_library_600x900.jpg',
      '${appId}_library_capsule.jpg',
      '${appId}_header.jpg',
      '${appId}_hero_capsule.jpg',
      '${appId}_logo.png',
    ];
    for (final name in legacyCandidates) {
      final path = p.join(libraryCache.path, name);
      if (await File(path).exists()) {
        return path;
      }
    }
    return _resolveSteamLibraryCoverByScan(libraryCache, appId);
  }

  /// Scan a per-appid subfolder (modern Steam layout) for the best art file.
  /// Same scoring as the legacy scan, just without the `<appid>_` prefix
  /// requirement since these files live inside their own appid-keyed dir.
  Future<String?> _resolveSteamLibraryCoverByScanInDir(Directory dir) async {
    const allowedExtensions = <String>{'.jpg', '.jpeg', '.png', '.webp'};
    const preferredTokens = <String>[
      '600x900',
      'library',
      'capsule',
      'header',
      'hero',
      'logo',
    ];

    String? bestPath;
    var bestScore = -1;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      final ext = p.extension(name);
      if (!allowedExtensions.contains(ext)) continue;

      var score = 0;
      for (var i = 0; i < preferredTokens.length; i++) {
        if (name.contains(preferredTokens[i])) {
          score += 12 - i;
        }
      }
      if (ext == '.jpg' || ext == '.png') score += 2;
      if (score > bestScore) {
        bestScore = score;
        bestPath = entity.path;
      }
    }
    return bestPath;
  }

  Future<String?> _resolveSteamAppIdFromGamePath(String gamePath) {
    final steamAppsPath = _steamAppsPathFromGamePath(gamePath);
    if (steamAppsPath == null) {
      return Future<String?>.value(null);
    }
    final gameFolderName = p.basename(gamePath).toLowerCase();
    return _resolveSteamAppId(steamAppsPath, gameFolderName);
  }

  Future<String?> _resolveSteamAppId(
    String steamAppsPath,
    String gameFolderName,
  ) async {
    final now = DateTime.now();
    final cacheKey = steamAppsPath.toLowerCase();
    final cached = CoverArtService._steamManifestCache.remove(cacheKey);
    if (cached != null &&
        now.difference(cached.loadedAt) <=
            CoverArtService._steamManifestCacheTtl) {
      CoverArtService._steamManifestCache[cacheKey] = cached;
      return cached.appIdByInstallDir[gameFolderName];
    }

    final loaded = await _loadSteamManifestIndex(steamAppsPath);
    if (loaded == null) {
      return null;
    }

    CoverArtService._steamManifestCache[cacheKey] = loaded;
    CoverArtService._trimLru(
      CoverArtService._steamManifestCache,
      CoverArtService._maxSteamManifestCacheEntries,
    );
    return loaded.appIdByInstallDir[gameFolderName];
  }

  Future<_SteamManifestIndex?> _loadSteamManifestIndex(
    String steamAppsPath,
  ) async {
    final steamAppsDir = Directory(steamAppsPath);
    if (!await steamAppsDir.exists()) {
      return null;
    }

    final entries = await steamAppsDir
        .list(followLinks: false)
        .where((e) => e is File)
        .cast<File>()
        .toList();
    final appIdPattern = RegExp(
      r'appmanifest_(\d+)\.acf$',
      caseSensitive: false,
    );
    final installDirPattern = RegExp(
      r'"installdir"\s*"([^"]+)"',
      caseSensitive: false,
    );
    final appIdByInstallDir = <String, String>{};
    for (final file in entries) {
      final name = p.basename(file.path);
      final match = appIdPattern.firstMatch(name);
      if (match == null) {
        continue;
      }

      String content;
      try {
        content = await file.readAsString();
      } catch (_) {
        content = '';
      }
      if (content.isEmpty) {
        continue;
      }

      final installMatch = installDirPattern.firstMatch(content);
      if (installMatch == null) {
        continue;
      }

      final installDir = installMatch.group(1)?.toLowerCase();
      final appId = match.group(1);
      if (installDir == null ||
          installDir.isEmpty ||
          appId == null ||
          appId.isEmpty) {
        continue;
      }
      appIdByInstallDir[installDir] = appId;
    }

    return _SteamManifestIndex(
      loadedAt: DateTime.now(),
      appIdByInstallDir: appIdByInstallDir,
    );
  }

  Future<String?> _resolveSteamLibraryCoverByScan(
    Directory libraryCache,
    String appId,
  ) async {
    const allowedExtensions = <String>{'.jpg', '.jpeg', '.png', '.webp'};
    const preferredTokens = <String>[
      '600x900',
      'library',
      'capsule',
      'header',
      'hero',
      'logo',
    ];

    final prefix = '${appId}_';
    String? bestPath;
    var bestScore = -1;
    await for (final entity in libraryCache.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final name = p.basename(entity.path).toLowerCase();
      if (!name.startsWith(prefix)) {
        continue;
      }

      final ext = p.extension(name);
      if (!allowedExtensions.contains(ext)) {
        continue;
      }

      var score = 0;
      for (var i = 0; i < preferredTokens.length; i++) {
        if (name.contains(preferredTokens[i])) {
          score += 12 - i;
        }
      }
      if (ext == '.jpg' || ext == '.png') {
        score += 2;
      }

      if (score > bestScore) {
        bestScore = score;
        bestPath = entity.path;
      }
    }
    return bestPath;
  }

  String? _steamAppsPathFromGamePath(String gamePath) {
    const marker = r'\steamapps\common\';
    final lower = gamePath.toLowerCase();
    final markerIndex = lower.lastIndexOf(marker);
    if (markerIndex < 0) {
      return null;
    }
    return gamePath.substring(0, markerIndex + r'\steamapps'.length);
  }
}

class _SteamManifestIndex {
  const _SteamManifestIndex({
    required this.loadedAt,
    required this.appIdByInstallDir,
  });

  final DateTime loadedAt;
  final Map<String, String> appIdByInstallDir;
}
