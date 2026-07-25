import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../models/game_info.dart';
import 'game_list_provider.dart';

@immutable
class HomeOverviewUiModel {
  const HomeOverviewUiModel({
    required this.readyCount,
    required this.reclaimableBytes,
    required this.firstReadyPath,
  });

  final int readyCount;
  final int reclaimableBytes;
  final String? firstReadyPath;
}

const double _fallbackSavingsRatio = 0.18;
const double _minimumSavingsRatio = 0.12;
const double _maximumSavingsRatio = 0.32;

final homeOverviewProvider = Provider<HomeOverviewUiModel>((ref) {
  final games =
      ref.watch(gameListProvider.select((state) => state.value?.games)) ??
      const <GameInfo>[];
  var readyCount = 0;
  String? firstReadyPath;

  // Single-pass: compute savings ratio inputs and ready-bytes simultaneously.
  var ratioSum = 0.0;
  var ratioCount = 0;
  var readySizeBytes = 0;
  for (final game in games) {
    if (game.isCompressed) {
      if (game.sizeBytes > 0 && game.bytesSaved > 0) {
        ratioSum += game.bytesSaved / game.sizeBytes;
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
  final learnedRatio = ratioCount == 0
      ? _fallbackSavingsRatio
      : (ratioSum / ratioCount).clamp(
          _minimumSavingsRatio,
          _maximumSavingsRatio,
        );
  final reclaimableBytes = (readySizeBytes * learnedRatio).round();

  return HomeOverviewUiModel(
    readyCount: readyCount,
    reclaimableBytes: reclaimableBytes,
    firstReadyPath: firstReadyPath,
  );
});
