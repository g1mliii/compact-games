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
  bool _cancelRequested = false;

  @override
  CompressionState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _cancelRequested = false;
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
    if (state.hasActiveJob || _progressSubscription != null) return;

    final algo =
        algorithm ??
        ref.read(settingsProvider).valueOrNull?.settings.algorithm ??
        CompressionAlgorithm.xpress8k;
    _cancelRequested = false;

    state = state.copyWith(
      activeJob: () => CompressionJobState(
        gamePath: gamePath,
        gameName: gameName,
        type: CompressionJobType.compression,
        algorithm: algo,
        status: CompressionJobStatus.running,
        progress: _initialProgress(gameName),
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
        _onProgress,
        onError: _onError,
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
    _cancelRequested = true;
    try {
      ref.read(rustBridgeServiceProvider).cancelCompression();
    } catch (e) {
      _cancelRequested = false;
      _failJob('Failed to cancel compression: $e');
      return;
    }
    // Prevent a stuck native stream from retaining a live subscription.
    _cancelSubscription();
    _cancelRequested = false;
    _archiveJob(job.copyWith(status: CompressionJobStatus.cancelled));
  }

  /// Start decompression (no progress stream).
  Future<void> startDecompression({
    required String gamePath,
    required String gameName,
  }) async {
    if (state.hasActiveJob || _progressSubscription != null) return;

    state = state.copyWith(
      activeJob: () => CompressionJobState(
        gamePath: gamePath,
        gameName: gameName,
        type: CompressionJobType.decompression,
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
      _cancelRequested = false;
      _failJob('Decompression failed: $e');
    }
  }

  void _onProgress(CompressionProgress progress) {
    if (_disposed) return;
    if (_cancelRequested) return;
    final job = state.activeJob;
    if (job == null) return;

    final normalizedProgress = _normalizeProgress(progress);
    state = state.copyWith(
      activeJob: () => job.copyWith(progress: () => normalizedProgress),
    );
  }

  void _onError(Object error, [StackTrace? _]) {
    if (_disposed) return;
    final message = error.toString();
    if (_cancelRequested) {
      _cancelRequested = false;
      _cancelSubscription();
      final job = state.activeJob;
      if (job != null && job.isActive) {
        _archiveJob(job.copyWith(status: CompressionJobStatus.cancelled));
      }
      return;
    }
    if (_isCancellationMessage(message)) {
      _cancelRequested = false;
      _cancelSubscription();
      final job = state.activeJob;
      if (job != null && job.isActive) {
        _archiveJob(job.copyWith(status: CompressionJobStatus.cancelled));
      }
      return;
    }
    _cancelRequested = false;
    _failJob(message);
  }

  void _onDone() {
    _cancelSubscription();
    _cancelRequested = false;
    if (_disposed) return;
    final job = state.activeJob;
    if (job == null || !job.isActive) return;
    _completeJob();
  }

  void _completeJob() {
    _cancelRequested = false;
    _cancelSubscription();
    final job = state.activeJob;
    if (job == null) return;

    final completedJob = job.copyWith(status: CompressionJobStatus.completed);
    _archiveJob(completedJob);

    unawaited(_refreshCompletedGame(completedJob));
  }

  void _failJob(String message) {
    _cancelRequested = false;
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

  CompressionProgress _normalizeProgress(CompressionProgress progress) {
    if (progress.filesProcessed <= progress.filesTotal) {
      return progress;
    }

    return CompressionProgress(
      gameName: progress.gameName,
      filesTotal: progress.filesProcessed,
      filesProcessed: progress.filesProcessed,
      bytesOriginal: progress.bytesOriginal,
      bytesCompressed: progress.bytesCompressed,
      bytesSaved: progress.bytesSaved,
      estimatedTimeRemaining: progress.estimatedTimeRemaining,
      isComplete: progress.isComplete,
    );
  }

  bool _isCancellationMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('cancelled') || normalized.contains('canceled');
  }

  CompressionProgress _initialProgress(String gameName) {
    return CompressionProgress(
      gameName: gameName,
      filesTotal: 0,
      filesProcessed: 0,
      bytesOriginal: 0,
      bytesCompressed: 0,
      bytesSaved: 0,
      estimatedTimeRemaining: null,
      isComplete: false,
    );
  }

  void _moveToHistoryAfterDelay() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      final job = state.activeJob;
      if (job == null || job.isActive) return;
      _archiveJob(job);
    });
  }

  void _archiveJob(CompressionJobState job) {
    _historyTimer?.cancel();
    state = CompressionState(
      activeJob: null,
      history: [job, ...state.history.take(9)],
    );
  }

  void _cancelSubscription() {
    _progressSubscription?.cancel();
    _progressSubscription = null;
  }

  Future<void> _refreshCompletedGame(CompressionJobState job) async {
    final bridge = ref.read(rustBridgeServiceProvider);
    final gameListNotifier = ref.read(gameListProvider.notifier);
    try {
      bridge.clearDiscoveryCacheEntry(job.gamePath);
    } catch (_) {
      // Best-effort cache eviction; hydration/refresh fallback still applies.
    }

    final gameListState = ref.read(gameListProvider).valueOrNull;
    if (gameListState == null) {
      gameListNotifier.requestHydration(job.gamePath);
      return;
    }

    final matchIndex = gameListState.games.indexWhere(
      (g) => g.path == job.gamePath,
    );
    final existingGame = matchIndex >= 0
        ? gameListState.games[matchIndex]
        : null;
    if (existingGame == null) {
      return;
    }

    try {
      final hydrated = await bridge.hydrateGame(
        gamePath: existingGame.path,
        gameName: existingGame.name,
        platform: existingGame.platform,
      );
      if (_disposed) return;
      if (hydrated != null) {
        gameListNotifier.updateGame(hydrated);
        return;
      }
      gameListNotifier.requestHydration(job.gamePath);
    } catch (_) {
      gameListNotifier.requestHydration(job.gamePath);
    }
  }
}
