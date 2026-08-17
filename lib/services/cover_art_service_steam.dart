part of 'cover_art_service.dart';

extension _CoverArtServiceSteam on CoverArtService {
  Future<String?> _resolveSteamLibraryCover(
    String gamePath, {
    required int? knownSteamAppId,
    required RustBridgeService? rustBridge,
  }) async {
    final steamAppsPath = SteamAppIdLookup.steamAppsPathFromGamePath(gamePath);
    if (steamAppsPath == null) {
      return null;
    }

    final steamRootPath = p.dirname(steamAppsPath);
    // Discovery normally already knows the id; the manifest lookup is only a
    // backfill for a game that arrived without one.
    final appId =
        knownSteamAppId?.toString() ??
        await _resolveSteamAppIdFromGamePath(gamePath, rustBridge);
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
    const maxEntries = 512;
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
    var entriesScanned = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        entriesScanned += 1;
        if (entriesScanned > maxEntries) {
          break;
        }
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
    } on FileSystemException {
      // Steam cache is optional; continue to API and executable-icon fallbacks.
    }
    return bestPath;
  }

  /// Delegates to Rust's ACF parser rather than reading manifests here, so
  /// cover art and discovery can never disagree about which app owns a folder.
  Future<String?> _resolveSteamAppIdFromGamePath(
    String gamePath,
    RustBridgeService? rustBridge,
  ) async {
    return (await SteamAppIdLookup.resolveAppId(
      gamePath,
      rustBridge,
    ))?.toString();
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
}
