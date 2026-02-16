import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/compression_progress.dart';
import 'compression_provider.dart';

/// Active compression progress. Returns null when no compression is running.
final activeCompressionProgressProvider =
    Provider<CompressionProgress?>((ref) {
  return ref.watch(
    compressionProvider.select((s) => s.activeJob?.progress),
  );
});

/// Name of the game currently being compressed (for header/tray display).
final compressingGameNameProvider = Provider<String?>((ref) {
  return ref.watch(
    compressionProvider.select((s) => s.activeJob?.gameName),
  );
});
