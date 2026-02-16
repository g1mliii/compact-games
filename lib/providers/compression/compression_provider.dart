import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/compression_algorithm.dart';
import '../../models/compression_progress.dart';
import '../games/game_list_provider.dart';
import '../settings/settings_provider.dart';
import 'compression_state.dart';

final compressionProvider =
    NotifierProvider<CompressionNotifier, CompressionState>(
      CompressionNotifier.new,
    );

class CompressionNotifier extends Notifier<CompressionState> {
  StreamSubscription<CompressionProgress>? _progressSubscription;
  Timer? _historyTimer;
  bool _disposed = false;

  @override
  CompressionState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _historyTimer?.cancel();
      _cancelSubscription();
    });
    return const CompressionState();
  }

  /// Start compression for a game. Only one job at a time.
  Future<void> startCompression({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm? algorithm,
  }) async {
    if (state.hasActiveJob) return;

    final algo =
        algorithm ??
        ref.read(settingsProvider).valueOrNull?.settings.algorithm ??
        CompressionAlgorithm.xpress8k;

    state = state.copyWith(
      activeJob: () => CompressionJobState(
        gamePath: gamePath,
        gameName: gameName,
        algorithm: algo,
        status: CompressionJobStatus.running,
      ),
    );

    try {
      final bridge = ref.read(rustBridgeServiceProvider);
      final stream = bridge.compressGame(
        gamePath: gamePath,
        gameName: gameName,
        algorithm: algo,
      );

      _cancelSubscription();
      _progressSubscription = stream.listen(
        (progress) => _onProgress(progress),
        onError: (Object error) => _onError(error.toString()),
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      _failJob('Failed to start: $e');
    }
  }

  /// Cancel the active compression job.
  void cancelCompression() {
    final job = state.activeJob;
    if (job == null || !job.isActive) return;

    _cancelSubscription();
    ref.read(rustBridgeServiceProvider).cancelCompression();

    state = state.copyWith(
      activeJob: () => job.copyWith(status: CompressionJobStatus.cancelled),
    );

    _moveToHistoryAfterDelay();
  }

  /// Start decompression (no progress stream).
  Future<void> startDecompression({
    required String gamePath,
    required String gameName,
  }) async {
    if (state.hasActiveJob) return;

    state = state.copyWith(
      activeJob: () => CompressionJobState(
        gamePath: gamePath,
        gameName: gameName,
        algorithm: CompressionAlgorithm.xpress4k,
        status: CompressionJobStatus.running,
      ),
    );

    try {
      final bridge = ref.read(rustBridgeServiceProvider);
      await bridge.decompressGame(gamePath);
      if (_disposed) return;

      _completeJob();
    } catch (e) {
      if (_disposed) return;
      _failJob('Decompression failed: $e');
    }
  }

  void _onProgress(CompressionProgress progress) {
    if (_disposed) return;
    final job = state.activeJob;
    if (job == null) return;

    state = state.copyWith(
      activeJob: () => job.copyWith(progress: () => progress),
    );
  }

  void _onError(String message) {
    if (_disposed) return;
    _failJob(message);
  }

  void _onDone() {
    if (_disposed) return;
    final job = state.activeJob;
    if (job == null || !job.isActive) return;
    _completeJob();
  }

  void _completeJob() {
    _cancelSubscription();
    final job = state.activeJob;
    if (job == null) return;

    final completedJob = job.copyWith(status: CompressionJobStatus.completed);

    state = CompressionState(
      activeJob: null,
      history: [completedJob, ...state.history.take(9)],
    );

    unawaited(_refreshCompletedGame(completedJob));
  }

  void _failJob(String message) {
    _cancelSubscription();
    final job = state.activeJob;
    if (job == null) return;

    state = state.copyWith(
      activeJob: () => job.copyWith(
        status: CompressionJobStatus.failed,
        error: () => message,
      ),
    );

    _moveToHistoryAfterDelay();
  }

  void _moveToHistoryAfterDelay() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      final job = state.activeJob;
      if (job == null || job.isActive) return;

      state = CompressionState(
        activeJob: null,
        history: [job, ...state.history.take(9)],
      );
    });
  }

  void _cancelSubscription() {
    _progressSubscription?.cancel();
    _progressSubscription = null;
  }

  Future<void> _refreshCompletedGame(CompressionJobState job) async {
    final gameListState = ref.read(gameListProvider).valueOrNull;
    if (gameListState == null) {
      ref.read(gameListProvider.notifier).refresh();
      return;
    }

    final matchIndex = gameListState.games.indexWhere(
      (g) => g.path == job.gamePath,
    );
    final existingGame = matchIndex >= 0
        ? gameListState.games[matchIndex]
        : null;
    if (existingGame == null) {
      ref.read(gameListProvider.notifier).refresh();
      return;
    }

    try {
      final bridge = ref.read(rustBridgeServiceProvider);
      final hydrated = await bridge.hydrateGame(
        gamePath: existingGame.path,
        gameName: existingGame.name,
        platform: existingGame.platform,
      );
      if (_disposed) return;
      if (hydrated != null) {
        ref.read(gameListProvider.notifier).updateGame(hydrated);
        return;
      }
    } catch (_) {
      // Best-effort fallback below.
    }

    if (_disposed) return;
    ref.read(gameListProvider.notifier).refresh();
  }
}
