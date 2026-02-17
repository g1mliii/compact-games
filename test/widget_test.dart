import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/app.dart';
import 'package:pressplay/core/widgets/cinematic_background.dart';
import 'package:pressplay/core/widgets/film_grain_overlay.dart';
import 'package:pressplay/core/widgets/status_badge.dart';
import 'package:pressplay/features/games/presentation/component_test_screen.dart';
import 'package:pressplay/features/games/presentation/home_screen.dart';
import 'package:pressplay/features/games/presentation/widgets/compression_progress_indicator.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card.dart';
import 'package:pressplay/features/games/presentation/widgets/home_game_grid.dart';
import 'package:pressplay/models/compression_algorithm.dart';
import 'package:pressplay/models/compression_estimate.dart';
import 'package:pressplay/models/compression_progress.dart';
import 'package:pressplay/models/game_info.dart';
import 'package:pressplay/providers/compression/compression_provider.dart';
import 'package:pressplay/providers/compression/compression_state.dart';
import 'package:pressplay/providers/games/game_list_provider.dart';
import 'package:pressplay/services/rust_bridge_service.dart';

const int _oneGiB = 1024 * 1024 * 1024;
const List<GameInfo> _sampleGames = <GameInfo>[
  GameInfo(
    name: 'Pixel Raider',
    path: r'C:\Games\pixel_raider',
    platform: Platform.steam,
    sizeBytes: 96 * _oneGiB,
  ),
  GameInfo(
    name: 'Dustline',
    path: r'C:\Games\dustline',
    platform: Platform.epicGames,
    sizeBytes: 48 * _oneGiB,
  ),
];

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PressPlayApp());
    expect(find.text('PressPlay'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Section 2.2 components render in test screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ComponentTestScreen())),
    );

    expect(find.text('Component Test Screen'), findsOneWidget);
    expect(find.byType(GameCard), findsNWidgets(3));
    expect(find.byType(CompressionProgressIndicator), findsOneWidget);
    expect(find.byType(StatusBadge), findsAtLeastNWidgets(3));
  });

  testWidgets('Discovery failure renders error view instead of empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            const _FailingRustBridgeService(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Failed to load games'), findsOneWidget);
    expect(find.textContaining('discovery boom'), findsOneWidget);
    expect(find.text('No games found'), findsNothing);
  });

  testWidgets('Home screen renders at constrained width without overflow', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            const _StaticRustBridgeService(_sampleGames),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(GameCard), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home grid avoids over-packed columns around 1024px width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            const _StaticRustBridgeService(_sampleGames),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    expect(delegate.childAspectRatio, inInclusiveRange(0.53, 0.54));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Refresh button clears cache and requests full discovery', (
    WidgetTester tester,
  ) async {
    final bridge = _RecordingRustBridgeService(games: _sampleGames);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(bridge.clearDiscoveryCacheCalls, 0);
    expect(bridge.getAllGamesCalls, 0);

    await tester.tap(find.byTooltip('Refresh games'));
    await tester.pumpAndSettle();

    expect(bridge.clearDiscoveryCacheCalls, 1);
    expect(bridge.getAllGamesCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'CinematicBackground isolates static layers behind repaint boundary',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CinematicBackground(child: SizedBox.expand())),
        ),
      );

      final staticLayers = find.byKey(CinematicBackground.staticLayersKey);
      expect(staticLayers, findsOneWidget);
      expect(
        find.descendant(
          of: staticLayers,
          matching: find.byType(FilmGrainOverlay),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('FilmGrainOverlay uses perf-oriented paint hints', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FilmGrainOverlay())),
    );

    final customPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(FilmGrainOverlay),
        matching: find.byType(CustomPaint),
      ),
    );

    expect(customPaint.isComplex, isTrue);
    expect(customPaint.willChange, isFalse);
    expect(
      find.descendant(
        of: find.byType(FilmGrainOverlay),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Card tap requires confirmation before compression starts', (
    WidgetTester tester,
  ) async {
    final bridge = _RecordingRustBridgeService(games: _sampleGames);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Compression'), findsOneWidget);
    expect(bridge.compressCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bridge.compressCalls, 0);

    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compress'));
    await tester.pump();

    expect(bridge.compressCalls, 1);
  });

  testWidgets('Tapping compressed card starts decompression immediately', (
    WidgetTester tester,
  ) async {
    final compressedGames = <GameInfo>[
      const GameInfo(
        name: 'Compressed Quest',
        path: r'C:\Games\compressed_quest',
        platform: Platform.steam,
        sizeBytes: 58 * _oneGiB,
        compressedSize: 53 * _oneGiB,
        isCompressed: true,
      ),
    ];
    final bridge = _RecordingRustBridgeService(games: compressedGames);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Compression'), findsNothing);
    expect(bridge.decompressCalls, 1);
  });

  testWidgets('Compressed DirectStorage card still allows decompression', (
    WidgetTester tester,
  ) async {
    final compressedDirectStorageGames = <GameInfo>[
      const GameInfo(
        name: 'DirectStorage Runner',
        path: r'C:\Games\ds_runner',
        platform: Platform.steam,
        sizeBytes: 58 * _oneGiB,
        compressedSize: 53 * _oneGiB,
        isCompressed: true,
        isDirectStorage: true,
      ),
    ];
    final bridge = _RecordingRustBridgeService(
      games: compressedDirectStorageGames,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Compression'), findsNothing);
    expect(bridge.decompressCalls, 1);
  });

  testWidgets('Home banner shows Decompressing while decompression is active', (
    WidgetTester tester,
  ) async {
    final compressedGames = <GameInfo>[
      const GameInfo(
        name: 'Decompress Banner Test',
        path: r'C:\Games\decompress_banner_test',
        platform: Platform.steam,
        sizeBytes: 58 * _oneGiB,
        compressedSize: 53 * _oneGiB,
        isCompressed: true,
      ),
    ];
    final bridge = _DelayedDecompressRustBridgeService(games: compressedGames);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameCard).first);
    await tester.pump();

    expect(find.text('Decompressing'), findsOneWidget);
    expect(find.text('Decompress Banner Test'), findsWidgets);
    expect(bridge.decompressCalls, 1);

    bridge.finishDecompression();
    await tester.pumpAndSettle();
  });

  testWidgets('Compression progress display clamps processed above total', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompressionProgressIndicator(
            gameName: 'Clamp Test',
            filesProcessed: 1000,
            filesTotal: 100,
            bytesSaved: 0,
          ),
        ),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('1000 / 1000 files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compression progress shows preparing state before totals', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompressionProgressIndicator(
            gameName: 'Prep Test',
            filesProcessed: 0,
            filesTotal: 0,
            bytesSaved: 0,
          ),
        ),
      ),
    );

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.text('Scanning files...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rapid card taps do not stack confirmation dialogs', (
    WidgetTester tester,
  ) async {
    final bridge = _RecordingRustBridgeService(games: _sampleGames);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameCard).first);
    await tester.tap(find.byType(GameCard).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Compression'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  test(
    'Cancellation stream error archives active job instead of leaving running',
    () async {
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _CancelledErrorRustBridgeService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(compressionProvider.notifier)
          .startCompression(
            gamePath: r'C:\Games\cancel_case',
            gameName: 'Cancel Case',
          );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = container.read(compressionProvider);
      expect(state.activeJob, isNull);
      expect(state.history, isNotEmpty);
      expect(state.history.first.status, CompressionJobStatus.cancelled);
    },
  );
}

