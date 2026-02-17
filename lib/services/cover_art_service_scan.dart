part of 'cover_art_service.dart';

extension _CoverArtServiceScan on CoverArtService {
  Future<String?> _resolveLauncherSpecificCover(GameInfo game) async {
    final roots = <String>[game.path];
    switch (game.platform) {
      case Platform.epicGames:
        roots.add(p.join(game.path, '.egstore'));
      case Platform.gogGalaxy:
        roots.add(p.join(game.path, 'gog'));
      case Platform.ubisoftConnect:
        roots.add(p.join(game.path, 'cache'));
      case Platform.eaApp:
        roots.add(p.join(game.path, '__Installer'));
      case Platform.battleNet:
        roots.add(p.join(game.path, '_retail_'));
      case Platform.xboxGamePass:
        roots.add(p.join(game.path, 'Content'));
      case Platform.steam:
      case Platform.custom:
        break;
    }

    for (final root in roots) {
      final candidate = await _findImageCandidate(
        rootPath: root,
        maxDepth: 2,
        maxFiles: 300,
      );
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }

  Future<String?> _findFolderImageCandidate(String rootPath) {
    return _findImageCandidate(rootPath: rootPath, maxDepth: 2, maxFiles: 250);
  }

  Future<String?> _findImageCandidate({
    required String rootPath,
    required int maxDepth,
    required int maxFiles,
  }) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      return null;
    }

    const allowedExtensions = <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.bmp',
      '.ico',
    };
    const keywords = <String>[
      'cover',
      'capsule',
      'poster',
      'banner',
      'icon',
      'hero',
      'logo',
    ];

    var seen = 0;
    String? bestPath;
    var bestScore = -1;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (seen >= maxFiles) {
        break;
      }
      if (entity is! File) {
        continue;
      }
      seen++;

      final relative = p.relative(entity.path, from: rootPath);
      final depth = p.split(relative).length;
      if (depth > maxDepth + 1) {
        continue;
      }

      final ext = p.extension(entity.path).toLowerCase();
      if (!allowedExtensions.contains(ext)) {
        continue;
      }

      final fileName = p.basenameWithoutExtension(entity.path).toLowerCase();
      var score = 0;
      for (var i = 0; i < keywords.length; i++) {
        if (fileName.contains(keywords[i])) {
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
