part of '../widget_test.dart';

const CompressionEstimate _emptyEstimate = CompressionEstimate(
  scannedFiles: 0,
  sampledBytes: 0,
  estimatedCompressedBytes: 0,
  estimatedSavedBytes: 0,
  estimatedSavingsRatio: 0,
);

class _BaseRustBridgeService implements RustBridgeService {
  const _BaseRustBridgeService();

  @override
  void clearDiscoveryCacheEntry(String path) {}

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
  }) {
    return const Stream<CompressionProgress>.empty();
  }

  @override
  Future<void> decompressGame(String gamePath) async {}

  @override
  Future<CompressionEstimate> estimateCompressionSavings({
    required String gamePath,
    required CompressionAlgorithm algorithm,
  }) async {
    return _emptyEstimate;
  }

  @override
  Future<List<GameInfo>> getAllGames() async {
    return const <GameInfo>[];
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    return getAllGames();
  }

  @override
  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async {
    return null;
  }

  @override
  CompressionProgress? getCompressionProgress() {
    return null;
  }

  @override
  Future<double> getCompressionRatio(String folderPath) async {
    return 1.0;
  }

  @override
  String initApp() {
    return 'ok';
  }

  @override
  bool isAutoCompressionRunning() {
    return false;
  }

  @override
  Stream<bool> watchAutoCompressionStatus() {
    return Stream<bool>.value(false);
  }

  @override
  bool isDirectStorage(String gamePath) {
    return false;
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const <GameInfo>[];
  }

  @override
  Future<void> startAutoCompression() async {}

  @override
  void stopAutoCompression() {}

  @override
  Stream<WatcherEvent> watchWatcherEvents() {
    return const Stream<WatcherEvent>.empty();
  }

  @override
  Stream<List<AutomationJob>> watchAutomationQueue() {
    return Stream<List<AutomationJob>>.value(const <AutomationJob>[]);
  }

  @override
  Stream<SchedulerState> watchSchedulerState() {
    return Stream<SchedulerState>.value(SchedulerState.idle);
  }

  @override
  Future<void> updateAutomationConfig({
    required double cpuThresholdPercent,
    required int idleDurationSeconds,
    required int cooldownSeconds,
    required List<String> watchPaths,
    required List<String> excludedPaths,
    required CompressionAlgorithm algorithm,
  }) async {}

  @override
  SchedulerState getSchedulerState() {
    return SchedulerState.idle;
  }

  @override
  List<AutomationJob> getAutomationQueue() {
    return const <AutomationJob>[];
  }
}

class _FailingRustBridgeService extends _BaseRustBridgeService {
  const _FailingRustBridgeService();

  @override
  Future<List<GameInfo>> getAllGames() async {
    throw Exception('discovery boom');
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    throw Exception('discovery boom');
  }

  @override
  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async {
    throw Exception('discovery boom');
  }
}

class _StaticRustBridgeService extends _BaseRustBridgeService {
  const _StaticRustBridgeService({required this.games});

  final List<GameInfo> games;

  @override
  Future<List<GameInfo>> getAllGames() async {
    return games;
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    return games;
  }
}

class _RecordingRustBridgeService extends _StaticRustBridgeService {
  _RecordingRustBridgeService({
    required super.games,
    this.scanCustomFolderGames = const <GameInfo>[],
  });

  int compressCalls = 0;
  int decompressCalls = 0;
  int clearDiscoveryCacheCalls = 0;
  int clearDiscoveryCacheEntryCalls = 0;
  int getAllGamesCalls = 0;
  int scanCustomFolderCalls = 0;
  String? lastScanCustomFolderPath;
  final List<GameInfo> scanCustomFolderGames;

  @override
  void clearDiscoveryCacheEntry(String path) {
    clearDiscoveryCacheEntryCalls += 1;
  }

  @override
  void clearDiscoveryCache() {
    clearDiscoveryCacheCalls += 1;
  }

  @override
  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
  }) {
    compressCalls += 1;
    return const Stream<CompressionProgress>.empty();
  }

  @override
  Future<void> decompressGame(String gamePath) async {
    decompressCalls += 1;
  }

  @override
  Future<List<GameInfo>> getAllGames() async {
    getAllGamesCalls += 1;
    return super.getAllGames();
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    scanCustomFolderCalls += 1;
    lastScanCustomFolderPath = path;
    return scanCustomFolderGames;
  }
}

class _CancelledErrorRustBridgeService extends _BaseRustBridgeService {
  @override
  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
  }) {
    return Stream<CompressionProgress>.error(
      Exception('FrbCompressionError.cancelled()'),
    );
  }

  @override
  Future<List<GameInfo>> getAllGames() async {
    return _sampleGames;
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    return _sampleGames;
  }
}

class _DelayedDecompressRustBridgeService extends _RecordingRustBridgeService {
  _DelayedDecompressRustBridgeService({required super.games});

  final Completer<void> _decompressCompleter = Completer<void>();

  @override
  Future<void> decompressGame(String gamePath) {
    decompressCalls += 1;
    return _decompressCompleter.future;
  }

  void finishDecompression() {
    if (_decompressCompleter.isCompleted) {
      return;
    }
    _decompressCompleter.complete();
  }
}
