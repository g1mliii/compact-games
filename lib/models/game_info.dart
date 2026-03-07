/// Supported game distribution platforms.
enum Platform {
  steam,
  epicGames,
  gogGalaxy,
  ubisoftConnect,
  eaApp,
  battleNet,
  xboxGamePass,
  custom;

  String get displayName => switch (this) {
    steam => 'Steam',
    epicGames => 'Epic Games',
    gogGalaxy => 'GOG Galaxy',
    ubisoftConnect => 'Ubisoft Connect',
    eaApp => 'EA App',
    battleNet => 'Battle.net',
    xboxGamePass => 'Xbox Game Pass',
    custom => 'Custom',
  };
}

/// Immutable game information mirroring Rust GameInfo.
class GameInfo {
  final String name;
  final String path;
  final Platform platform;
  final int sizeBytes;
  final int? compressedSize;
  final bool isCompressed;
  final bool isDirectStorage;
  final bool isUnsupported;
  final bool excluded;

  /// Legacy timestamp field from older transports. Avoid using this for new UI.
  final DateTime? lastPlayed;

  /// Dedicated timestamp for last successful compression.
  final DateTime? lastCompressedAt;

  /// Pre-lowered name for O(1) search filtering (avoids per-keystroke allocation).
  late final String normalizedName = name.toLowerCase();

  /// Pre-lowered path for stable sort tiebreaking (avoids per-comparison allocation).
  late final String normalizedPath = path.toLowerCase();

  GameInfo({
    required this.name,
    required this.path,
    required this.platform,
    required this.sizeBytes,
    this.compressedSize,
    this.isCompressed = false,
    this.isDirectStorage = false,
    this.isUnsupported = false,
    this.excluded = false,
    this.lastPlayed,
    this.lastCompressedAt,
  });

  int get bytesSaved {
    if (compressedSize == null) return 0;
    final saved = sizeBytes - compressedSize!;
    return saved > 0 ? saved : 0;
  }

  double get savingsRatio {
    if (sizeBytes == 0 || !isCompressed) return 0.0;
    return bytesSaved / sizeBytes;
  }

  DateTime? get lastCompressed {
    if (!isCompressed) {
      return null;
    }
    return lastCompressedAt ?? lastPlayed;
  }

  GameInfo copyWith({
    String? name,
    String? path,
    Platform? platform,
    int? sizeBytes,
    int? Function()? compressedSize,
    bool? isCompressed,
    bool? isDirectStorage,
    bool? isUnsupported,
    bool? excluded,
    DateTime? Function()? lastPlayed,
    DateTime? Function()? lastCompressedAt,
  }) {
    return GameInfo(
      name: name ?? this.name,
      path: path ?? this.path,
      platform: platform ?? this.platform,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      compressedSize: compressedSize != null
          ? compressedSize()
          : this.compressedSize,
      isCompressed: isCompressed ?? this.isCompressed,
      isDirectStorage: isDirectStorage ?? this.isDirectStorage,
      isUnsupported: isUnsupported ?? this.isUnsupported,
      excluded: excluded ?? this.excluded,
      lastPlayed: lastPlayed != null ? lastPlayed() : this.lastPlayed,
      lastCompressedAt: lastCompressedAt != null
          ? lastCompressedAt()
          : this.lastCompressedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameInfo &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          name == other.name &&
          platform == other.platform &&
          sizeBytes == other.sizeBytes &&
          compressedSize == other.compressedSize &&
          isCompressed == other.isCompressed &&
          isDirectStorage == other.isDirectStorage &&
          isUnsupported == other.isUnsupported &&
          excluded == other.excluded &&
          lastPlayed == other.lastPlayed &&
          lastCompressedAt == other.lastCompressedAt;

  @override
  int get hashCode => Object.hash(
    path,
    name,
    platform,
    sizeBytes,
    compressedSize,
    isCompressed,
    isDirectStorage,
    isUnsupported,
    excluded,
    lastPlayed,
    lastCompressedAt,
  );

  @override
  String toString() =>
      'GameInfo(name: $name, platform: ${platform.displayName})';
}
