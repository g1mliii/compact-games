/// Compression algorithms available via Windows Overlay Filter (WOF).
enum CompressionAlgorithm {
  xpress4k,
  xpress8k,
  xpress16k,
  lzx;

  String get displayName => switch (this) {
    xpress4k => 'XPRESS 4K (Fast)',
    xpress8k => 'XPRESS 8K (Balanced)',
    xpress16k => 'XPRESS 16K (Better Ratio)',
    lzx => 'LZX (Maximum)',
  };
}
