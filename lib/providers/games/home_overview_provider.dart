import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../models/game_info.dart';
import 'game_list_provider.dart';

enum HomePrimaryActionKind { reviewEligible, openInventory, addGame }

@immutable
class HomeOverviewUiModel {
  const HomeOverviewUiModel({
    required this.totalGames,
    required this.readyCount,
    required this.compressedCount,
    required this.protectedCount,
    required this.reclaimableBytes,
    required this.firstReadyPath,
    required this.primaryAction,
  });

  final int totalGames;
  final int readyCount;
  final int compressedCount;
  final int protectedCount;
  final int reclaimableBytes;
  final String? firstReadyPath;
  final HomePrimaryActionKind primaryAction;

  bool get hasGames => totalGames > 0;
}

const double _fallbackSavingsRatio = 0.18;
const double _minimumSavingsRatio = 0.12;
const double _maximumSavingsRatio = 0.32;

final homeOverviewProvider = Provider<HomeOverviewUiModel>((ref) {
  final games =
      ref.watch(gameListProvider.select((state) => state.valueOrNull?.games)) ??
      const <GameInfo>[];
  var totalGames = 0;
  var readyCount = 0;
  var compressedCount = 0;
  var protectedCount = 0;
  String? firstReadyPath;

  // Single-pass: compute savings ratio inputs and ready-bytes simultaneously.
  var ratioSum = 0.0;
  var ratioCount = 0;
  var readySizeBytes = 0;
  for (final game in games) {
    totalGames += 1;
    if (game.isCompressed) {
      compressedCount += 1;
      if (game.sizeBytes > 0 && game.bytesSaved > 0) {
        ratioSum += game.bytesSaved / game.sizeBytes;
        ratioCount += 1;
      }
      continue;
    }
    if (game.isDirectStorage || game.isUnsupported) {
      protectedCount += 1;
      continue;
    }
    readyCount += 1;
    readySizeBytes += game.sizeBytes;
    firstReadyPath ??= game.path;
  }
  final learnedRatio = ratioCount == 0
      ? _fallbackSavingsRatio
      : (ratioSum / ratioCount)
          .clamp(_minimumSavingsRatio, _maximumSavingsRatio);
  final reclaimableBytes = (readySizeBytes * learnedRatio).round();

  final primaryAction = readyCount > 0
      ? HomePrimaryActionKind.reviewEligible
      : totalGames > 0
      ? HomePrimaryActionKind.openInventory
      : HomePrimaryActionKind.addGame;

  return HomeOverviewUiModel(
    totalGames: totalGames,
    readyCount: readyCount,
    compressedCount: compressedCount,
    protectedCount: protectedCount,
    reclaimableBytes: reclaimableBytes,
    firstReadyPath: firstReadyPath,
    primaryAction: primaryAction,
  );
});

