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
  }) {
    return const Stream<CompressionProgress>.empty();
  }

  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) {
    return const Stream<CompressionProgress>.empty();
  }

  @override
  Future<CompressionEstimate> estimateCompressionSavings({
    required String gamePath,
    required CompressionAlgorithm algorithm,
    String? gameName,
    int? steamAppId,
    int? knownSizeBytes,
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
  Future<void> shutdownApp({
    Duration manualCompressionStopTimeout = const Duration(seconds: 2),
  }) async {}

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
  void reportUnsupportedGame(String gamePath) {}

  @override
  void unreportUnsupportedGame(String gamePath) {}

  @override
  Future<int> syncUnsupportedReportCollection({
    required String appVersion,
  }) async {
    return 0;
  }

  @override
  Future<int> fetchCommunityUnsupportedList() async => 0;

  @override
  Uint8List? extractExeIcon({required String exePath}) => null;

  @override
  Future<String?> discoverPrimaryExe(String folder) async => null;

  @override
  Future<rust_update.UpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async {
    return const rust_update.UpdateCheckResult(
      updateAvailable: false,
      latestVersion: '0.1.0',
      downloadUrl: '',
      releaseNotes: '',
      checksumSha256: '',
      publishedAt: '',
    );
  }

  @override
  Future<String> downloadUpdate({
    required String url,
    required String destPath,
    required String expectedSha256,
  }) async {
    return destPath;
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const <GameInfo>[];
  }

  @override
  Future<GameInfo> addApplicationFolder(String path, {String? name}) async {
    return GameInfo(
      name: name ?? 'Test Application',
      path: path,
      platform: Platform.application,
      sizeBytes: 0,
    );
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
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
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
  int getAllGamesQuickCalls = 0;
  int scanCustomFolderCalls = 0;
  int startAutoCompressionCalls = 0;
  int updateAutomationConfigCalls = 0;
  String? lastScanCustomFolderPath;
  bool? lastAllowDirectStorageOverride;
  bool? lastAutomationAllowDirectStorageOverride;
  int reportUnsupportedGameCalls = 0;
  String? lastReportedUnsupportedGamePath;
  int unreportUnsupportedGameCalls = 0;
  String? lastUnreportedUnsupportedGamePath;
  int syncUnsupportedReportCollectionCalls = 0;
  String? lastSyncUnsupportedReportAppVersion;
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
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
  }) {
    compressCalls += 1;
    lastAllowDirectStorageOverride = allowDirectStorageOverride;
    return const Stream<CompressionProgress>.empty();
  }

  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) {
    decompressCalls += 1;
    return const Stream<CompressionProgress>.empty();
  }

  @override
  Future<List<GameInfo>> getAllGames() async {
    getAllGamesCalls += 1;
    return super.getAllGames();
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    getAllGamesQuickCalls += 1;
    return super.getAllGamesQuick();
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    scanCustomFolderCalls += 1;
    lastScanCustomFolderPath = path;
    return scanCustomFolderGames;
  }

  @override
  void reportUnsupportedGame(String gamePath) {
    reportUnsupportedGameCalls += 1;
    lastReportedUnsupportedGamePath = gamePath;
  }

  @override
  void unreportUnsupportedGame(String gamePath) {
    unreportUnsupportedGameCalls += 1;
    lastUnreportedUnsupportedGamePath = gamePath;
  }

  @override
  Future<int> syncUnsupportedReportCollection({
    required String appVersion,
  }) async {
    syncUnsupportedReportCollectionCalls += 1;
    lastSyncUnsupportedReportAppVersion = appVersion;
    return 0;
  }

  @override
  Future<void> startAutoCompression() async {
    startAutoCompressionCalls += 1;
  }

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
  }) async {
    updateAutomationConfigCalls += 1;
    lastAutomationAllowDirectStorageOverride = allowDirectStorageOverride;
  }
}

class _QuickThenFullRustBridgeService extends _BaseRustBridgeService {
  _QuickThenFullRustBridgeService({
    required this.quickGames,
    required this.fullGames,
  });

  final List<GameInfo> quickGames;
  final List<GameInfo> fullGames;
  final Completer<void> _fullLoadCompleter = Completer<void>();
  int clearDiscoveryCacheCalls = 0;
  int getAllGamesCalls = 0;
  int getAllGamesQuickCalls = 0;

  @override
  void clearDiscoveryCache() {
    clearDiscoveryCacheCalls += 1;
  }

  @override
  Future<List<GameInfo>> getAllGames() async {
    getAllGamesCalls += 1;
    await _fullLoadCompleter.future;
    return fullGames;
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    getAllGamesQuickCalls += 1;
    return quickGames;
  }

  void releaseFullLoad() {
    if (_fullLoadCompleter.isCompleted) {
      return;
    }
    _fullLoadCompleter.complete();
  }
}

class _QueuedSyncRustBridgeService extends _BaseRustBridgeService {
  final List<Completer<int>> _syncCompleters = <Completer<int>>[];

  int syncUnsupportedReportCollectionCalls = 0;
  String? lastSyncUnsupportedReportAppVersion;

