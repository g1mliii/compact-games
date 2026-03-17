part of '../phase6_ui_test.dart';

class _InMemorySettingsPersistence implements SettingsPersistence {
  AppSettings _current = const AppSettings();

  @override
  Future<AppSettings> load() async {
    return _current;
  }

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
  }
}

class _TestRustBridgeService implements RustBridgeService {
  _TestRustBridgeService({
    required this.games,
    this.autoCompressionRunning = false,
  });

  final List<GameInfo> games;
  final bool autoCompressionRunning;
  int compressCalls = 0;
  int decompressCalls = 0;
  bool? lastAllowDirectStorageOverride;
  int reportUnsupportedGameCalls = 0;
  String? lastReportedUnsupportedGamePath;
  int unreportUnsupportedGameCalls = 0;
  String? lastUnreportedUnsupportedGamePath;
  int removeGameFromDiscoveryCalls = 0;
  String? lastRemovedGamePath;
  int syncUnsupportedReportCollectionCalls = 0;
  String? lastSyncUnsupportedReportAppVersion;

  @override
  void cancelCompression() {}

  @override
  void clearDiscoveryCache() {}

  @override
  void clearDiscoveryCacheEntry(String path) {}
  @override
  Future<void> removeGameFromDiscovery({
    required String path,
    required Platform platform,
  }) async {
    removeGameFromDiscoveryCalls += 1;
    lastRemovedGamePath = path;
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
  Future<CompressionEstimate> estimateCompressionSavings({
    required String gamePath,
    required CompressionAlgorithm algorithm,
  }) async {
    return const CompressionEstimate(
      scannedFiles: 0,
      sampledBytes: 0,
      estimatedCompressedBytes: 0,
      estimatedSavedBytes: 0,
      estimatedSavingsRatio: 0,
    );
  }

  @override
  Future<List<GameInfo>> getAllGames() async {
    return games;
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    return games;
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
  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async {
    return null;
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
    return autoCompressionRunning;
  }

  @override
  Stream<bool> watchAutoCompressionStatus() {
    return Stream<bool>.value(autoCompressionRunning);
  }

  @override
  bool isDirectStorage(String gamePath) {
    return false;
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
  void persistCompressionHistory() {}

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const [];
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

  @override
  Future<int> fetchCommunityUnsupportedList() async => 0;
}

class _DelayedActivityRustBridgeService extends _TestRustBridgeService {
  _DelayedActivityRustBridgeService({required super.games})
    : _compressionController = StreamController<CompressionProgress>(),
      _decompressionController = StreamController<CompressionProgress>();

  final StreamController<CompressionProgress> _compressionController;
  final StreamController<CompressionProgress> _decompressionController;

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

  void disposeStreams() {
    finishCompression();
    finishDecompression();
  }
}

class _DeferredRemoveRustBridgeService extends _TestRustBridgeService {
  _DeferredRemoveRustBridgeService({required super.games});

  final Completer<void> _removeCompleter = Completer<void>();

  @override
  Future<void> removeGameFromDiscovery({
    required String path,
    required Platform platform,
  }) async {
    removeGameFromDiscoveryCalls += 1;
    lastRemovedGamePath = path;
    return _removeCompleter.future;
  }

  void completeRemoval() {
    if (_removeCompleter.isCompleted) {
      return;
    }
    _removeCompleter.complete();
  }
}

class _RecordingCoverArtService extends CoverArtService {
  _RecordingCoverArtService({required this.placeholders});

  final Set<String> placeholders;
  int clearLookupCachesCalls = 0;
  List<String> lastPlaceholderCandidatesInput = const <String>[];
  List<String> invalidatedPaths = const <String>[];

  @override
  void clearLookupCaches() {
    clearLookupCachesCalls += 1;
  }

  @override
  void invalidateCoverForGames(Iterable<String> gamePaths) {
    invalidatedPaths = gamePaths.toList(growable: false);
  }

  @override
  List<String> placeholderRefreshCandidates(Iterable<String> gamePaths) {
    final snapshot = gamePaths.toList(growable: false);
    lastPlaceholderCandidatesInput = snapshot;
    return snapshot
        .where((path) => placeholders.contains(path))
        .toList(growable: false);
  }

  @override
  Future<CoverArtResult> resolveCover(
    GameInfo game, {
    String? steamGridDbApiKey,
  }) async {
    return const CoverArtResult.none();
  }
}

class _VersionedSameUriCoverArtService extends CoverArtService {
  _VersionedSameUriCoverArtService({required this.coverUri});

  final String coverUri;
  final Map<String, int> _revisions = <String, int>{};

  @override
  Future<CoverArtResult> resolveCover(
    GameInfo game, {
    String? steamGridDbApiKey,
  }) async {
    return CoverArtResult(
      uri: coverUri,
      source: CoverArtSource.cache,
      revision: _revisions[game.path] ?? 1,
    );
  }

  void rewriteCover(String gamePath) {
    _revisions[gamePath] = (_revisions[gamePath] ?? 1) + 1;
  }
}
