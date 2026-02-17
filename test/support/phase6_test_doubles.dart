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
  _TestRustBridgeService({required this.games});

  final List<GameInfo> games;
  int compressCalls = 0;
  int decompressCalls = 0;

  @override
  void cancelCompression() {}

  @override
  void clearDiscoveryCache() {}

  @override
  void clearDiscoveryCacheEntry(String path) {}

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
  void persistCompressionHistory() {}

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const [];
  }

  @override
  Future<void> startAutoCompression() async {}

  @override
  void stopAutoCompression() {}
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
