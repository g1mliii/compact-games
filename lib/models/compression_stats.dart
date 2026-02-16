/// Immutable result of a completed compression operation.
class CompressionStats {
  final int originalBytes;
  final int compressedBytes;
  final int filesProcessed;
  final int filesSkipped;
  final int durationMs;

  const CompressionStats({
    required this.originalBytes,
    required this.compressedBytes,
    required this.filesProcessed,
    required this.filesSkipped,
    required this.durationMs,
  });

  int get bytesSaved {
    final saved = originalBytes - compressedBytes;
    return saved > 0 ? saved : 0;
  }

  double get savingsRatio {
    if (originalBytes == 0) return 0.0;
    return bytesSaved / originalBytes;
  }

  Duration get duration => Duration(milliseconds: durationMs);
}
