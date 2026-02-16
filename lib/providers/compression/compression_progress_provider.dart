import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/compression_progress.dart';
import 'compression_state.dart';
import 'compression_provider.dart';

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

/// Active compression progress. Returns null when no compression is running.
final activeCompressionProgressProvider = Provider<CompressionProgress?>((ref) {
  final job = ref.watch(activeCompressionJobProvider);
  if (job == null || job.type != CompressionJobType.compression) {
    return null;
  }
  return job.progress;
});

/// Name of the game currently being compressed (for header/tray display).
final compressingGameNameProvider = Provider<String?>((ref) {
  final job = ref.watch(activeCompressionJobProvider);
  return job?.gameName;
});
