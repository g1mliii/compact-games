import 'package:flutter/foundation.dart';

import '../../models/game_info.dart';

const int _nameDuplicateLargeInstallBytes = 2 * 1024 * 1024 * 1024;
const int _nameDuplicateStaleMaxBytes = 512 * 1024 * 1024;
final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]+');

List<GameInfo> dedupeDiscoveredGames(List<GameInfo> games) {
  if (games.isEmpty) {
    return const <GameInfo>[];
  }

  final seen = <String>{};
  final pathDeduped = <GameInfo>[];
  for (final game in games) {
    final key = _pathDedupKey(game.path);
    if (!seen.add(key)) {
      continue;
    }
    pathDeduped.add(game);
  }

  final staleNamePaths = _findLikelyStaleNameDuplicatePaths(pathDeduped);
  if (staleNamePaths.isEmpty) {
    return pathDeduped;
  }
  return pathDeduped
      .where((game) => !staleNamePaths.contains(_pathDedupKey(game.path)))
      .toList(growable: false);
}

String _pathDedupKey(String path) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    return path;
  }

  var normalized = path.replaceAll('/', '\\');
  while (normalized.length > 3 && normalized.endsWith('\\')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.toLowerCase();
}

Set<String> _findLikelyStaleNameDuplicatePaths(List<GameInfo> games) {
  final grouped = <String, List<GameInfo>>{};
  for (final game in games) {
    final key = _nameDedupKey(game);
    grouped.putIfAbsent(key, () => <GameInfo>[]).add(game);
  }

  final stalePaths = <String>{};
  for (final group in grouped.values) {
    if (group.length < 2) {
      continue;
    }

    var largest = group.first;
    for (final game in group.skip(1)) {
      if (game.sizeBytes > largest.sizeBytes) {
        largest = game;
      }
    }

    if (largest.sizeBytes < _nameDuplicateLargeInstallBytes) {
      continue;
    }

    for (final game in group) {
      if (_pathDedupKey(game.path) == _pathDedupKey(largest.path)) {
        continue;
      }
      if (game.sizeBytes <= _nameDuplicateStaleMaxBytes) {
        stalePaths.add(_pathDedupKey(game.path));
      }
    }
  }

  return stalePaths;
}

String _nameDedupKey(GameInfo game) {
  final normalizedName = game.name.toLowerCase().replaceAll(
    _nonAlphanumeric,
    '',
  );
  final safeName = normalizedName.isEmpty
      ? game.name.toLowerCase()
      : normalizedName;
  return '${game.platform}:$safeName';
}