  @override
  Future<int> syncUnsupportedReportCollection({required String appVersion}) {
    syncUnsupportedReportCollectionCalls += 1;
    lastSyncUnsupportedReportAppVersion = appVersion;
    final completer = Completer<int>();
    _syncCompleters.add(completer);
    return completer.future;
  }

  int get pendingSyncCount =>
      _syncCompleters.where((completer) => !completer.isCompleted).length;

  void completeNextSync([int result = 0]) {
    final nextIndex = _syncCompleters.indexWhere(
      (completer) => !completer.isCompleted,
    );
    if (nextIndex < 0) {
      throw StateError('No pending unsupported-report sync to complete.');
    }
    _syncCompleters[nextIndex].complete(result);
  }
}

class _WatcherRecordingRustBridgeService extends _RecordingRustBridgeService {
  _WatcherRecordingRustBridgeService({required super.games});

  final StreamController<WatcherEvent> _watcherController =
      StreamController<WatcherEvent>.broadcast();

  @override
  Stream<WatcherEvent> watchWatcherEvents() {
    return _watcherController.stream;
  }

  void emitWatcherEvent(WatcherEvent event) {
    if (_watcherController.isClosed) {
      return;
    }
    _watcherController.add(event);
  }

  void disposeWatcher() {
    if (_watcherController.isClosed) {
      return;
    }
    unawaited(_watcherController.close());
  }
}

class _CancelledErrorRustBridgeService extends _BaseRustBridgeService {
  @override
  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
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

class _DelayedActivityRustBridgeService extends _StaticRustBridgeService {
  _DelayedActivityRustBridgeService({required super.games, this.hydratedGame})
    : _compressionController = StreamController<CompressionProgress>(),
      _decompressionController = StreamController<CompressionProgress>(),
      _automationQueueController =
          StreamController<List<AutomationJob>>.broadcast();

  final StreamController<CompressionProgress> _compressionController;
  final StreamController<CompressionProgress> _decompressionController;
  final StreamController<List<AutomationJob>> _automationQueueController;
  GameInfo? hydratedGame;
  int compressCalls = 0;
  int decompressCalls = 0;
  int persistCompressionHistoryCalls = 0;
  bool? lastAllowDirectStorageOverride;

  @override
  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
  }) {
    compressCalls += 1;
    lastAllowDirectStorageOverride = allowDirectStorageOverride;
    return _compressionController.stream;
  }

  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) {
    decompressCalls += 1;
    return _decompressionController.stream;
  }

  @override
  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async {
    return hydratedGame;
  }

  @override
  Stream<List<AutomationJob>> watchAutomationQueue() {
    return _automationQueueController.stream;
  }

  @override
  void persistCompressionHistory() {
    persistCompressionHistoryCalls += 1;
  }

  void emitCompressionProgress({
    required String gameName,
    required int filesProcessed,
    required int filesTotal,
    required int bytesOriginal,
    required int bytesCompressed,
    Duration? estimatedTimeRemaining,
  }) {
    if (_compressionController.isClosed) {
      return;
    }
    _compressionController.add(
      CompressionProgress(
        gameName: gameName,
        filesProcessed: filesProcessed,
        filesTotal: filesTotal,
        bytesOriginal: bytesOriginal,
        bytesCompressed: bytesCompressed,
        bytesSaved: bytesOriginal - bytesCompressed,
        estimatedTimeRemaining: estimatedTimeRemaining,
        isComplete: filesTotal > 0 && filesProcessed >= filesTotal,
      ),
    );
  }

  void finishCompression() {
    if (_compressionController.isClosed) {
      return;
    }
    unawaited(_compressionController.close());
  }

  void finishDecompression() {
    if (_decompressionController.isClosed) {
      return;
    }
    unawaited(_decompressionController.close());
  }

  void emitAutomationQueue(List<AutomationJob> jobs) {
    if (_automationQueueController.isClosed) {
      return;
    }
    _automationQueueController.add(jobs);
  }

  void disposeStreams() {
    finishCompression();
    finishDecompression();
    if (_automationQueueController.isClosed) {
      return;
    }
    unawaited(_automationQueueController.close());
  }
}

class _DelayedDecompressRustBridgeService extends _RecordingRustBridgeService {
  _DelayedDecompressRustBridgeService({required super.games});

  final StreamController<CompressionProgress> _decompressController =
      StreamController<CompressionProgress>();

  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) {
    decompressCalls += 1;
    return _decompressController.stream;
  }

  void finishDecompression() {
    if (_decompressController.isClosed) {
      return;
    }
    _decompressController.close();
  }
}

class _FakePlatformShellService extends PlatformShellService {
  _FakePlatformShellService({this.folderPath, this.executablePath});

  final String? folderPath;
  final String? executablePath;
  int pickFolderCalls = 0;
  int pickExecutableCalls = 0;

  @override
  Future<String?> pickGameFolder() async {
    pickFolderCalls += 1;
    return folderPath;
  }

  @override
  Future<String?> pickGameExecutable() async {
    pickExecutableCalls += 1;
    return executablePath;
  }
}

class _FixedSettingsPersistence implements SettingsPersistence {
  _FixedSettingsPersistence(this._current);

  AppSettings _current;

  @override
  Future<AppSettings> load() async {
    return _current;
  }

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
  }
}
