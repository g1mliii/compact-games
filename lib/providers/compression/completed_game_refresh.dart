import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_info.dart';
import '../games/game_list_provider.dart';
import 'compression_state.dart';

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

Future<void> refreshCompletedCompressionGame({
  required ProviderReader read,
  required String gamePath,
  DateTime? completedAt,
}) {
  return refreshCompletedGameAfterJob(
    read: read,
    gamePath: gamePath,
    jobType: CompressionJobType.compression,
    completedAt: completedAt,
  );
}

Future<void> refreshCompletedGameAfterJob({
  required ProviderReader read,
  required String gamePath,
  required CompressionJobType jobType,
  DateTime? completedAt,
}) async {
  final bridge = read(rustBridgeServiceProvider);
  final gameListNotifier = read(gameListProvider.notifier);

  if (jobType == CompressionJobType.compression) {
    _applyOptimisticCompressionCompletionUpdate(
      read: read,
      gamePath: gamePath,
      completedAt: completedAt ?? DateTime.now(),
    );
    try {
      bridge.persistCompressionHistory();
    } catch (_) {
      // Best-effort flush; in-memory history lookup should still work.
    }
  }

  try {
    bridge.clearDiscoveryCacheEntry(gamePath);
  } catch (_) {
    // Best-effort cache eviction; hydration/refresh fallback still applies.
  }

  final gameListState = read(gameListProvider).valueOrNull;
  if (gameListState == null) {
    gameListNotifier.requestHydration(gamePath);
    return;
  }

  final existingGame = _currentGameForPath(read, gamePath);
  if (existingGame == null) {
    return;
  }

  try {
    final hydrated = await bridge.hydrateGame(
      gamePath: existingGame.path,
      gameName: existingGame.name,
      platform: existingGame.platform,
    );
    if (hydrated != null) {
      final currentGame = _currentGameForPath(read, gamePath);
      gameListNotifier.updateGame(
        _mergeCompletedGameRefresh(
          currentGame: currentGame,
          hydratedGame: hydrated,
          jobType: jobType,
        ),
      );
      return;
    }
    gameListNotifier.requestHydration(gamePath);
  } catch (_) {
    gameListNotifier.requestHydration(gamePath);
  }
}

void _applyOptimisticCompressionCompletionUpdate({
  required ProviderReader read,
  required String gamePath,
  required DateTime completedAt,
}) {
  final currentGame = _currentGameForPath(read, gamePath);
  if (currentGame == null) {
    return;
  }

  read(gameListProvider.notifier).updateGame(
    currentGame.copyWith(
      isCompressed: true,
      lastPlayed: () => completedAt,
      lastCompressedAt: () => completedAt,
    ),
  );
}

GameInfo? _currentGameForPath(ProviderReader read, String gamePath) {
  final gameListState = read(gameListProvider).valueOrNull;
  if (gameListState == null) {
    return null;
  }

  final matchIndex = gameListState.games.indexWhere((g) => g.path == gamePath);
  return matchIndex >= 0 ? gameListState.games[matchIndex] : null;
}

GameInfo _mergeCompletedGameRefresh({
  required GameInfo? currentGame,
  required GameInfo hydratedGame,
  required CompressionJobType jobType,
}) {
  if (jobType != CompressionJobType.compression || currentGame == null) {
    return hydratedGame;
  }

  final currentLastCompressed = currentGame.lastCompressed;
  final hydratedLastCompressed = hydratedGame.lastCompressed;
  final shouldPreserveCurrentTimestamp =
      currentLastCompressed != null &&
      (hydratedLastCompressed == null ||
          hydratedLastCompressed.isBefore(currentLastCompressed));

  return hydratedGame.copyWith(
    isCompressed: hydratedGame.isCompressed || currentGame.isCompressed,
    compressedSize: () =>
        hydratedGame.compressedSize ?? currentGame.compressedSize,
    lastPlayed: shouldPreserveCurrentTimestamp
        ? () => currentGame.lastCompressedAt ?? currentGame.lastPlayed
        : null,
    lastCompressedAt: shouldPreserveCurrentTimestamp
        ? () => currentGame.lastCompressed
        : null,
  );
}
