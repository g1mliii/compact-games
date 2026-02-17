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

part 'support/rust_bridge_test_doubles.dart';
part 'support/widget_progress_indicator_tests.dart';

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
            const _StaticRustBridgeService(games: _sampleGames),
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
            const _StaticRustBridgeService(games: _sampleGames),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(delegate.maxCrossAxisExtent, 320);
    expect(delegate.childAspectRatio, inInclusiveRange(0.81, 0.83));
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

  _registerProgressIndicatorWidgetTests();

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
