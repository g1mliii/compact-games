import '../../models/compression_algorithm.dart';
import '../../models/compression_progress.dart';
import '../../models/compression_stats.dart';

/// Status of a compression job.
enum CompressionJobStatus { pending, running, completed, failed, cancelled }

enum CompressionJobType { compression, decompression }

/// Immutable state for a single compression job.
class CompressionJobState {
  final String gamePath;
  final String gameName;
  final CompressionJobType type;
  final CompressionAlgorithm algorithm;
  final CompressionJobStatus status;
  final CompressionProgress? progress;
  final CompressionStats? stats;
  final String? error;

  const CompressionJobState({
    required this.gamePath,
    required this.gameName,
    required this.type,
    required this.algorithm,
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
      gamePath: gamePath,
      gameName: gameName,
      type: type ?? this.type,
      algorithm: algorithm,
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
  final List<CompressionJobState> history;

  const CompressionState({this.activeJob, this.history = const []});

  bool get hasActiveJob => activeJob != null && activeJob!.isActive;

  CompressionState copyWith({
    CompressionJobState? Function()? activeJob,
    List<CompressionJobState>? history,
  }) {
    return CompressionState(
      activeJob: activeJob != null ? activeJob() : this.activeJob,
      history: history ?? this.history,
    );
  }
}
