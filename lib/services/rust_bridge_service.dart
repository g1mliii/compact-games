import 'dart:async';
import 'dart:collection';

import '../models/game_info.dart';
import '../models/compression_algorithm.dart';
import '../models/compression_estimate.dart';
import '../models/compression_progress.dart';
import '../models/compression_stats.dart';
import '../src/rust/api/automation.dart' as rust_automation;
import '../src/rust/api/compression.dart' as rust_compression;
import '../src/rust/api/discovery.dart' as rust_discovery;
import '../src/rust/api/minimal.dart' as rust_minimal;
import '../src/rust/api/types.dart' as rust_types;

class RustBridgeService {
  static const RustBridgeService instance = RustBridgeService._();
  static const int _maxConcurrentEstimateRequests = 1;
  static const int _maxPendingEstimateRequests = 24;
  static const Duration _estimatePermitWaitTimeout = Duration(seconds: 8);
  static int _activeEstimateRequests = 0;
  static final Queue<_EstimatePermitWaiter> _estimatePermitQueue =
      Queue<_EstimatePermitWaiter>();
  static final Map<String, Future<CompressionEstimate>> _estimateInFlight =
      <String, Future<CompressionEstimate>>{};

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

  /// Clear discovery cache (memory + persisted file) before hard refresh.
  void clearDiscoveryCache() {
    rust_discovery.clearDiscoveryCache();
  }

  /// Evict one discovery cache entry so post-compression hydration uses fresh stats.
  void clearDiscoveryCacheEntry(String path) {
    rust_discovery.clearDiscoveryCacheEntry(path: path);
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

  /// Persist compression history entries to disk.
  void persistCompressionHistory() {
    rust_compression.persistCompressionHistory();
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

  /// Estimate potential savings before compression.
  Future<CompressionEstimate> estimateCompressionSavings({
    required String gamePath,
    required CompressionAlgorithm algorithm,
  }) async {
    final key = _estimateRequestKey(gamePath, algorithm);
    final existing = _estimateInFlight[key];
    if (existing != null) {
      return existing;
    }

    final future = _runWithEstimatePermit(() async {
      final frbAlgorithm = _toFrbAlgorithm(algorithm);
      final estimate = await rust_compression.estimateCompressionSavings(
        gamePath: gamePath,
        algorithm: frbAlgorithm,
      );
      return _mapFrbEstimate(estimate);
    });

    _estimateInFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_estimateInFlight[key], future)) {
        _estimateInFlight.remove(key);
      }
    }
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

  Stream<bool> watchAutoCompressionStatus() {
    return rust_automation.watchAutoCompressionStatus().distinct();
  }

  String _estimateRequestKey(String gamePath, CompressionAlgorithm algorithm) {
    return '${algorithm.name}|${gamePath.toLowerCase()}';
  }

  Future<T> _runWithEstimatePermit<T>(Future<T> Function() task) async {
    _EstimatePermitWaiter? waiter;
    if (_activeEstimateRequests >= _maxConcurrentEstimateRequests) {
      if (_estimatePermitQueue.length >= _maxPendingEstimateRequests) {
        throw StateError(
          'Too many pending estimate requests. Try again when scrolling stops.',
        );
      }

      waiter = _EstimatePermitWaiter();
      _estimatePermitQueue.addLast(waiter);
      try {
        await waiter.completer.future.timeout(_estimatePermitWaitTimeout);
      } on TimeoutException {
        _estimatePermitQueue.remove(waiter);
        throw TimeoutException(
          'Estimate request waited too long for a permit.',
        );
      }
    }

    _activeEstimateRequests += 1;
    try {
      return await task();
    } finally {
      _activeEstimateRequests -= 1;
      if (_activeEstimateRequests < _maxConcurrentEstimateRequests) {
        _releaseNextEstimatePermit();
      }
    }
  }

  void _releaseNextEstimatePermit() {
    if (_estimatePermitQueue.isEmpty) {
      return;
    }

    final now = DateTime.now();
    while (_estimatePermitQueue.isNotEmpty) {
      final next = _estimatePermitQueue.removeFirst();
      if (next.completer.isCompleted) {
        continue;
      }

      final waited = now.difference(next.enqueuedAt);
      if (waited > _estimatePermitWaitTimeout) {
        next.completer.completeError(
          TimeoutException('Estimate request waited too long for a permit.'),
        );
        continue;
      }

      next.completer.complete();
      return;
    }
  }
}

class _EstimatePermitWaiter {
  _EstimatePermitWaiter()
    : enqueuedAt = DateTime.now(),
      completer = Completer<void>();

  final DateTime enqueuedAt;
  final Completer<void> completer;
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

CompressionEstimate _mapFrbEstimate(rust_types.FrbCompressionEstimate frb) {
  return CompressionEstimate(
    scannedFiles: frb.scannedFiles.toInt(),
    sampledBytes: frb.sampledBytes.toInt(),
    estimatedCompressedBytes: frb.estimatedCompressedBytes.toInt(),
    estimatedSavedBytes: frb.estimatedSavedBytes.toInt(),
    estimatedSavingsRatio: frb.estimatedSavingsRatio,
    artworkCandidatePath: frb.artworkCandidatePath,
    executableCandidatePath: frb.executableCandidatePath,
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
