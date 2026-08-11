import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_aggregate_provider.dart';

/// Everything the Library Home surface draws, bounded by construction.
///
/// Scalar totals plus at most three game paths. The paths are resolved back to
/// names through `singleGameProvider` at paint time rather than being copied
/// here, so this model never holds a [GameInfo] alive.
@immutable
class LibraryHomeUiModel {
  const LibraryHomeUiModel({
    required this.totalGames,
    required this.compressedCount,
    required this.actualBytesSaved,
    required this.largestInstallPath,
    required this.largestInstallBytes,
    required this.biggestSaverPath,
    required this.biggestSaverBytes,
    required this.mostRecentCompressedPath,
    required this.mostRecentCompressedAt,
  });

  final int totalGames;
  final int compressedCount;
  final int actualBytesSaved;

  final String? largestInstallPath;
  final int largestInstallBytes;

  final String? biggestSaverPath;
  final int biggestSaverBytes;

  final String? mostRecentCompressedPath;
  final DateTime? mostRecentCompressedAt;

  bool get hasGames => totalGames > 0;

  @override
  bool operator ==(Object other) {
    return other is LibraryHomeUiModel &&
        other.totalGames == totalGames &&
        other.compressedCount == compressedCount &&
        other.actualBytesSaved == actualBytesSaved &&
        other.largestInstallPath == largestInstallPath &&
        other.largestInstallBytes == largestInstallBytes &&
        other.biggestSaverPath == biggestSaverPath &&
        other.biggestSaverBytes == biggestSaverBytes &&
        other.mostRecentCompressedPath == mostRecentCompressedPath &&
        other.mostRecentCompressedAt == mostRecentCompressedAt;
  }

  @override
  int get hashCode => Object.hash(
    totalGames,
    compressedCount,
    actualBytesSaved,
    largestInstallPath,
    largestInstallBytes,
    biggestSaverPath,
    biggestSaverBytes,
    mostRecentCompressedPath,
    mostRecentCompressedAt,
  );
}

/// Library Home's view of the shared reduction. Adds no scan of its own.
final libraryHomeProvider = Provider<LibraryHomeUiModel>((ref) {
  final aggregate = ref.watch(libraryAggregateProvider);
  return LibraryHomeUiModel(
    totalGames: aggregate.totalGames,
    compressedCount: aggregate.compressedCount,
    actualBytesSaved: aggregate.actualBytesSaved,
    largestInstallPath: aggregate.largestInstallPath,
    largestInstallBytes: aggregate.largestInstallBytes,
    biggestSaverPath: aggregate.biggestSaverPath,
    biggestSaverBytes: aggregate.biggestSaverBytes,
    mostRecentCompressedPath: aggregate.mostRecentCompressedPath,
    mostRecentCompressedAt: aggregate.mostRecentCompressedAt,
  );
});
