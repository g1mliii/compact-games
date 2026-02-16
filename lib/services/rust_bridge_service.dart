import 'dart:async';

import '../models/game_info.dart';
import '../models/compression_algorithm.dart';
import '../models/compression_progress.dart';
import '../models/compression_stats.dart';
import '../src/rust/api/automation.dart' as rust_automation;
import '../src/rust/api/compression.dart' as rust_compression;
import '../src/rust/api/discovery.dart' as rust_discovery;
import '../src/rust/api/minimal.dart' as rust_minimal;
import '../src/rust/api/types.dart' as rust_types;

class RustBridgeService {
  static const RustBridgeService instance = RustBridgeService._();

  const RustBridgeService._();

  /// Initialize the Rust core (logger, thread pool).
  String initApp() {
    return rust_minimal.initApp();
  }

  Future<List<GameInfo>> getAllGames() async {
    final frbGames = await rust_discovery.getAllGames();
    return frbGames.map(_mapFrbGameInfo).toList();
  }

  Future<List<GameInfo>> getAllGamesQuick() async {
    final frbGames = await rust_discovery.getAllGamesQuick();
    return frbGames.map(_mapFrbGameInfo).toList();
  }

  Future<List<GameInfo>> scanCustomFolder(String path) async {
    final frbGames = await rust_discovery.scanCustomFolder(path: path);
    return frbGames.map(_mapFrbGameInfo).toList();
  }

  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async {
    final frbPlatform = _toFrbPlatform(platform);
    final frbGame = await rust_discovery.hydrateGame(
      path: gamePath,
      name: gameName,
      platform: frbPlatform,
    );
    if (frbGame == null) {
      return null;
    }
    return _mapFrbGameInfo(frbGame);
  }

  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
  }) {
    final frbAlgorithm = _toFrbAlgorithm(algorithm);
    return rust_compression
        .compressGame(
          gamePath: gamePath,
          gameName: gameName,
          algorithm: frbAlgorithm,
        )
        .map(_mapFrbProgress);
  }

  /// Cancel the active compression job.
  void cancelCompression() {
    rust_compression.cancelCompression();
  }

  CompressionProgress? getCompressionProgress() {
    final progress = rust_compression.getCompressionProgress();
    if (progress == null) {
      return null;
    }
    return _mapFrbProgress(progress);
  }

  /// Decompress a game folder.
  Future<void> decompressGame(String gamePath) {
    return rust_compression.decompressGame(gamePath: gamePath);
  }

  /// Get compression ratio for a folder.
  Future<double> getCompressionRatio(String folderPath) {
    return rust_compression.getCompressionRatio(folderPath: folderPath);
  }

  /// Check if a game uses DirectStorage.
  bool isDirectStorage(String gamePath) {
    return rust_compression.isDirectstorage(gamePath: gamePath);
  }

  Future<void> startAutoCompression() {
    if (rust_automation.isAutoCompressionRunning()) {
      return Future.value();
    }
    return rust_automation.startAutoCompression();
  }

  void stopAutoCompression() {
    if (!rust_automation.isAutoCompressionRunning()) {
      return;
    }
    rust_automation.stopAutoCompression();
  }

  bool isAutoCompressionRunning() {
    return rust_automation.isAutoCompressionRunning();
  }
}

GameInfo _mapFrbGameInfo(rust_types.FrbGameInfo frb) {
  return GameInfo(
    name: frb.name,
    path: frb.path,
    platform: _mapFrbPlatform(frb.platform),
    sizeBytes: frb.sizeBytes.toInt(),
    compressedSize: frb.compressedSize?.toInt(),
    isCompressed: frb.isCompressed,
    isDirectStorage: frb.isDirectstorage,
    excluded: frb.excluded,
    lastPlayed: frb.lastPlayed != null
        ? DateTime.fromMillisecondsSinceEpoch(frb.lastPlayed!.toInt())
        : null,
  );
}

Platform _mapFrbPlatform(rust_types.FrbPlatform frb) {
  return switch (frb) {
    rust_types.FrbPlatform.steam => Platform.steam,
    rust_types.FrbPlatform.epicGames => Platform.epicGames,
    rust_types.FrbPlatform.gogGalaxy => Platform.gogGalaxy,
    rust_types.FrbPlatform.ubisoftConnect => Platform.ubisoftConnect,
    rust_types.FrbPlatform.eaApp => Platform.eaApp,
    rust_types.FrbPlatform.battleNet => Platform.battleNet,
    rust_types.FrbPlatform.xboxGamePass => Platform.xboxGamePass,
    rust_types.FrbPlatform.custom => Platform.custom,
  };
}

CompressionProgress _mapFrbProgress(rust_types.FrbCompressionProgress frb) {
  return CompressionProgress(
    gameName: frb.gameName,
    filesTotal: frb.filesTotal.toInt(),
    filesProcessed: frb.filesProcessed.toInt(),
    bytesOriginal: frb.bytesOriginal.toInt(),
    bytesCompressed: frb.bytesCompressed.toInt(),
    bytesSaved: frb.bytesSaved.toInt(),
    estimatedTimeRemaining: frb.estimatedTimeRemainingMs != null
        ? Duration(milliseconds: frb.estimatedTimeRemainingMs!.toInt())
        : null,
    isComplete: frb.isComplete,
  );
}

// ignore: unused_element
CompressionStats _mapFrbStats(rust_types.FrbCompressionStats frb) {
  return CompressionStats(
    originalBytes: frb.originalBytes.toInt(),
    compressedBytes: frb.compressedBytes.toInt(),
    filesProcessed: frb.filesProcessed.toInt(),
    filesSkipped: frb.filesSkipped.toInt(),
    durationMs: frb.durationMs.toInt(),
  );
}

rust_types.FrbCompressionAlgorithm _toFrbAlgorithm(CompressionAlgorithm algo) {
  return switch (algo) {
    CompressionAlgorithm.xpress4k =>
      rust_types.FrbCompressionAlgorithm.xpress4K,
    CompressionAlgorithm.xpress8k =>
      rust_types.FrbCompressionAlgorithm.xpress8K,
    CompressionAlgorithm.xpress16k =>
      rust_types.FrbCompressionAlgorithm.xpress16K,
    CompressionAlgorithm.lzx => rust_types.FrbCompressionAlgorithm.lzx,
  };
}

rust_types.FrbPlatform _toFrbPlatform(Platform platform) {
  return switch (platform) {
    Platform.steam => rust_types.FrbPlatform.steam,
    Platform.epicGames => rust_types.FrbPlatform.epicGames,
    Platform.gogGalaxy => rust_types.FrbPlatform.gogGalaxy,
    Platform.ubisoftConnect => rust_types.FrbPlatform.ubisoftConnect,
    Platform.eaApp => rust_types.FrbPlatform.eaApp,
    Platform.battleNet => rust_types.FrbPlatform.battleNet,
    Platform.xboxGamePass => rust_types.FrbPlatform.xboxGamePass,
    Platform.custom => rust_types.FrbPlatform.custom,
  };
}
