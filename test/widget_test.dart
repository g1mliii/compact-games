import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pressplay/app.dart';
import 'package:pressplay/core/widgets/cinematic_background.dart';
import 'package:pressplay/core/widgets/film_grain_overlay.dart';
import 'package:pressplay/core/widgets/status_badge.dart';
import 'package:pressplay/features/games/presentation/component_test_screen.dart';
import 'package:pressplay/features/games/presentation/home_screen.dart';
import 'package:pressplay/features/games/presentation/widgets/compression_activity_overlay.dart';
import 'package:pressplay/features/games/presentation/widgets/compression_progress_indicator.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card.dart';
import 'package:pressplay/features/games/presentation/widgets/home_game_grid.dart';
import 'package:pressplay/features/games/presentation/widgets/home_compression_banner.dart';
import 'package:pressplay/models/app_settings.dart';
import 'package:pressplay/models/automation_state.dart';
import 'package:pressplay/models/compression_algorithm.dart';
import 'package:pressplay/models/compression_estimate.dart';
import 'package:pressplay/models/compression_progress.dart';
import 'package:pressplay/models/game_info.dart';
import 'package:pressplay/models/watcher_event.dart';
import 'package:pressplay/providers/compression/compression_progress_provider.dart';
import 'package:pressplay/providers/compression/compression_provider.dart';
import 'package:pressplay/providers/compression/compression_state.dart';
import 'package:pressplay/providers/games/game_list_provider.dart';
import 'package:pressplay/providers/settings/settings_persistence.dart';
import 'package:pressplay/providers/settings/settings_provider.dart';
import 'package:pressplay/providers/system/route_state_provider.dart';
import 'package:pressplay/providers/system/platform_shell_provider.dart';
import 'package:pressplay/services/rust_bridge_service.dart';
import 'package:pressplay/services/platform_shell_service.dart';
import 'package:pressplay/services/unsupported_report_sync_service.dart';

part 'support/rust_bridge_test_doubles.dart';
part 'support/widget_progress_indicator_tests.dart';

