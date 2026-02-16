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
  final bool excluded;
  final DateTime? lastPlayed;

  const GameInfo({
    required this.name,
    required this.path,
    required this.platform,
    required this.sizeBytes,
    this.compressedSize,
    this.isCompressed = false,
    this.isDirectStorage = false,
    this.excluded = false,
    this.lastPlayed,
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

  GameInfo copyWith({
    String? name,
    String? path,
    Platform? platform,
    int? sizeBytes,
    int? Function()? compressedSize,
    bool? isCompressed,
    bool? isDirectStorage,
    bool? excluded,
    DateTime? Function()? lastPlayed,
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
      excluded: excluded ?? this.excluded,
      lastPlayed: lastPlayed != null ? lastPlayed() : this.lastPlayed,
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
          excluded == other.excluded &&
          lastPlayed == other.lastPlayed;

  @override
  int get hashCode => Object.hash(
        path,
        name,
        platform,
        sizeBytes,
        compressedSize,
        isCompressed,
        isDirectStorage,
        excluded,
        lastPlayed,
      );

  @override
  String toString() =>
      'GameInfo(name: $name, platform: ${platform.displayName})';
}
