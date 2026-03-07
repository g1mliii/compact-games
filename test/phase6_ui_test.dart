import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pressplay/core/navigation/app_routes.dart';
import 'package:pressplay/core/theme/app_theme.dart';
import 'package:pressplay/core/widgets/status_badge.dart';
import 'package:pressplay/features/games/presentation/game_details_screen.dart';
import 'package:pressplay/features/games/presentation/widgets/compression_activity_overlay.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card.dart';
import 'package:pressplay/features/games/presentation/widgets/home_compression_banner.dart';
import 'package:pressplay/models/app_settings.dart';
import 'package:pressplay/models/automation_state.dart';
import 'package:pressplay/models/compression_algorithm.dart';
import 'package:pressplay/models/compression_estimate.dart';
import 'package:pressplay/models/compression_progress.dart';
import 'package:pressplay/models/game_info.dart';
import 'package:pressplay/models/watcher_event.dart';
import 'package:pressplay/providers/cover_art/cover_art_provider.dart';
import 'package:pressplay/providers/compression/compression_provider.dart';
import 'package:pressplay/providers/games/game_list_provider.dart';
import 'package:pressplay/providers/settings/settings_persistence.dart';
import 'package:pressplay/providers/settings/settings_provider.dart';
import 'package:pressplay/providers/system/route_state_provider.dart';
import 'package:pressplay/services/cover_art_service.dart';
import 'package:pressplay/services/rust_bridge_service.dart';

part 'support/phase6_test_doubles.dart';
part 'support/phase6_ui_split_tests.dart';

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

Widget _buildRouteAwareTestApp({
  required ProviderContainer container,
  required String initialRoute,
  RouteFactory? onGenerateRoute,
}) {
  final routeObserver = container.read(routeStateObserverProvider);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(),
      initialRoute: initialRoute,
      navigatorObservers: [routeObserver],
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: child ?? const SizedBox.shrink()),
            const RepaintBoundary(child: CompressionActivityOverlay()),
          ],
        );
      },
      onGenerateRoute: onGenerateRoute ?? AppRoutes.onGenerateRoute,
    ),
  );
}

