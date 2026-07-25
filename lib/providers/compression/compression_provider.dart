import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/compression_algorithm.dart';
import '../../models/compression_progress.dart';
import '../games/game_list_provider.dart';
import '../settings/settings_provider.dart';
import '../restore/restore_gate_provider.dart';
import 'completed_game_refresh.dart';
import 'compression_state.dart';

final compressionProvider =
    NotifierProvider<CompressionNotifier, CompressionState>(
      CompressionNotifier.new,
    );

class CompressionNotifier extends Notifier<CompressionState> {
  StreamSubscription<CompressionProgress>? _progressSubscription;
  Completer<CompressionJobStatus>? _activeJobCompletion;
  final Map<int, Completer<CompressionJobStatus>> _queuedJobCompletions =
      <int, Completer<CompressionJobStatus>>{};
  Timer? _historyTimer;
  Timer? _cancelWatchdog;
  bool _disposed = false;
  bool _cancelRequested = false;
  int _nextRunId = 1;

  @override
  CompressionState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _cancelRequested = false;
      _historyTimer?.cancel();
      _cancelSubscription();
      _completeActiveJobCompletion(CompressionJobStatus.cancelled);
      for (final completion in _queuedJobCompletions.values) {
        if (!completion.isCompleted) {
          completion.complete(CompressionJobStatus.cancelled);
        }
      }
      _queuedJobCompletions.clear();
    });
    return const CompressionState();
  }

  /// Start compression for a game, or append it to the manual FIFO queue.
  Future<bool> startCompression({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm? algorithm,
    bool? allowDirectStorageOverride,
  }) async {
    if (ref.read(restoreGateProvider) || _containsGamePath(gamePath)) {
      return false;
    }

    final settings = ref.read(settingsProvider).value?.settings;
    final algo =
        algorithm ?? settings?.algorithm ?? CompressionAlgorithm.xpress8k;
    final dsOverride =
        allowDirectStorageOverride ??
        settings?.directStorageOverrideEnabled ??
        false;
    final ioParallelismOverride = settings?.ioParallelismOverride;
    return _scheduleJob(
      CompressionJobState(
        runId: _allocateRunId(),
        gamePath: gamePath,
        gameName: gameName,
        type: CompressionJobType.compression,
        algorithm: algo,
        allowDirectStorageOverride: dsOverride,
        ioParallelismOverride: ioParallelismOverride,
      ),
    );
  }

  void _beginCompression(CompressionJobState job) {
    try {
      final bridge = ref.read(rustBridgeServiceProvider);
      final stream = bridge.compressGame(
        gamePath: job.gamePath,
        gameName: job.gameName,
        algorithm: job.algorithm,
        allowDirectStorageOverride: job.allowDirectStorageOverride,
        ioParallelismOverride: job.ioParallelismOverride,
      );
      _subscribeToProgressStream(stream);
    } catch (e) {
      _failJob('Failed to start: $e');
      return;
    }
  }

  /// Cancel the active manual compression/decompression job.
  void cancelCompression() {
    final job = state.activeJob;
    if (job == null || !job.isActive) return;
    _cancelRequested = true;
    state = state.copyWith(
      activeJob: () => job.copyWith(status: CompressionJobStatus.cancelled),
    );
    _completeActiveJobCompletion(CompressionJobStatus.cancelled);
    try {
      ref.read(rustBridgeServiceProvider).cancelCompression();
    } catch (e) {
      _cancelRequested = false;
      _failJob('Failed to cancel compression: $e');
      return;
    }

    // Keep the subscription until the native operation exits. Rust owns the
    // serialization guard, so starting the next queued job before its stream
    // closes can race that guard and incorrectly fail the next job. Guard
    // against a native stream that never closes (e.g. a worker stalled on a
    // locked file) with a watchdog so the queue can never wedge permanently.
    _armCancelWatchdog();
    _drainQueue();
  }

  /// If a cancelled operation's native stream never emits done/error, its
  /// subscription would stay live forever and every later [_drainQueue] would
  /// early-return, wedging the queue. This detaches the stalled subscription
  /// and advances the queue after a generous grace period.
  void _armCancelWatchdog() {
    _cancelWatchdog?.cancel();
    _cancelWatchdog = Timer(const Duration(seconds: 20), () {
      if (_disposed) return;
      if (_progressSubscription == null) return;
      final job = state.activeJob;
      _cancelSubscription();
      if (job != null && !job.isActive) {
        _archiveJob(job);
      }
      _drainQueue();
    });
  }

  /// Start decompression with progress streaming.
  Future<void> startDecompression({
    required String gamePath,
    required String gameName,
  }) async {
    _scheduleDecompression(gamePath: gamePath, gameName: gameName);
  }

  /// Start decompression and complete with the final job status.
  Future<CompressionJobStatus?> startDecompressionAndWait({
    required String gamePath,
    required String gameName,
  }) async {
    if (_containsGamePath(gamePath)) return null;
    final completion = Completer<CompressionJobStatus>();
    final started = _scheduleDecompression(
      gamePath: gamePath,
      gameName: gameName,
      completion: completion,
    );
    if (!started) return null;
    return completion.future;
  }

  bool _scheduleDecompression({
    required String gamePath,
    required String gameName,
    Completer<CompressionJobStatus>? completion,
  }) {
    if (_containsGamePath(gamePath)) return false;
    final settings = ref.read(settingsProvider).value?.settings;
    return _scheduleJob(
      CompressionJobState(
        runId: _allocateRunId(),
        gamePath: gamePath,
        gameName: gameName,
        type: CompressionJobType.decompression,
        algorithm: CompressionAlgorithm.xpress4k,
        ioParallelismOverride: settings?.ioParallelismOverride,
      ),
      completion: completion,
    );
  }

  void _beginDecompression(CompressionJobState job) {
    try {
      final bridge = ref.read(rustBridgeServiceProvider);
      final stream = bridge.decompressGame(
        job.gamePath,
        gameName: job.gameName,
        ioParallelismOverride: job.ioParallelismOverride,
      );
      _subscribeToProgressStream(stream);
    } catch (e) {
      if (_disposed) return;
      _cancelRequested = false;
      _failJob('Decompression failed: $e');
    }
  }

  bool _scheduleJob(
    CompressionJobState job, {
    Completer<CompressionJobStatus>? completion,
  }) {
    if (_disposed || _containsGamePath(job.gamePath)) return false;
    if (completion != null) {
      _queuedJobCompletions[job.runId] = completion;
    }

    if (state.hasActiveJob || _progressSubscription != null) {
      state = state.copyWith(queue: <CompressionJobState>[...state.queue, job]);
      return true;
    }

    _beginJob(job);
    return true;
  }

  void _beginJob(CompressionJobState job) {
    if (_disposed) return;
    final previousJob = state.activeJob;
    if (previousJob != null) {
      _archiveJob(previousJob);
    }

    _completeActiveJobCompletion(CompressionJobStatus.cancelled);
    _activeJobCompletion = _queuedJobCompletions.remove(job.runId);
    _cancelRequested = false;
    state = state.copyWith(
      activeJob: () => job.copyWith(
        status: CompressionJobStatus.running,
        progress: () => _initialProgress(job.gameName),
        error: () => null,
      ),
    );

    switch (job.type) {
      case CompressionJobType.compression:
        _beginCompression(job);
        break;
      case CompressionJobType.decompression:
        _beginDecompression(job);
        break;
    }
  }

  /// Removes one pending job without affecting the active operation.
  void removeFromQueue(int runId) {
    final index = state.queue.indexWhere((job) => job.runId == runId);
    if (index < 0) return;
    final updatedQueue = <CompressionJobState>[...state.queue]..removeAt(index);
    state = state.copyWith(queue: updatedQueue);
    _completeQueuedJob(runId, CompressionJobStatus.cancelled);
  }

  /// Clears all pending jobs without affecting the active operation.
  void clearQueue() {
    if (state.queue.isEmpty) return;
    final removedRunIds = state.queue.map((job) => job.runId).toList();
    state = state.copyWith(queue: const <CompressionJobState>[]);
    for (final runId in removedRunIds) {
      _completeQueuedJob(runId, CompressionJobStatus.cancelled);
    }
  }

  bool _containsGamePath(String gamePath) {
    final normalizedPath = _normalizeGamePath(gamePath);
    final activeJob = state.activeJob;
    if (activeJob != null &&
        (activeJob.isActive || _progressSubscription != null) &&
        _normalizeGamePath(activeJob.gamePath) == normalizedPath) {
      return true;
    }
    return state.queue.any(
      (job) => _normalizeGamePath(job.gamePath) == normalizedPath,
    );
  }

  String _normalizeGamePath(String gamePath) {
    var normalized = gamePath.trim().replaceAll('/', '\\').toLowerCase();
    while (normalized.length > 3 && normalized.endsWith('\\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  void _completeQueuedJob(int runId, CompressionJobStatus status) {
    final completion = _queuedJobCompletions.remove(runId);
    if (completion == null || completion.isCompleted) return;
    completion.complete(status);
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
    final job = state.activeJob;
    if (_cancelRequested ||
        job?.status == CompressionJobStatus.cancelled ||
        _isCancellationMessage(message)) {
      _cancelRequested = false;
      _cancelSubscription();
      if (job != null) {
        _completeActiveJobCompletion(CompressionJobStatus.cancelled);
        _archiveJob(job.copyWith(status: CompressionJobStatus.cancelled));
      }
      _drainQueue();
      return;
    }
    _cancelRequested = false;
    _failJob(message);
  }

  void _onDone() {
    final job = state.activeJob;
    final wasCancelled =
        _cancelRequested || job?.status == CompressionJobStatus.cancelled;
    _cancelSubscription();
    _cancelRequested = false;
    if (_disposed) return;
    if (job == null) {
      _drainQueue();
      return;
    }
    if (wasCancelled) {
      _completeActiveJobCompletion(CompressionJobStatus.cancelled);
      _archiveJob(job.copyWith(status: CompressionJobStatus.cancelled));
      _drainQueue();
      return;
    }
    if (!job.isActive) {
      _drainQueue();
      return;
    }
    _completeJob();
  }

  void _completeJob() {
    _cancelRequested = false;
    _cancelSubscription();
    final job = state.activeJob;
    if (job == null) return;

    final completedJob = job.copyWith(status: CompressionJobStatus.completed);
    _completeActiveJobCompletion(CompressionJobStatus.completed);
    _archiveJob(completedJob);
    _drainQueue();

    unawaited(
      refreshCompletedGameAfterJob(
        read: ref.read,
        gamePath: completedJob.gamePath,
        jobType: completedJob.type,
        completedAt: completedJob.type == CompressionJobType.compression
            ? DateTime.now()
            : null,
      ),
    );
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

    _completeActiveJobCompletion(CompressionJobStatus.failed);
    // Keep the failed job in the active slot for its display window before
    // draining. Calling _drainQueue() here would immediately archive the failed
    // job whenever the queue is non-empty, cancelling that window so the user
    // never sees which game failed. The timer archives the job and then advances
    // the queue.
    _moveToHistoryAfterDelay();
  }

  void _completeActiveJobCompletion(CompressionJobStatus status) {
    final completion = _activeJobCompletion;
    _activeJobCompletion = null;
    if (completion == null || completion.isCompleted) return;
    completion.complete(status);
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
      // Advance any queued jobs now that the failed job's display window has
      // elapsed and it has been archived to history.
      _drainQueue();
    });
  }

  void _archiveJob(CompressionJobState job) {
    _historyTimer?.cancel();
    state = state.copyWith(
      activeJob: () => null,
      history: [job, ...state.history.take(9)],
    );
  }

  void _drainQueue() {
    if (_disposed || state.hasActiveJob || _progressSubscription != null) {
      return;
    }
    if (state.queue.isEmpty) return;

    final terminalJob = state.activeJob;
    if (terminalJob != null) {
      _archiveJob(terminalJob);
    }
    if (state.queue.isEmpty) return;

    final nextJob = state.queue.first;
    state = state.copyWith(
      activeJob: () => null,
      queue: state.queue.skip(1).toList(growable: false),
    );
    _beginJob(nextJob);
  }

  void _cancelSubscription() {
    _cancelWatchdog?.cancel();
    _cancelWatchdog = null;
    _progressSubscription?.cancel();
    _progressSubscription = null;
  }

  int _allocateRunId() {
    final runId = _nextRunId;
    _nextRunId += 1;
    return runId;
  }

  void _subscribeToProgressStream(Stream<CompressionProgress> stream) {
    _cancelSubscription();
    _progressSubscription = stream.listen(
      _onProgress,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }
}
