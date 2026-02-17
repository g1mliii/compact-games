/// Pre-compression estimate used for confirmation UX.
class CompressionEstimate {
  final int scannedFiles;
  final int sampledBytes;
  final int estimatedCompressedBytes;
  final int estimatedSavedBytes;
  final double estimatedSavingsRatio;
  final String? artworkCandidatePath;
  final String? executableCandidatePath;

  const CompressionEstimate({
    required this.scannedFiles,
    required this.sampledBytes,
    required this.estimatedCompressedBytes,
    required this.estimatedSavedBytes,
    required this.estimatedSavingsRatio,
    this.artworkCandidatePath,
    this.executableCandidatePath,
  });

  double get estimatedSavingsPercent => estimatedSavingsRatio * 100.0;
}
