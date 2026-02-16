/// Immutable snapshot of compression progress.
class CompressionProgress {
  final String gameName;
  final int filesTotal;
  final int filesProcessed;
  final int bytesOriginal;
  final int bytesCompressed;
  final int bytesSaved;
  final Duration? estimatedTimeRemaining;
  final bool isComplete;

  const CompressionProgress({
    required this.gameName,
    required this.filesTotal,
    required this.filesProcessed,
    required this.bytesOriginal,
    required this.bytesCompressed,
    required this.bytesSaved,
    this.estimatedTimeRemaining,
    this.isComplete = false,
  });

  double get fraction {
    final total = filesTotal < filesProcessed ? filesProcessed : filesTotal;
    if (total == 0) return 0.0;
    return filesProcessed / total;
  }

  int get percent => (fraction * 100).clamp(0, 100).toInt();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompressionProgress &&
          runtimeType == other.runtimeType &&
          gameName == other.gameName &&
          filesTotal == other.filesTotal &&
          filesProcessed == other.filesProcessed &&
          bytesOriginal == other.bytesOriginal &&
          bytesCompressed == other.bytesCompressed &&
          bytesSaved == other.bytesSaved &&
          estimatedTimeRemaining == other.estimatedTimeRemaining &&
          isComplete == other.isComplete;

  @override
  int get hashCode => Object.hash(
    gameName,
    filesTotal,
    filesProcessed,
    bytesOriginal,
    bytesCompressed,
    bytesSaved,
    estimatedTimeRemaining,
    isComplete,
  );
}