class _FailingRustBridgeService implements RustBridgeService {
  const _FailingRustBridgeService();

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
  bool isDirectStorage(String gamePath) {
    return false;
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const [];
  }

  @override
  Future<void> startAutoCompression() async {}

  @override
  void stopAutoCompression() {}
}

class _StaticRustBridgeService implements RustBridgeService {
  const _StaticRustBridgeService(this.games);

  final List<GameInfo> games;

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
  bool isDirectStorage(String gamePath) {
    return false;
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const [];
  }

  @override
  Future<void> startAutoCompression() async {}

  @override
  void stopAutoCompression() {}
}

class _RecordingRustBridgeService implements RustBridgeService {
  _RecordingRustBridgeService({required this.games});

  final List<GameInfo> games;
  int compressCalls = 0;
  int decompressCalls = 0;
  int clearDiscoveryCacheCalls = 0;
  int clearDiscoveryCacheEntryCalls = 0;
  int getAllGamesCalls = 0;

  @override
  void clearDiscoveryCacheEntry(String path) {
    clearDiscoveryCacheEntryCalls += 1;
  }

  @override
  void clearDiscoveryCache() {
    clearDiscoveryCacheCalls += 1;
  }

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
    getAllGamesCalls += 1;
    return games;
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    return games;
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
  bool isDirectStorage(String gamePath) {
    return false;
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const [];
  }

  @override
  Future<void> startAutoCompression() async {}

  @override
  void stopAutoCompression() {}
}

class _CancelledErrorRustBridgeService implements RustBridgeService {
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
    return Stream<CompressionProgress>.error(
      Exception('FrbCompressionError.cancelled()'),
    );
  }

  @override
  Future<void> decompressGame(String gamePath) async {}

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
    return _sampleGames;
  }

  @override
  Future<List<GameInfo>> getAllGamesQuick() async {
    return _sampleGames;
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
  bool isDirectStorage(String gamePath) {
    return false;
  }

  @override
  Future<List<GameInfo>> scanCustomFolder(String path) async {
    return const [];
  }

  @override
  Future<void> startAutoCompression() async {}

  @override
  void stopAutoCompression() {}
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