const int _oneGiB = 1024 * 1024 * 1024;
final List<GameInfo> _sampleGames = <GameInfo>[
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
    final bridge = _StaticRustBridgeService(games: _sampleGames);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const PressPlayApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compact Games'), findsOneWidget);
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

    expect(find.text("Couldn't load your library"), findsOneWidget);
    expect(find.textContaining('discovery boom'), findsOneWidget);
    expect(find.text('No games in view'), findsNothing);
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
            _StaticRustBridgeService(games: _sampleGames),
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

  testWidgets('Home screen only shows one ready-to-reclaim summary message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _StaticRustBridgeService(games: _sampleGames),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('2 games are ready to reclaim space.'), findsOneWidget);
  });

  testWidgets('Home screen keeps only the overview review-eligible action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _StaticRustBridgeService(games: _sampleGames),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Review eligible games'), findsOneWidget);
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
            _StaticRustBridgeService(games: _sampleGames),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(delegate.maxCrossAxisExtent, 288);
    expect(delegate.childAspectRatio, inInclusiveRange(0.55, 0.57));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home grid keeps card width stable within a small resize bucket',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rustBridgeServiceProvider.overrideWithValue(
              _StaticRustBridgeService(games: _sampleGames),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
        ),
      );

      await tester.pumpAndSettle();

      final initialWidth = tester.getSize(find.byType(GameCard).first).width;

      await tester.binding.setSurfaceSize(const Size(1212, 900));
      await tester.pumpAndSettle();

      final withinBucketWidth = tester
          .getSize(find.byType(GameCard).first)
          .width;
      expect(withinBucketWidth, closeTo(initialWidth, 0.01));

      await tester.binding.setSurfaceSize(const Size(1248, 900));
      await tester.pumpAndSettle();

      final nextBucketWidth = tester.getSize(find.byType(GameCard).first).width;
      expect(nextBucketWidth, greaterThan(withinBucketWidth));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home grid reuses the same grid subtree within a resize bucket', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _StaticRustBridgeService(games: _sampleGames),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();

    final initialGrid = tester.widget<GridView>(find.byType(GridView).first);

    await tester.binding.setSurfaceSize(const Size(1212, 900));
    await tester.pumpAndSettle();

    final withinBucketGrid = tester.widget<GridView>(
      find.byType(GridView).first,
    );
    expect(identical(withinBucketGrid, initialGrid), isTrue);

    await tester.binding.setSurfaceSize(const Size(1248, 900));
    await tester.pumpAndSettle();

    final nextBucketGrid = tester.widget<GridView>(find.byType(GridView).first);
    expect(identical(nextBucketGrid, withinBucketGrid), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home grid reuses the same grid subtree for metadata-only game updates',
    (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _StaticRustBridgeService(games: _sampleGames),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
        ),
      );

      await tester.pumpAndSettle();

      final initialGrid = tester.widget<GridView>(find.byType(GridView).first);

      container
          .read(gameListProvider.notifier)
          .updateGame(
            _sampleGames.first.copyWith(
              isCompressed: true,
              compressedSize: () => 72 * _oneGiB,
              lastCompressedAt: () => DateTime(2026, 3, 10, 11, 30),
            ),
          );
      await tester.pump();

      final updatedGrid = tester.widget<GridView>(find.byType(GridView).first);
      expect(identical(updatedGrid, initialGrid), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Startup quick discovery promotes itself to a full scan', (
    WidgetTester tester,
  ) async {
    final fullGame = GameInfo(
      name: 'Night Circuit',
      path: r'C:\Games\night_circuit',
      platform: Platform.gogGalaxy,
      sizeBytes: 36 * _oneGiB,
    );
    final bridge = _QuickThenFullRustBridgeService(
      quickGames: <GameInfo>[_sampleGames.first],
      fullGames: <GameInfo>[_sampleGames.first, fullGame],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pump();
    expect(find.text('Pixel Raider'), findsOneWidget);
    expect(find.text('Night Circuit'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(bridge.getAllGamesQuickCalls, 1);
    expect(bridge.getAllGamesCalls, 1);
    expect(bridge.clearDiscoveryCacheCalls, 0);

    bridge.releaseFullLoad();
    await tester.pumpAndSettle();

    expect(find.text('Pixel Raider'), findsOneWidget);
    expect(find.text('Night Circuit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Refresh button clears cache and requests another full discovery',
    (WidgetTester tester) async {
      final bridge = _RecordingRustBridgeService(games: _sampleGames);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pumpAndSettle();
      expect(bridge.clearDiscoveryCacheCalls, 0);
      expect(bridge.getAllGamesCalls, 1);

      await tester.tap(find.byTooltip('Refresh games'));
      await tester.pumpAndSettle();

      expect(bridge.clearDiscoveryCacheCalls, 1);
      expect(bridge.getAllGamesCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Add game imports manual EXE target into the grid', (
    WidgetTester tester,
  ) async {
    final manualGame = GameInfo(
      name: 'Manual Entry',
      path: r'C:\Manual\Entry',
      platform: Platform.custom,
      sizeBytes: 12 * _oneGiB,
    );
    final bridge = _RecordingRustBridgeService(
      games: _sampleGames,
      scanCustomFolderGames: <GameInfo>[manualGame],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Manual Entry'), findsNothing);

    await tester.tap(find.byTooltip('Add game'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('addGamePathField')),
      r'C:\Manual\Entry\game.exe',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('confirmAddGameButton')),
    );
    await tester.pumpAndSettle();

    expect(bridge.scanCustomFolderCalls, 1);
    expect(bridge.lastScanCustomFolderPath, r'C:\Manual\Entry');
    expect(find.text('Manual Entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add game supports browse-folder selection in dialog', (
    WidgetTester tester,
  ) async {
    final manualGame = GameInfo(
      name: 'Browsed Entry',
      path: r'C:\Manual\Entry',
      platform: Platform.custom,
      sizeBytes: 14 * _oneGiB,
    );
    final bridge = _RecordingRustBridgeService(
      games: _sampleGames,
      scanCustomFolderGames: <GameInfo>[manualGame],
    );
    final shell = _FakePlatformShellService(
      folderPath: r'C:\Manual\Entry',
      executablePath: r'C:\Manual\Entry\game.exe',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(bridge),
          platformShellServiceProvider.overrideWithValue(shell),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add game'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('browseGameFolderButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('confirmAddGameButton')),
    );
    await tester.pumpAndSettle();

    expect(shell.pickFolderCalls, 1);
    expect(bridge.scanCustomFolderCalls, 1);
    expect(bridge.lastScanCustomFolderPath, r'C:\Manual\Entry');
    expect(find.text('Browsed Entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add game browse buttons stay below the path field', (
    WidgetTester tester,
  ) async {
    final bridge = _RecordingRustBridgeService(games: _sampleGames);
    final shell = _FakePlatformShellService(
      folderPath: r'C:\Manual\Entry',
      executablePath: r'C:\Manual\Entry\game.exe',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(bridge),
          platformShellServiceProvider.overrideWithValue(shell),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add game'));
    await tester.pumpAndSettle();

    final fieldRect = tester.getRect(
      find.byKey(const ValueKey<String>('addGamePathField')),
    );
    final folderRect = tester.getRect(
      find.byKey(const ValueKey<String>('browseGameFolderButton')),
    );
    final exeRect = tester.getRect(
      find.byKey(const ValueKey<String>('browseGameExeButton')),
    );

    expect(folderRect.top, greaterThan(fieldRect.bottom));
    expect((folderRect.top - exeRect.top).abs(), lessThanOrEqualTo(1));
    expect(folderRect.left, lessThan(exeRect.left));
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

  testWidgets('Card tap opens menu and compresses only after action select', (
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

    expect(find.text('Confirm Compression'), findsNothing);
    expect(find.text('Compress Now'), findsOneWidget);
    expect(bridge.compressCalls, 0);

    await tester.tap(find.text('Compress Now'));
    await tester.pumpAndSettle();

    expect(bridge.compressCalls, 1);
  });

  testWidgets('Tapping compressed card opens menu before decompression', (
    WidgetTester tester,
  ) async {
    final compressedGames = <GameInfo>[
      GameInfo(
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
    expect(find.text('Decompress'), findsOneWidget);
    expect(bridge.decompressCalls, 0);

    await tester.tap(find.text('Decompress'));
    await tester.pumpAndSettle();
    expect(bridge.decompressCalls, 1);
  });

  testWidgets('Compressed DirectStorage card menu still allows decompression', (
    WidgetTester tester,
  ) async {
    final compressedDirectStorageGames = <GameInfo>[
      GameInfo(
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
    expect(find.text('Decompress'), findsOneWidget);
    expect(bridge.decompressCalls, 0);

    await tester.tap(find.text('Decompress'));
    await tester.pumpAndSettle();
    expect(bridge.decompressCalls, 1);
  });

  testWidgets('DirectStorage override enables context-menu compression', (
    WidgetTester tester,
  ) async {
    final directStorageGames = <GameInfo>[
      GameInfo(
        name: 'DirectStorage Override Candidate',
        path: r'C:\Games\ds_override_candidate',
        platform: Platform.steam,
        sizeBytes: 58 * _oneGiB,
        isDirectStorage: true,
      ),
    ];
    final bridge = _RecordingRustBridgeService(games: directStorageGames);
    final persistence = _FixedSettingsPersistence(
      const AppSettings(directStorageOverrideEnabled: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(bridge),
          settingsPersistenceProvider.overrideWithValue(persistence),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    expect(find.text('Compress Now'), findsOneWidget);
    expect(bridge.compressCalls, 0);

    await tester.tap(find.text('Compress Now'));
    await tester.pumpAndSettle();

    expect(bridge.compressCalls, 1);
    expect(bridge.lastAllowDirectStorageOverride, isTrue);
  });

  testWidgets(
    'Unsupported games can compress from card menu without DirectStorage override',
    (WidgetTester tester) async {
      final unsupportedGames = <GameInfo>[
        GameInfo(
          name: 'Unsupported Compression Candidate',
          path: r'C:\Games\unsupported_compression_candidate',
          platform: Platform.steam,
          sizeBytes: 58 * _oneGiB,
          isUnsupported: true,
        ),
      ];
      final bridge = _RecordingRustBridgeService(games: unsupportedGames);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
          child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(GameCard).first);
      await tester.pumpAndSettle();

      expect(find.text('Compress Now'), findsOneWidget);

      await tester.tap(find.text('Compress Now'));
      await tester.pumpAndSettle();

      expect(bridge.compressCalls, 1);
      expect(bridge.lastAllowDirectStorageOverride, isFalse);
    },
  );

  testWidgets('Card menu can mark and unmark unsupported state', (
    WidgetTester tester,
  ) async {
    final game = GameInfo(
      name: 'Unsupported Candidate',
      path: r'C:\Games\unsupported_candidate',
      platform: Platform.steam,
      sizeBytes: 42 * _oneGiB,
    );
    final bridge = _RecordingRustBridgeService(games: <GameInfo>[game]);
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      container.read(gameListProvider).valueOrNull?.games.first.isUnsupported,
      isFalse,
    );

    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    expect(find.text('Mark as Unsupported'), findsOneWidget);

    await tester.tap(find.text('Mark as Unsupported'));
    await tester.pumpAndSettle();

    expect(bridge.reportUnsupportedGameCalls, 1);
    expect(bridge.lastReportedUnsupportedGamePath, game.path);
    expect(
      container.read(gameListProvider).valueOrNull?.games.first.isUnsupported,
      isTrue,
    );
    expect(find.textContaining('marked as unsupported'), findsOneWidget);

    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    expect(find.text('Mark as Supported'), findsOneWidget);

    await tester.tap(find.text('Mark as Supported'));
    await tester.pumpAndSettle();

    expect(bridge.unreportUnsupportedGameCalls, 1);
    expect(bridge.lastUnreportedUnsupportedGamePath, game.path);
    expect(
      container.read(gameListProvider).valueOrNull?.games.first.isUnsupported,
      isFalse,
    );
    expect(find.textContaining('marked as supported'), findsOneWidget);
  });

  testWidgets('Marking unsupported preserves fresher game state updates', (
    WidgetTester tester,
  ) async {
    final game = GameInfo(
      name: 'Unsupported Merge Candidate',
      path: r'C:\Games\unsupported_merge_candidate',
      platform: Platform.steam,
      sizeBytes: 42 * _oneGiB,
    );
    final bridge = _RecordingRustBridgeService(games: <GameInfo>[game]);
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HomeGameGrid())),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    final hydratedGame = game.copyWith(
      isCompressed: true,
      compressedSize: () => 30 * _oneGiB,
      lastCompressedAt: () => DateTime(2026, 3, 8, 12, 0),
    );
    container.read(gameListProvider.notifier).updateGame(hydratedGame);
    await tester.pump();

    await tester.tap(find.text('Mark as Unsupported'));
    await tester.pumpAndSettle();

    final updatedGame = container
        .read(gameListProvider)
        .valueOrNull!
        .games
        .first;
    expect(updatedGame.isUnsupported, isTrue);
    expect(updatedGame.isCompressed, isTrue);
    expect(updatedGame.compressedSize, 30 * _oneGiB);
    expect(updatedGame.lastCompressed, DateTime(2026, 3, 8, 12, 0));
  });

  testWidgets(
    'Automation settings sync forwards DirectStorage override to auto config',
    (WidgetTester tester) async {
      final bridge = _RecordingRustBridgeService(games: _sampleGames);
      final persistence = _FixedSettingsPersistence(
        const AppSettings(
          autoCompress: true,
          directStorageOverrideEnabled: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rustBridgeServiceProvider.overrideWithValue(bridge),
            settingsPersistenceProvider.overrideWithValue(persistence),
          ],
          child: const PressPlayApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(bridge.updateAutomationConfigCalls, greaterThan(0));
      expect(bridge.startAutoCompressionCalls, greaterThan(0));
      expect(bridge.lastAutomationAllowDirectStorageOverride, isTrue);
    },
  );

  testWidgets(
    'Watcher uninstall removes card without triggering discovery refresh',
    (WidgetTester tester) async {
      final games = <GameInfo>[
        ..._sampleGames,
        GameInfo(
          name: 'Resident Evil Requiem',
          path: r'C:\Games\resident_evil_requiem',
          platform: Platform.steam,
          sizeBytes: 96 * _oneGiB,
        ),
      ];
      final bridge = _WatcherRecordingRustBridgeService(games: games);
      addTearDown(bridge.disposeWatcher);
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PressPlayApp(),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Resident Evil Requiem'), findsOneWidget);

      final baselineFullCalls = bridge.getAllGamesCalls;
      final baselineQuickCalls = bridge.getAllGamesQuickCalls;
      final baselineClearCalls = bridge.clearDiscoveryCacheCalls;

      bridge.emitWatcherEvent(
        WatcherEvent(
          type: WatcherEventType.uninstalled,
          gamePath: r'C:\Games\resident_evil_requiem',
          gameName: 'Resident Evil Requiem',
          timestamp: DateTime(2026, 3, 7, 12, 0),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        container
            .read(gameListProvider)
            .valueOrNull
            ?.games
            .any((game) => game.path == r'C:\Games\resident_evil_requiem'),
        isFalse,
      );
      expect(find.text('Resident Evil Requiem'), findsNothing);
      expect(bridge.getAllGamesCalls, baselineFullCalls);
      expect(bridge.getAllGamesQuickCalls, baselineQuickCalls);
      expect(bridge.clearDiscoveryCacheCalls, baselineClearCalls);
    },
  );

  testWidgets('Home banner shows Decompressing while decompression is active', (
    WidgetTester tester,
  ) async {
    final compressedGames = <GameInfo>[
      GameInfo(
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
    await tester.ensureVisible(find.text('Decompress Banner Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decompress Banner Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decompress'));
    await tester.pump();

    final inlineHost = find.byKey(compressionInlineActivityHostKey);
    expect(inlineHost, findsOneWidget);
    expect(
      find.descendant(of: inlineHost, matching: find.text('Decompressing')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inlineHost, matching: find.text('Cancel')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: inlineHost,
        matching: find.text('Decompress Banner Test'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(compressionFloatingActivityHostKey),
        matching: find.text('Decompressing'),
      ),
      findsNothing,
    );
    expect(bridge.decompressCalls, 1);

    await tester.tap(
      find.descendant(of: inlineHost, matching: find.text('Cancel')),
    );
    await tester.pump();

    expect(
      find.descendant(of: inlineHost, matching: find.text('Decompressing')),
      findsNothing,
    );
    expect(
      find.descendant(of: inlineHost, matching: find.text('Cancel')),
      findsNothing,
    );

    bridge.finishDecompression();
    await tester.pumpAndSettle();
  });

  _registerProgressIndicatorWidgetTests();

  testWidgets('Rapid card taps do not stack context menus', (
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

    expect(find.text('Confirm Compression'), findsNothing);
    expect(find.text('Compress Now'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
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

  test(
    'Unsupported report sync queues a follow-up run after mid-flight changes',
    () async {
      final bridge = _QueuedSyncRustBridgeService();
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(container.dispose);
      addTearDown(UnsupportedReportSyncService.instance.resetForTest);

      final service = UnsupportedReportSyncService.instance;
      service.resetForTest();

      final firstRun = service.sync(container);
      expect(bridge.syncUnsupportedReportCollectionCalls, 1);
      expect(bridge.pendingSyncCount, 1);

      service.notePotentialChange(container);
      expect(bridge.syncUnsupportedReportCollectionCalls, 1);

      bridge.completeNextSync();
      await firstRun;
      await Future<void>.delayed(Duration.zero);

      expect(bridge.syncUnsupportedReportCollectionCalls, 2);
      expect(bridge.pendingSyncCount, 1);

      bridge.completeNextSync();
      await Future<void>.delayed(Duration.zero);

      expect(bridge.pendingSyncCount, 0);
    },
  );
}
