import 'dart:async';
import 'dart:collection';

import '../models/automation_state.dart';
import '../models/game_info.dart';
import '../models/compression_algorithm.dart';
import '../models/compression_estimate.dart';
import '../models/compression_progress.dart';
import '../models/compression_stats.dart';
import '../models/watcher_event.dart';
import '../src/rust/api/automation.dart' as rust_automation;
import '../src/rust/api/compression.dart' as rust_compression;
import '../src/rust/api/discovery.dart' as rust_discovery;
import '../src/rust/frb_generated.dart';
import '../src/rust/api/minimal.dart' as rust_minimal;
import '../src/rust/api/types.dart' as rust_types;

part 'rust_bridge_mappers.dart';

class RustBridgeService {
  static const RustBridgeService instance = RustBridgeService._();
  static const int _maxConcurrentEstimateRequests = 1;
  static const int _maxPendingEstimateRequests = 24;
  static const Duration _estimatePermitWaitTimeout = Duration(seconds: 8);
  static const Duration _manualCompressionStopTimeout = Duration(seconds: 2);
  static int _activeEstimateRequests = 0;
  static final Queue<_EstimatePermitWaiter> _estimatePermitQueue =
      Queue<_EstimatePermitWaiter>();
  static final Map<String, Future<CompressionEstimate>> _estimateInFlight =
      <String, Future<CompressionEstimate>>{};
  static Future<void>? _shutdownFuture;

  const RustBridgeService._();

  /// Initialize the Rust core (logger, thread pool).
  String initApp() {
    return rust_minimal.initApp();
  }

  Future<void> shutdownApp({
    Duration manualCompressionStopTimeout = _manualCompressionStopTimeout,
  }) {
    final existing = _shutdownFuture;
    if (existing != null) {
      return existing;
    }

    final shutdown = _performShutdown(
      manualCompressionStopTimeout: manualCompressionStopTimeout,
    );
    _shutdownFuture = shutdown;
    shutdown.whenComplete(() {
      if (identical(_shutdownFuture, shutdown)) {
        _shutdownFuture = null;
      }
    });
    return shutdown;
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

  Stream<WatcherEvent> watchWatcherEvents() {
    return rust_automation.watchWatcherEvents().map(_mapFrbWatcherEvent);
  }

  Stream<List<AutomationJob>> watchAutomationQueue() {
    return rust_automation.watchAutomationQueue().map(
      (jobs) => jobs.map(_mapFrbAutomationJob).toList(),
    );
  }

  Stream<SchedulerState> watchSchedulerState() {
    return rust_automation.watchSchedulerState().map(_mapFrbSchedulerState);
  }

  Future<void> updateAutomationConfig({
    required double cpuThresholdPercent,
    required int idleDurationSeconds,
    required int cooldownSeconds,
    required List<String> watchPaths,
    required List<String> excludedPaths,
    required CompressionAlgorithm algorithm,
  }) {
    return rust_automation.updateAutomationConfig(
      config: rust_types.FrbAutomationConfig(
        cpuThresholdPercent: cpuThresholdPercent,
        idleDurationSeconds: BigInt.from(idleDurationSeconds),
        cooldownSeconds: BigInt.from(cooldownSeconds),
        watchPaths: watchPaths,
        excludedPaths: excludedPaths,
        algorithm: _toFrbAlgorithm(algorithm),
      ),
    );
  }

  SchedulerState getSchedulerState() {
    return _mapFrbSchedulerState(rust_automation.getSchedulerState());
  }

  List<AutomationJob> getAutomationQueue() {
    return rust_automation
        .getAutomationQueue()
        .map(_mapFrbAutomationJob)
        .toList();
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

  Future<void> _performShutdown({
    required Duration manualCompressionStopTimeout,
  }) async {
    try {
      stopAutoCompression();
    } catch (_) {
      // Best effort: app is closing.
    }

    try {
      cancelCompression();
    } catch (_) {
      // Best effort: app is closing.
    }

    await _waitForManualCompressionToStop(manualCompressionStopTimeout);

    try {
      persistCompressionHistory();
    } catch (_) {
      // Best effort: app is closing.
    }

    _failPendingEstimateWaiters();
    _estimateInFlight.clear();
    _activeEstimateRequests = 0;

    try {
      RustLib.dispose();
    } catch (_) {
      // Best effort: dispose may fail if init state is partial.
    }
  }

  Future<void> _waitForManualCompressionToStop(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      CompressionProgress? progress;
      try {
        progress = getCompressionProgress();
      } catch (_) {
        return;
      }
      if (progress == null) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  void _failPendingEstimateWaiters() {
    while (_estimatePermitQueue.isNotEmpty) {
      final waiter = _estimatePermitQueue.removeFirst();
      if (waiter.completer.isCompleted) {
        continue;
      }
      waiter.completer.completeError(
        StateError('Estimate request cancelled during app shutdown.'),
      );
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
