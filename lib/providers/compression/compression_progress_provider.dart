import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/compression_progress.dart';
import '../system/route_state_provider.dart';
import 'compression_state.dart';
import 'compression_provider.dart';

const int _bytesPerMiB = 1024 * 1024;
const int _bytesPerGiB = 1024 * 1024 * 1024;
const int _bytesPer16MiB = 16 * _bytesPerMiB;
const int _bytesPer32MiB = 32 * _bytesPerMiB;
const int _bytesPer128MiB = 128 * _bytesPerMiB;

class CompressionActivityUiModel {
  const CompressionActivityUiModel({
    required this.type,
    required this.gameName,
    required this.filesProcessed,
    required this.filesTotal,
    required this.percent,
    required this.bytesDelta,
    required this.hasKnownFileTotal,
    required this.isFileCountApproximate,
    required this.canCancel,
    this.etaSeconds,
  });

  final CompressionJobType type;
  final String gameName;
  final int filesProcessed;
  final int filesTotal;
  final int percent;
  final int bytesDelta;
  final bool hasKnownFileTotal;
  final bool isFileCountApproximate;
  final bool canCancel;
  final int? etaSeconds;

  bool get isCompression => type == CompressionJobType.compression;

  String get statusLabel => isCompression ? 'Compressing' : 'Decompressing';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompressionActivityUiModel &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          gameName == other.gameName &&
          filesProcessed == other.filesProcessed &&
          filesTotal == other.filesTotal &&
          percent == other.percent &&
          bytesDelta == other.bytesDelta &&
          hasKnownFileTotal == other.hasKnownFileTotal &&
          isFileCountApproximate == other.isFileCountApproximate &&
          canCancel == other.canCancel &&
          etaSeconds == other.etaSeconds;

  @override
  int get hashCode => Object.hash(
    type,
    gameName,
    filesProcessed,
    filesTotal,
    percent,
    bytesDelta,
    hasKnownFileTotal,
    isFileCountApproximate,
    canCancel,
    etaSeconds,
  );
}

const int _exactFileCountThreshold = 200;
const int _leadingExactFileUpdates = 12;

class _BucketedFileProgress {
  const _BucketedFileProgress({
    required this.filesProcessed,
    required this.isApproximate,
  });

  final int filesProcessed;
  final bool isApproximate;
}

/// Active compression/decompression job. Null when idle.
final activeCompressionJobProvider = Provider<CompressionJobState?>((ref) {
  return ref.watch(
    compressionProvider.select((s) {
      final job = s.activeJob;
      if (job == null || !job.isActive) {
        return null;
      }
      return job;
    }),
  );
});

/// Stable identifier for the currently active manual job instance.
final activeCompressionRunIdProvider = Provider<int?>((ref) {
  return ref.watch(activeCompressionJobProvider.select((job) => job?.runId));
});

/// Run id of the floating monitor the user dismissed.
final dismissedFloatingActivityRunIdProvider = StateProvider<int?>((ref) {
  return null;
});

/// Whether the floating monitor should render at all.
///
/// This stays independent from the full UI activity model so the overlay can
/// return early without subscribing to progress-heavy display updates while it
/// is hidden.
final showFloatingActivityOverlayProvider = Provider<bool>((ref) {
  final isHomeRoute = ref.watch(isHomeRouteProvider);
  if (isHomeRoute) {
    return false;
  }

  final activeRunId = ref.watch(activeCompressionRunIdProvider);
  if (activeRunId == null) {
    return false;
  }

  final dismissedRunId = ref.watch(dismissedFloatingActivityRunIdProvider);
  return activeRunId != dismissedRunId;
});

/// Active compression progress. Returns null when no compression is running.
final activeCompressionProgressProvider = Provider<CompressionProgress?>((ref) {
  final job = ref.watch(activeCompressionJobProvider);
  if (job == null || job.type != CompressionJobType.compression) {
    return null;
  }
  return job.progress;
});

/// Name of the game currently being compressed (for header/tray display).
/// Returns null for decompression jobs so the tray shows the correct mode.
final compressingGameNameProvider = Provider<String?>((ref) {
  final job = ref.watch(activeCompressionJobProvider);
  if (job == null || job.type != CompressionJobType.compression) return null;
  return job.gameName;
});

