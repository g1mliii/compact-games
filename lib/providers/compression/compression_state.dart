import '../../models/compression_algorithm.dart';
import '../../models/compression_progress.dart';
import '../../models/compression_stats.dart';

/// Status of a compression job.
enum CompressionJobStatus { pending, running, completed, failed, cancelled }

enum CompressionJobType { compression, decompression }

/// Immutable state for a single compression job.
class CompressionJobState {
  final int runId;
  final String gamePath;
  final String gameName;
  final CompressionJobType type;
  final CompressionAlgorithm algorithm;
  final bool allowDirectStorageOverride;
  final int? ioParallelismOverride;
  final CompressionJobStatus status;
  final CompressionProgress? progress;
  final CompressionStats? stats;
  final String? error;

  const CompressionJobState({
    required this.runId,
    required this.gamePath,
    required this.gameName,
    required this.type,
    required this.algorithm,
    this.allowDirectStorageOverride = false,
    this.ioParallelismOverride,
    this.status = CompressionJobStatus.pending,
    this.progress,
    this.stats,
    this.error,
  });

  bool get isActive =>
      status == CompressionJobStatus.pending ||
      status == CompressionJobStatus.running;

  CompressionJobState copyWith({
    CompressionJobType? type,
    CompressionJobStatus? status,
    CompressionProgress? Function()? progress,
    CompressionStats? Function()? stats,
    String? Function()? error,
  }) {
    return CompressionJobState(
      runId: runId,
      gamePath: gamePath,
      gameName: gameName,
      type: type ?? this.type,
      algorithm: algorithm,
      allowDirectStorageOverride: allowDirectStorageOverride,
      ioParallelismOverride: ioParallelismOverride,
      status: status ?? this.status,
      progress: progress != null ? progress() : this.progress,
      stats: stats != null ? stats() : this.stats,
      error: error != null ? error() : this.error,
    );
  }
}

/// Immutable top-level compression state.
class CompressionState {
  final CompressionJobState? activeJob;
  final List<CompressionJobState> queue;
  final List<CompressionJobState> history;

  const CompressionState({
    this.activeJob,
    this.queue = const [],
    this.history = const [],
  });

  bool get hasActiveJob => activeJob != null && activeJob!.isActive;
  int get queueLength => queue.length;

  bool isQueued(int runId) => queue.any((job) => job.runId == runId);

  CompressionState copyWith({
    CompressionJobState? Function()? activeJob,
    List<CompressionJobState>? queue,
    List<CompressionJobState>? history,
  }) {
    return CompressionState(
      activeJob: activeJob != null ? activeJob() : this.activeJob,
      queue: queue ?? this.queue,
      history: history ?? this.history,
    );
  }
}
