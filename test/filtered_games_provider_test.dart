import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/models/game_info.dart';
import 'package:pressplay/providers/games/filtered_games_provider.dart';
import 'package:pressplay/providers/games/game_list_provider.dart';
import 'package:pressplay/providers/games/game_list_state.dart';
import 'package:pressplay/models/automation_state.dart';
import 'package:pressplay/models/compression_algorithm.dart';
import 'package:pressplay/models/compression_estimate.dart';
import 'package:pressplay/models/compression_progress.dart';
import 'package:pressplay/models/watcher_event.dart';
import 'package:pressplay/services/rust_bridge_service.dart';

const int _gib = 1024 * 1024 * 1024;

final _games = <GameInfo>[
  GameInfo(
    name: 'Alpha Game',
    path: r'C:\Games\alpha',
    platform: Platform.steam,
    sizeBytes: 10 * _gib,
  ),
  GameInfo(
    name: 'Beta Quest',
    path: r'C:\Games\beta',
    platform: Platform.epicGames,
    sizeBytes: 20 * _gib,
    isCompressed: true,
    compressedSize: 15 * _gib,
  ),
  GameInfo(
    name: 'Gamma Arena',
    path: r'C:\Games\gamma',
    platform: Platform.steam,
    sizeBytes: 5 * _gib,
    isDirectStorage: true,
  ),
];

void main() {
  group('filteredGamesProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _MinimalBridgeService(games: _games),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    Future<void> waitForLoad() async {
      // Allow the async game list to settle.
      await container.read(gameListProvider.future);
    }

    test('returns all games when no filters are active', () async {
      await waitForLoad();
      final filtered = container.read(filteredGamesProvider);
      expect(filtered.length, 3);
    });

    test('search is case-insensitive and uses normalizedName', () async {
      await waitForLoad();
      container.read(gameListProvider.notifier).setSearchQuery('ALPHA');
      final filtered = container.read(filteredGamesProvider);
      expect(filtered.length, 1);
      expect(filtered.first.name, 'Alpha Game');
    });

    test('platform filter narrows results', () async {
      await waitForLoad();
      container.read(gameListProvider.notifier).setPlatformFilter({
        Platform.epicGames,
      });
      final filtered = container.read(filteredGamesProvider);
      expect(filtered.length, 1);
      expect(filtered.first.platform, Platform.epicGames);
    });

    test('compression filter compressed shows only compressed', () async {
      await waitForLoad();
      container
          .read(gameListProvider.notifier)
          .setCompressionFilter(CompressionFilter.compressed);
      final filtered = container.read(filteredGamesProvider);
      expect(filtered.length, 1);
      expect(filtered.first.isCompressed, isTrue);
    });

    test('compression filter uncompressed excludes DS games', () async {
      await waitForLoad();
      container
          .read(gameListProvider.notifier)
          .setCompressionFilter(CompressionFilter.uncompressed);
      final filtered = container.read(filteredGamesProvider);
      expect(filtered.length, 1);
      expect(filtered.first.name, 'Alpha Game');
    });

    test('sort by size descending', () async {
      await waitForLoad();
      container
          .read(gameListProvider.notifier)
          .setSortField(GameSortField.sizeBytes);
      // Default is ascending; toggle to descending
      container.read(gameListProvider.notifier).toggleSortDirection();
      final filtered = container.read(filteredGamesProvider);
      expect(filtered.first.name, 'Beta Quest');
      expect(filtered.last.name, 'Gamma Arena');
    });

    test('name sort is case-insensitive for mixed-case titles', () async {
      final mixedCaseGames = <GameInfo>[
        GameInfo(
          name: 'Wallpaper Engine',
          path: r'C:\Games\wallpaper',
          platform: Platform.steam,
          sizeBytes: 3 * _gib,
        ),
        GameInfo(
          name: 'tekken 8',
          path: r'C:\Games\tekken8',
          platform: Platform.steam,
          sizeBytes: 6 * _gib,
        ),
        GameInfo(
          name: 'Tom Clancy',
          path: r'C:\Games\tomclancy',
          platform: Platform.steam,
          sizeBytes: 9 * _gib,
        ),
        GameInfo(
          name: 'Counterstrike',
          path: r'C:\Games\counterstrike',
          platform: Platform.steam,
          sizeBytes: 5 * _gib,
        ),
        GameInfo(
          name: 'Cairn',
          path: r'C:\Games\cairn',
          platform: Platform.steam,
          sizeBytes: 4 * _gib,
        ),
        GameInfo(
          name: 'Battlefield',
          path: r'C:\Games\battlefield',
          platform: Platform.steam,
          sizeBytes: 7 * _gib,
        ),
      ];

      final local = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _MinimalBridgeService(games: mixedCaseGames),
          ),
        ],
      );
      addTearDown(local.dispose);
      await local.read(gameListProvider.future);

      final filtered = local.read(filteredGamesProvider);
      expect(
        filtered.map((g) => g.name).toList(growable: false),
        equals(<String>[
          'Battlefield',
          'Cairn',
          'Counterstrike',
          'tekken 8',
          'Tom Clancy',
          'Wallpaper Engine',
        ]),
      );
    });
  });

  group('GameInfo.normalizedName', () {
    test('is lowercase version of name', () {
      final game = GameInfo(
        name: 'My COOL Game',
        path: r'C:\test',
        platform: Platform.custom,
        sizeBytes: 0,
      );
      expect(game.normalizedName, 'my cool game');
    });

    test('is computed lazily and cached', () {
      final game = GameInfo(
        name: 'Test',
        path: r'C:\test',
        platform: Platform.custom,
        sizeBytes: 0,
      );
      expect(identical(game.normalizedName, game.normalizedName), isTrue);
    });
  });
}

class _MinimalBridgeService implements RustBridgeService {
  _MinimalBridgeService({required this.games});
  final List<GameInfo> games;

  @override
  Future<List<GameInfo>> getAllGames() async => games;
  @override
  Future<List<GameInfo>> getAllGamesQuick() async => games;
  @override
  String initApp() => 'ok';
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
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
  }) => const Stream.empty();
  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) => const Stream.empty();
  @override
  Future<CompressionEstimate> estimateCompressionSavings({
    required String gamePath,
    required CompressionAlgorithm algorithm,
  }) async => const CompressionEstimate(
    scannedFiles: 0,
    sampledBytes: 0,
    estimatedCompressedBytes: 0,
    estimatedSavedBytes: 0,
    estimatedSavingsRatio: 0,
  );
  @override
  CompressionProgress? getCompressionProgress() => null;
  @override
  Future<double> getCompressionRatio(String folderPath) async => 1.0;
  @override
  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async => null;
  @override
  bool isDirectStorage(String gamePath) => false;
  @override
  void persistCompressionHistory() {}
  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async => const [];
  @override
  Future<void> shutdownApp({
    Duration manualCompressionStopTimeout = const Duration(seconds: 2),
  }) async {}
  @override
  bool isAutoCompressionRunning() => false;
  @override
  Stream<bool> watchAutoCompressionStatus() => Stream.value(false);
  @override
  Future<void> startAutoCompression() async {}
  @override
  void stopAutoCompression() {}
  @override
  Stream<WatcherEvent> watchWatcherEvents() => const Stream.empty();
  @override
  Stream<List<AutomationJob>> watchAutomationQueue() => Stream.value(const []);
  @override
  Stream<SchedulerState> watchSchedulerState() =>
      Stream.value(SchedulerState.idle);
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
  List<AutomationJob> getAutomationQueue() => const [];
}
