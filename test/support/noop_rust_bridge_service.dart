import 'dart:typed_data';

import 'package:compact_games/models/automation_state.dart';
import 'package:compact_games/models/compression_algorithm.dart';
import 'package:compact_games/models/compression_estimate.dart';
import 'package:compact_games/models/compression_progress.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/models/watcher_event.dart';
import 'package:compact_games/services/rust_bridge_service.dart';
import 'package:compact_games/src/rust/api/update.dart' as rust_update;

/// Shared no-op [RustBridgeService] for tests that pump [CompactGamesApp]
/// without the Flutter-Rust bridge initialized.
class NoOpRustBridgeService implements RustBridgeService {
  const NoOpRustBridgeService();

  @override
  void clearDiscoveryCacheEntry(String path) {}
  @override
  Future<void> removeGameFromDiscovery({
    required String path,
    required Platform platform,
  }) async {}
  @override
  void clearDiscoveryCache() {}
  @override
  void cancelCompression() {}
  @override
  void persistCompressionHistory() {}

  @override
  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
  }) =>
      const Stream<CompressionProgress>.empty();

  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) =>
      const Stream<CompressionProgress>.empty();

  @override
  Future<CompressionEstimate> estimateCompressionSavings({
    required String gamePath,
    required CompressionAlgorithm algorithm,
  }) async =>
      const CompressionEstimate(
        scannedFiles: 0,
        sampledBytes: 0,
        estimatedCompressedBytes: 0,
        estimatedSavedBytes: 0,
        estimatedSavingsRatio: 0,
      );

  @override
  Future<List<GameInfo>> getAllGames() async => const <GameInfo>[];
  @override
  Future<List<GameInfo>> getAllGamesQuick() async => const <GameInfo>[];

  @override
  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async =>
      null;

  @override
  CompressionProgress? getCompressionProgress() => null;
  @override
  Future<double> getCompressionRatio(String folderPath) async => 1.0;
  @override
  String initApp() => 'ok';
  @override
  Future<void> shutdownApp({
    Duration manualCompressionStopTimeout = const Duration(seconds: 2),
  }) async {}

  @override
  bool isAutoCompressionRunning() => false;
  @override
  Stream<bool> watchAutoCompressionStatus() => Stream<bool>.value(false);
  @override
  bool isDirectStorage(String gamePath) => false;

  @override
  void reportUnsupportedGame(String gamePath) {}
  @override
  void unreportUnsupportedGame(String gamePath) {}
  @override
  Future<int> syncUnsupportedReportCollection({
    required String appVersion,
  }) async =>
      0;
  @override
  Future<int> fetchCommunityUnsupportedList() async => 0;

  @override
  Uint8List? extractExeIcon({required String exePath}) => null;

  @override
  Future<rust_update.UpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async =>
      const rust_update.UpdateCheckResult(
        updateAvailable: false,
        latestVersion: '0.1.0',
        downloadUrl: '',
        releaseNotes: '',
        checksumSha256: '',
        publishedAt: '',
      );

  @override
  Future<String> downloadUpdate({
    required String url,
    required String destPath,
    required String expectedSha256,
  }) async =>
      destPath;

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async =>
      const <GameInfo>[];

  @override
  Future<GameInfo> addApplicationFolder(String path, {String? name}) async =>
      GameInfo(
        name: name ?? 'Test Application',
        path: path,
        platform: Platform.application,
        sizeBytes: 0,
      );

  @override
  Future<void> startAutoCompression() async {}
  @override
  void stopAutoCompression() {}

  @override
  Stream<WatcherEvent> watchWatcherEvents() =>
      const Stream<WatcherEvent>.empty();
  @override
  Stream<List<AutomationJob>> watchAutomationQueue() =>
      Stream<List<AutomationJob>>.value(const <AutomationJob>[]);
  @override
  Stream<SchedulerState> watchSchedulerState() =>
      Stream<SchedulerState>.value(SchedulerState.idle);

  @override
  Future<void> updateAutomationConfig({
    required double cpuThresholdPercent,
    required int idleDurationSeconds,
    required int cooldownSeconds,
    required List<String> watchPaths,
    required List<String> excludedPaths,
    required CompressionAlgorithm algorithm,
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
  }) async {}

  @override
  SchedulerState getSchedulerState() => SchedulerState.idle;
  @override
  List<AutomationJob> getAutomationQueue() => const <AutomationJob>[];
}