/// Derived UI model for inline/floating activity surfaces.
///
/// Uses bucketed display values so trivial raw progress changes do not
/// trigger unnecessary widget rebuilds.
final activeCompressionUiModelProvider = Provider<CompressionActivityUiModel?>((
  ref,
) {
  return ref.watch(
    compressionProvider.select((state) {
      final job = state.activeJob;
      if (job == null || !job.isActive) {
        return null;
      }

      final progress = job.progress;
      final rawFilesProcessed = progress?.filesProcessed ?? 0;
      final rawFilesTotal = progress?.filesTotal ?? 0;
      final filesTotal = rawFilesTotal < rawFilesProcessed
          ? rawFilesProcessed
          : rawFilesTotal;
      final hasKnownFileTotal = filesTotal > 0 || rawFilesProcessed > 0;
      final bucketedFileProgress = _bucketDisplayFileProgress(
        filesProcessed: rawFilesProcessed,
        filesTotal: filesTotal,
        isComplete: progress?.isComplete ?? false,
      );
      final percent = _bucketDisplayPercent(
        filesProcessed: bucketedFileProgress.filesProcessed,
        filesTotal: filesTotal,
        hasKnownFileTotal: hasKnownFileTotal,
        isComplete: progress?.isComplete ?? false,
      );
      final etaSeconds = _bucketEtaSeconds(
        progress?.estimatedTimeRemaining?.inSeconds,
      );

      return CompressionActivityUiModel(
        type: job.type,
        gameName: job.gameName,
        filesProcessed: bucketedFileProgress.filesProcessed,
        filesTotal: filesTotal,
        percent: percent,
        bytesDelta: _bucketDisplayBytes(progress?.bytesSaved ?? 0),
        hasKnownFileTotal: hasKnownFileTotal,
        isFileCountApproximate: bucketedFileProgress.isApproximate,
        canCancel: job.isActive,
        etaSeconds: etaSeconds,
      );
    }),
  );
});

int _bucketDisplayBytes(int bytes) {
  if (bytes <= 0) {
    return 0;
  }
  if (bytes < _bytesPer16MiB) {
    return 0;
  }
  if (bytes < 512 * _bytesPerMiB) {
    return (bytes ~/ _bytesPer16MiB) * _bytesPer16MiB;
  }
  if (bytes < _bytesPerGiB) {
    return (bytes ~/ _bytesPer32MiB) * _bytesPer32MiB;
  }
  return (bytes ~/ _bytesPer128MiB) * _bytesPer128MiB;
}

_BucketedFileProgress _bucketDisplayFileProgress({
  required int filesProcessed,
  required int filesTotal,
  required bool isComplete,
}) {
  if (filesProcessed <= 0 || filesTotal <= 0) {
    return _BucketedFileProgress(
      filesProcessed: filesProcessed,
      isApproximate: false,
    );
  }

  if (isComplete || filesProcessed >= filesTotal) {
    return _BucketedFileProgress(
      filesProcessed: filesTotal,
      isApproximate: false,
    );
  }

  if (filesTotal <= _exactFileCountThreshold) {
    return _BucketedFileProgress(
      filesProcessed: filesProcessed,
      isApproximate: false,
    );
  }

  final step = _displayFileStep(filesTotal);
  if (filesProcessed <= math.min(step, _leadingExactFileUpdates)) {
    return _BucketedFileProgress(
      filesProcessed: filesProcessed,
      isApproximate: false,
    );
  }

  final bucketed = (filesProcessed ~/ step) * step;
  return _BucketedFileProgress(
    filesProcessed: bucketed.clamp(0, filesTotal),
    isApproximate: true,
  );
}

int _displayFileStep(int filesTotal) {
  if (filesTotal <= 500) {
    return 10;
  }
  if (filesTotal <= 1500) {
    return 25;
  }
  if (filesTotal <= 5000) {
    return 50;
  }
  return 100;
}

int _bucketDisplayPercent({
  required int filesProcessed,
  required int filesTotal,
  required bool hasKnownFileTotal,
  required bool isComplete,
}) {
  if (!hasKnownFileTotal || filesTotal <= 0) {
    return 0;
  }
  if (isComplete || filesProcessed >= filesTotal) {
    return 100;
  }
  return ((filesProcessed / filesTotal) * 100).round().clamp(0, 100);
}

int? _bucketEtaSeconds(int? seconds) {
  if (seconds == null || seconds <= 0) {
    return seconds;
  }

  if (seconds <= 15) {
    return seconds;
  }
  if (seconds < 120) {
    return _roundToNearest(seconds, 10);
  }
  if (seconds < 600) {
    return _roundToNearest(seconds, 30);
  }

  return _roundToNearest(seconds, 60);
}

int _roundToNearest(int value, int bucket) {
  return ((value / bucket).round()) * bucket;
}
