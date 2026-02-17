import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/game_info.dart';

class ManualGameImportResult {
  const ManualGameImportResult({required this.game, required this.wasAdded});

  final GameInfo game;
  final bool wasAdded;
}

class ManualGameImportTarget {
  const ManualGameImportTarget({
    required this.folderPath,
    required this.fallbackName,
  });

  final String folderPath;
  final String fallbackName;
}

ManualGameImportTarget resolveManualImportTarget(String inputPath) {
  final normalized = p.normalize(inputPath.trim());
  if (_looksLikeExecutablePath(normalized)) {
    final folderPath = p.normalize(p.dirname(normalized));
    final fallbackName = p.basenameWithoutExtension(normalized).trim();
    return ManualGameImportTarget(
      folderPath: folderPath,
      fallbackName: fallbackName.isEmpty
          ? _fallbackGameNameFromFolder(folderPath)
          : fallbackName,
    );
  }

  return ManualGameImportTarget(
    folderPath: normalized,
    fallbackName: _fallbackGameNameFromFolder(normalized),
  );
}

GameInfo? pickManualGameFromScan(
  List<GameInfo> scanResults,
  String folderPath,
) {
  if (scanResults.isEmpty) {
    return null;
  }

  final targetKey = manualImportPathKey(folderPath);
  for (final game in scanResults) {
    if (manualImportPathKey(game.path) == targetKey) {
      return game;
    }
  }

  if (scanResults.length == 1) {
    return scanResults.first;
  }

  return null;
}

String manualImportPathKey(String path) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    return path;
  }

  var normalized = path.replaceAll('/', '\\');
  while (normalized.length > 3 && normalized.endsWith('\\')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.toLowerCase();
}

String _fallbackGameNameFromFolder(String folderPath) {
  final name = p.basename(folderPath).trim();
  if (name.isNotEmpty && name != '.' && name != p.separator) {
    return name;
  }
  return 'Custom Game';
}

bool _looksLikeExecutablePath(String inputPath) {
  return inputPath.toLowerCase().endsWith('.exe');
}