void main() {
  testWidgets('Header route button navigates to inventory', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(
          _TestRustBridgeService(games: _sampleGames),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Compression inventory'));
    await tester.pumpAndSettle();
    expect(find.text('Compression Inventory'), findsOneWidget);
  });

  testWidgets('Header route button navigates to settings', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(
          _TestRustBridgeService(games: _sampleGames),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Card context menu compress action starts compression directly', (
    WidgetTester tester,
  ) async {
    final bridge = _TestRustBridgeService(games: _sampleGames);
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(GameCard).first);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compress Now'));
    await tester.pump();

    expect(bridge.compressCalls, 1);
  });

  testWidgets('Context menu can open details route', (
    WidgetTester tester,
  ) async {
    final bridge = _TestRustBridgeService(games: _sampleGames);
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(GameCard).first);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();

    expect(find.byType(GameDetailsScreen), findsOneWidget);
    expect(find.byTooltip('Open directory'), findsOneWidget);
    expect(find.byTooltip('Copy path'), findsOneWidget);
  });

  testWidgets(
    'Details compress action shows floating activity overlay outside home',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final game = GameInfo(
        name: 'Details Overlay Compression',
        path: r'C:\Games\details_overlay_compression',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
      );
      final bridge = _DelayedActivityRustBridgeService(games: <GameInfo>[game]);
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(() {
        bridge.disposeStreams();
        container.dispose();
        tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        _buildRouteAwareTestApp(
          container: container,
          initialRoute: AppRoutes.gameDetails(game.path),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final primaryAction = find.byKey(
        const ValueKey<String>('detailsStatusPrimaryAction'),
      );
      await tester.ensureVisible(primaryAction);
      await tester.tap(primaryAction);
      await tester.pump();

      final floatingHost = find.byKey(compressionFloatingActivityHostKey);
      expect(floatingHost, findsOneWidget);
      expect(
        find.descendant(of: floatingHost, matching: find.text('Compressing')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: floatingHost, matching: find.text(game.name)),
        findsOneWidget,
      );
      expect(find.byKey(compressionInlineActivityHostKey), findsNothing);
      expect(bridge.compressCalls, 1);

      bridge.finishCompression();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'Floating activity dismiss hides monitor without cancelling active job',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final game = GameInfo(
        name: 'Dismiss Monitor Compression',
        path: r'C:\Games\dismiss_monitor_compression',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
      );
      final bridge = _DelayedActivityRustBridgeService(games: <GameInfo>[game]);
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(() {
        bridge.disposeStreams();
        container.dispose();
        tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        _buildRouteAwareTestApp(
          container: container,
          initialRoute: AppRoutes.gameDetails(game.path),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await container
          .read(compressionProvider.notifier)
          .startCompression(gamePath: game.path, gameName: game.name);
      await tester.pump();

      final floatingHost = find.byKey(compressionFloatingActivityHostKey);
      expect(
        find.descendant(of: floatingHost, matching: find.text('Compressing')),
        findsOneWidget,
      );
      final dismissButton = find.descendant(
        of: floatingHost,
        matching: find.byIcon(LucideIcons.x),
      );
      expect(dismissButton, findsOneWidget);

      await tester.tap(dismissButton);
      await tester.pump();

      expect(
        find.descendant(of: floatingHost, matching: find.text('Compressing')),
        findsNothing,
      );
      expect(container.read(compressionProvider).activeJob?.isActive, isTrue);

      bridge.emitCompressionProgress(
        gameName: game.name,
        filesProcessed: 25,
        filesTotal: 100,
        bytesOriginal: 256 * 1024 * 1024,
        bytesCompressed: 192 * 1024 * 1024,
        estimatedTimeRemaining: const Duration(seconds: 40),
      );
      await tester.pump();

      expect(
        find.descendant(of: floatingHost, matching: find.text('Compressing')),
        findsNothing,
      );
      expect(container.read(compressionProvider).activeJob?.isActive, isTrue);

      bridge.finishCompression();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'Details decompression overlay keeps scoped game name and survives narrow resize',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final game = GameInfo(
        name: 'Details Overlay Decompression',
        path: r'C:\Games\details_overlay_decompression',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
        compressedSize: 72 * _oneGiB,
        isCompressed: true,
      );
      final bridge = _DelayedActivityRustBridgeService(games: <GameInfo>[game]);
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(() {
        bridge.disposeStreams();
        container.dispose();
        tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        _buildRouteAwareTestApp(
          container: container,
          initialRoute: AppRoutes.gameDetails(game.path),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final primaryAction = find.byKey(
        const ValueKey<String>('detailsStatusPrimaryAction'),
      );
      await tester.ensureVisible(primaryAction);
      await tester.tap(primaryAction);
      await tester.pump();

      final floatingHost = find.byKey(compressionFloatingActivityHostKey);
      expect(
        find.descendant(of: floatingHost, matching: find.text('Decompressing')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: floatingHost, matching: find.text(game.name)),
        findsOneWidget,
      );

      await tester.binding.setSurfaceSize(const Size(680, 900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.descendant(of: floatingHost, matching: find.text(game.name)),
        findsOneWidget,
      );

      bridge.finishDecompression();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets('Progress ticks do not rebuild the routed page subtree', (
    WidgetTester tester,
  ) async {
    final bridge = _DelayedActivityRustBridgeService(games: _sampleGames);
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(() {
      bridge.disposeStreams();
      container.dispose();
    });

    var routeBuildCount = 0;

    Route<dynamic> buildCountingRoute(RouteSettings settings) {
      return PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          routeBuildCount += 1;
          return const Scaffold(body: Center(child: Text('Route body')));
        },
      );
    }

    await tester.pumpWidget(
      _buildRouteAwareTestApp(
        container: container,
        initialRoute: AppRoutes.inventory,
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.inventory) {
            return buildCountingRoute(
              const RouteSettings(name: AppRoutes.inventory),
            );
          }
          return AppRoutes.onGenerateRoute(settings);
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final initialBuildCount = routeBuildCount;
    expect(initialBuildCount, greaterThan(0));

    await container
        .read(compressionProvider.notifier)
        .startCompression(
          gamePath: _sampleGames.first.path,
          gameName: _sampleGames.first.name,
        );
    await tester.pump();

    bridge.emitCompressionProgress(
      gameName: _sampleGames.first.name,
      filesProcessed: 8,
      filesTotal: 100,
      bytesOriginal: 8 * 1024 * 1024,
      bytesCompressed: 6 * 1024 * 1024,
      estimatedTimeRemaining: const Duration(seconds: 12),
    );
    await tester.pump();

    bridge.emitCompressionProgress(
      gameName: _sampleGames.first.name,
      filesProcessed: 16,
      filesTotal: 100,
      bytesOriginal: 16 * 1024 * 1024,
      bytesCompressed: 11 * 1024 * 1024,
      estimatedTimeRemaining: const Duration(seconds: 10),
    );
    await tester.pump();

    expect(routeBuildCount, initialBuildCount);

    bridge.finishCompression();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('Game details status card hosts right-side action buttons', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = GameInfo(
      name: 'Details Action Layout',
      path: r'C:\Games\details_action_layout',
      platform: Platform.steam,
      sizeBytes: 96 * _oneGiB,
      compressedSize: 70 * _oneGiB,
      isCompressed: true,
    );
    final bridge = _TestRustBridgeService(games: <GameInfo>[game]);
    final persistence = _InMemorySettingsPersistence();
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(bridge),
        settingsPersistenceProvider.overrideWithValue(persistence),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: GameDetailsScreen(gamePath: game.path),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const infoCardKey = ValueKey<String>('detailsInfoCard');
    const actionRowKey = ValueKey<String>('detailsStatusActionRow');
    const primaryActionKey = ValueKey<String>('detailsStatusPrimaryAction');
    const excludeActionKey = ValueKey<String>('detailsStatusExcludeAction');

    final infoCardFinder = find.byKey(infoCardKey);
    final actionRowFinder = find.byKey(actionRowKey);

    expect(infoCardFinder, findsOneWidget);
    expect(
      find.descendant(of: infoCardFinder, matching: actionRowFinder),
      findsOneWidget,
    );
    expect(find.byKey(primaryActionKey), findsOneWidget);
    expect(find.byKey(excludeActionKey), findsOneWidget);
    expect(find.text('Decompress'), findsOneWidget);
    expect(find.text('Exclude From Auto-Compression'), findsOneWidget);

    final statusRect = tester.getRect(find.text('STATUS'));
    final actionRect = tester.getRect(actionRowFinder);
    expect(actionRect.center.dx, greaterThan(statusRect.center.dx + 120));

    await tester.tap(find.byKey(primaryActionKey));
    await tester.pumpAndSettle();
    expect(bridge.decompressCalls, 1);

    await tester.tap(find.byKey(excludeActionKey));
    await tester.pumpAndSettle();
    expect(
      container
          .read(settingsProvider)
          .valueOrNull
          ?.settings
          .excludedPaths
          .contains(game.path),
      isTrue,
    );
    expect(find.text('Include In Auto-Compression'), findsOneWidget);
  });

  testWidgets('Game details status actions reflow on compact resize', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = GameInfo(
      name: 'Details Resize Layout',
      path: r'C:\Games\details_resize_layout',
      platform: Platform.steam,
      sizeBytes: 96 * _oneGiB,
      compressedSize: 70 * _oneGiB,
      isCompressed: true,
    );
    final bridge = _TestRustBridgeService(games: <GameInfo>[game]);
    final persistence = _InMemorySettingsPersistence();
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(bridge),
        settingsPersistenceProvider.overrideWithValue(persistence),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: GameDetailsScreen(gamePath: game.path),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const actionRowKey = ValueKey<String>('detailsStatusActionRow');
    const excludeActionKey = ValueKey<String>('detailsStatusExcludeAction');
    final actionRowFinder = find.byKey(actionRowKey);

    final wideStatusRect = tester.getRect(find.text('STATUS'));
    final wideActionRect = tester.getRect(actionRowFinder);
    expect(
      wideActionRect.center.dx,
      greaterThan(wideStatusRect.center.dx + 120),
    );

    await tester.binding.setSurfaceSize(const Size(680, 900));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(actionRowFinder, findsOneWidget);

    final compactStatusRect = tester.getRect(find.text('STATUS'));
    final compactActionRect = tester.getRect(actionRowFinder);
    expect(compactActionRect.top, greaterThan(compactStatusRect.bottom));

    await tester.tap(find.byKey(excludeActionKey));
    await tester.pumpAndSettle();
    expect(find.text('Include In Auto-Compression'), findsOneWidget);
  });

  testWidgets('Game details shows last compressed when timestamp exists', (
    WidgetTester tester,
  ) async {
    final game = GameInfo(
      name: 'Details Timestamp',
      path: r'C:\Games\details_timestamp',
      platform: Platform.steam,
      sizeBytes: 96 * _oneGiB,
      compressedSize: 70 * _oneGiB,
      isCompressed: true,
      lastCompressedAt: DateTime(2026, 3, 4, 16, 5),
    );
    final bridge = _TestRustBridgeService(games: <GameInfo>[game]);
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: GameDetailsScreen(gamePath: game.path),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compressed Mar 4, 16:05'), findsOneWidget);
    expect(find.text('Last compressed'), findsNothing);
  });

  testWidgets(
    'Game details hides last compressed when game is not compressed',
    (WidgetTester tester) async {
      final game = GameInfo(
        name: 'Details No Timestamp',
        path: r'C:\Games\details_no_timestamp',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
        isCompressed: false,
        lastCompressedAt: DateTime(2026, 3, 4, 16, 5),
      );
      final bridge = _TestRustBridgeService(games: <GameInfo>[game]);
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: GameDetailsScreen(gamePath: game.path),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Last compressed'), findsNothing);
      expect(find.text('Compressed Mar 4, 16:05'), findsNothing);
    },
  );

  testWidgets(
    'Settings I/O override selector is compact and updates provider',
    (WidgetTester tester) async {
      final persistence = _InMemorySettingsPersistence();
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(games: _sampleGames),
          ),
          settingsPersistenceProvider.overrideWithValue(persistence),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            initialRoute: AppRoutes.settings,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selectorFinder = find.byKey(
        const ValueKey<String>('settingsIoOverrideSelector'),
      );
      expect(selectorFinder, findsOneWidget);
      expect(tester.getSize(selectorFinder).height, 40);

      await tester.tap(selectorFinder);
      await tester.pumpAndSettle();

      final firstMenuItem = find.byType(PopupMenuItem<int>).first;
      expect(tester.getSize(firstMenuItem).height, lessThan(40));

      await tester.tap(find.text('4 threads').last);
      await tester.pumpAndSettle();
      expect(
        container
            .read(settingsProvider)
            .valueOrNull
            ?.settings
            .ioParallelismOverride,
        4,
      );

      await tester.tap(selectorFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto').last);
      await tester.pumpAndSettle();
      expect(
        container
            .read(settingsProvider)
            .valueOrNull
            ?.settings
            .ioParallelismOverride,
        isNull,
      );

      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('Inventory search filters list rows', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(
          _TestRustBridgeService(games: _sampleGames),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          initialRoute: AppRoutes.inventory,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Dust');
    await tester.pumpAndSettle();

    expect(find.text('Dustline'), findsOneWidget);
    expect(find.text('Pixel Raider'), findsNothing);
  });

  testWidgets(
    'Inventory watcher column only marks compressed eligible games as watched',
    (WidgetTester tester) async {
      final inventoryGames = <GameInfo>[
        GameInfo(
          name: 'Watched Compression',
          path: r'C:\Games\watched_compression',
          platform: Platform.steam,
          sizeBytes: 96 * _oneGiB,
          compressedSize: 94 * _oneGiB,
          isCompressed: true,
        ),
        GameInfo(
          name: 'Fresh Install',
          path: r'C:\Games\fresh_install',
          platform: Platform.epicGames,
          sizeBytes: 48 * _oneGiB,
          isDirectStorage: true,
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(
              games: inventoryGames,
              autoCompressionRunning: true,
            ),
          ),
          settingsPersistenceProvider.overrideWithValue(
            _InMemorySettingsPersistence()
              .._current = const AppSettings(autoCompress: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            initialRoute: AppRoutes.inventory,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Watched'), findsOneWidget);
      expect(find.text('Not watched'), findsOneWidget);
    },
  );

  testWidgets(
    'Inventory groups watched games ahead of non-watched games by default',
    (WidgetTester tester) async {
      final inventoryGames = <GameInfo>[
        GameInfo(
          name: 'Excluded Compression',
          path: r'C:\Games\excluded_compression',
          platform: Platform.steam,
          sizeBytes: 96 * _oneGiB,
          compressedSize: 48 * _oneGiB,
          isCompressed: true,
        ),
        GameInfo(
          name: 'Watched Compression',
          path: r'C:\Games\watched_compression',
          platform: Platform.steam,
          sizeBytes: 96 * _oneGiB,
          compressedSize: 94 * _oneGiB,
          isCompressed: true,
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(
              games: inventoryGames,
              autoCompressionRunning: true,
            ),
          ),
          settingsPersistenceProvider.overrideWithValue(
            _InMemorySettingsPersistence()
              .._current = const AppSettings(
                autoCompress: true,
                excludedPaths: <String>[r'C:\Games\excluded_compression'],
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            initialRoute: AppRoutes.inventory,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final watchedTop = tester.getTopLeft(find.text('Watched Compression')).dy;
      final excludedTop = tester
          .getTopLeft(find.text('Excluded Compression'))
          .dy;
      expect(watchedTop, lessThan(excludedTop));
    },
  );

  testWidgets('Settings inventory advanced toggle updates provider', (
    WidgetTester tester,
  ) async {
    final persistence = _InMemorySettingsPersistence();
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(
          _TestRustBridgeService(games: _sampleGames),
        ),
        settingsPersistenceProvider.overrideWithValue(persistence),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          initialRoute: AppRoutes.settings,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container
          .read(settingsProvider)
          .valueOrNull
          ?.settings
          .inventoryAdvancedScanEnabled,
      isFalse,
    );

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('settingsInventoryAdvancedToggle')),
    );
    await tester.pumpAndSettle();

    expect(
      container
          .read(settingsProvider)
          .valueOrNull
          ?.settings
          .inventoryAdvancedScanEnabled,
      isTrue,
    );
  });

  testWidgets('Settings inventory watcher toggle updates provider', (
    WidgetTester tester,
  ) async {
    final persistence = _InMemorySettingsPersistence();
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(
          _TestRustBridgeService(games: _sampleGames),
        ),
        settingsPersistenceProvider.overrideWithValue(persistence),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          initialRoute: AppRoutes.settings,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull?.settings.autoCompress,
      isFalse,
    );

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('settingsWatcherToggleButton')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull?.settings.autoCompress,
      isTrue,
    );
  });
  runPhase6OversizeSplitTests();
}
