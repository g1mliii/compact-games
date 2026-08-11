import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_info.dart';
import 'game_list_provider.dart';

/// Everything the home surfaces need from the library, derived in one pass.
///
/// Both the compression overview banner and Library Home read from this, so a
/// library update walks the game list exactly once no matter how many
/// consumers are mounted. Only scalars and game paths are retained — never
/// [GameInfo] references — so the aggregate cannot pin a stale library
/// snapshot in memory.
@immutable
class LibraryAggregate {
  const LibraryAggregate({
    required this.totalGames,
    required this.compressedCount,
    required this.actualBytesSaved,
    required this.largestInstallPath,
    required this.largestInstallBytes,
    required this.biggestSaverPath,
    required this.biggestSaverBytes,
    required this.mostRecentCompressedPath,
    required this.mostRecentCompressedAt,
    required this.readyCount,
    required this.readySizeBytes,
    required this.firstReadyPath,
    required this.learnedSavingsRatio,
  });

  static const LibraryAggregate empty = LibraryAggregate(
    totalGames: 0,
    compressedCount: 0,
    actualBytesSaved: 0,
    largestInstallPath: null,
    largestInstallBytes: 0,
    biggestSaverPath: null,
    biggestSaverBytes: 0,
    mostRecentCompressedPath: null,
    mostRecentCompressedAt: null,
    readyCount: 0,
    readySizeBytes: 0,
    firstReadyPath: null,
    learnedSavingsRatio: _fallbackSavingsRatio,
  );

  /// Every discovered game, including compressed, DirectStorage, and
  /// unsupported entries.
  final int totalGames;
  final int compressedCount;

  /// Sum of [GameInfo.bytesSaved] across compressed games — measured, not
  /// estimated.
  final int actualBytesSaved;

  final String? largestInstallPath;
  final int largestInstallBytes;

  /// Game with the largest measured [GameInfo.bytesSaved].
  final String? biggestSaverPath;
  final int biggestSaverBytes;

  final String? mostRecentCompressedPath;
  final DateTime? mostRecentCompressedAt;

  /// Games that are neither compressed, DirectStorage, nor unsupported.
  final int readyCount;
  final int readySizeBytes;
  final String? firstReadyPath;

  /// Observed savings ratio across compressed games, clamped to a sane band
  /// and falling back to a fixed estimate when nothing is compressed yet.
  final double learnedSavingsRatio;

  /// Estimated bytes the ready games could still reclaim.
  int get reclaimableBytes => (readySizeBytes * learnedSavingsRatio).round();
}

const double _fallbackSavingsRatio = 0.18;
const double _minimumSavingsRatio = 0.12;
const double _maximumSavingsRatio = 0.32;

/// Single-pass reduction over the discovered library.
@visibleForTesting
LibraryAggregate buildLibraryAggregate(List<GameInfo> games) {
  if (games.isEmpty) {
    return LibraryAggregate.empty;
  }

  var compressedCount = 0;
  var actualBytesSaved = 0;
  var readyCount = 0;
  var readySizeBytes = 0;
  String? firstReadyPath;

  String? largestInstallPath;
  var largestInstallKey = '';
  var largestInstallBytes = 0;
  String? biggestSaverPath;
  var biggestSaverKey = '';
  var biggestSaverBytes = 0;
  String? mostRecentCompressedPath;
  var mostRecentCompressedKey = '';
  DateTime? mostRecentCompressedAt;

  var ratioSum = 0.0;
  var ratioCount = 0;

  for (final game in games) {
    // Largest install is a property of the whole library, so it is measured
    // before the compressed/ready split below. Ties break on the lowered path
    // so two same-size installs always resolve to the same winner.
    if (game.sizeBytes > largestInstallBytes ||
        (game.sizeBytes == largestInstallBytes &&
            largestInstallPath != null &&
            game.normalizedPath.compareTo(largestInstallKey) < 0)) {
      largestInstallBytes = game.sizeBytes;
      largestInstallPath = game.path;
      largestInstallKey = game.normalizedPath;
    }

    if (game.isCompressed) {
      compressedCount += 1;
      final saved = game.bytesSaved;
      actualBytesSaved += saved;
      if (saved > biggestSaverBytes ||
          (saved == biggestSaverBytes &&
              biggestSaverPath != null &&
              game.normalizedPath.compareTo(biggestSaverKey) < 0)) {
        biggestSaverBytes = saved;
        biggestSaverPath = game.path;
        biggestSaverKey = game.normalizedPath;
      }

      final compressedAt = game.lastCompressed;
      if (compressedAt != null &&
          (mostRecentCompressedAt == null ||
              compressedAt.isAfter(mostRecentCompressedAt) ||
              (compressedAt.isAtSameMomentAs(mostRecentCompressedAt) &&
                  game.normalizedPath.compareTo(mostRecentCompressedKey) <
                      0))) {
        mostRecentCompressedAt = compressedAt;
        mostRecentCompressedPath = game.path;
        mostRecentCompressedKey = game.normalizedPath;
      }

      if (game.sizeBytes > 0 && saved > 0) {
        ratioSum += saved / game.sizeBytes;
        ratioCount += 1;
      }
      continue;
    }

    if (game.isDirectStorage || game.isUnsupported) {
      continue;
    }

    readyCount += 1;
    readySizeBytes += game.sizeBytes;
    firstReadyPath ??= game.path;
  }

  return LibraryAggregate(
    totalGames: games.length,
    compressedCount: compressedCount,
    actualBytesSaved: actualBytesSaved,
    largestInstallPath: largestInstallPath,
    largestInstallBytes: largestInstallBytes,
    biggestSaverPath: biggestSaverPath,
    biggestSaverBytes: biggestSaverBytes,
    mostRecentCompressedPath: mostRecentCompressedPath,
    mostRecentCompressedAt: mostRecentCompressedAt,
    readyCount: readyCount,
    readySizeBytes: readySizeBytes,
    firstReadyPath: firstReadyPath,
    learnedSavingsRatio: ratioCount == 0
        ? _fallbackSavingsRatio
        : (ratioSum / ratioCount).clamp(
            _minimumSavingsRatio,
            _maximumSavingsRatio,
          ),
  );
}

/// The library reduction shared by every home surface.
///
/// Watches only the games list, so filter, sort, and search changes do not
/// re-run the pass.
final libraryAggregateProvider = Provider<LibraryAggregate>((ref) {
  final games =
      ref.watch(gameListProvider.select((state) => state.value?.games)) ??
      const <GameInfo>[];
  return buildLibraryAggregate(games);
});
