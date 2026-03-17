import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pressplay/core/navigation/app_routes.dart';
import 'package:pressplay/core/theme/app_colors.dart';
import 'package:pressplay/core/theme/app_theme.dart';
import 'package:pressplay/features/games/presentation/game_details_screen.dart';
import 'package:pressplay/features/games/presentation/home_screen.dart';
import 'package:pressplay/features/games/presentation/widgets/compression_activity_overlay.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card_adapter.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card_adapter_intents.dart';
import 'package:pressplay/features/games/presentation/widgets/game_details/details_media.dart';
import 'package:pressplay/features/games/presentation/widgets/home_compression_banner.dart';
import 'package:pressplay/features/games/presentation/widgets/home_cover_art_nudge.dart';
import 'package:pressplay/features/games/presentation/widgets/home_game_grid.dart';
import 'package:pressplay/features/games/presentation/widgets/home_game_list_view.dart';
import 'package:pressplay/features/games/presentation/widgets/home_header.dart';
import 'package:pressplay/features/games/presentation/widgets/home_overview_panel.dart';
import 'package:pressplay/features/games/presentation/widgets/inventory_components.dart';
import 'package:pressplay/features/settings/presentation/sections/compression_section.dart';
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
import 'package:pressplay/providers/games/selected_game_provider.dart';
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

String _sameUriCoverFixture(String name) {
  return Uri.file('C:\\PressPlayCoverFixtures\\$name.png').toString();
}

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

    await tester.tap(find.byTooltip('Open compression inventory'));
    await tester.pumpAndSettle();
    expect(find.text('Compression Inventory'), findsOneWidget);
  });

  testWidgets(
    'Header suppresses duplicate inventory primary action when inventory icon is present',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final inventoryOnlyGames = <GameInfo>[
        GameInfo(
          name: 'Already Packed',
          path: r'C:\Games\already_packed',
          platform: Platform.steam,
          sizeBytes: 64 * _oneGiB,
          isCompressed: true,
        ),
        GameInfo(
          name: 'DirectStorage Guarded',
          path: r'C:\Games\directstorage_guarded',
          platform: Platform.epicGames,
          sizeBytes: 72 * _oneGiB,
          isDirectStorage: true,
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(games: inventoryOnlyGames),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: HomeHeader(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open compression inventory'), findsOneWidget);
      expect(find.text('Open inventory'), findsNothing);
    },
  );

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

    expect(find.byTooltip('Open settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Open settings'));
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

    final firstCard = find.byType(GameCard).first;
    await tester.ensureVisible(firstCard);
    await tester.pumpAndSettle();
    final firstCardTapPoint =
        tester.getTopLeft(firstCard) + const Offset(24, 24);
    await tester.tapAt(firstCardTapPoint);
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

    final firstCard = find.byType(GameCard).first;
    await tester.ensureVisible(firstCard);
    await tester.pumpAndSettle();
    final firstCardTapPoint =
        tester.getTopLeft(firstCard) + const Offset(24, 24);
    await tester.tapAt(firstCardTapPoint);
    await tester.pumpAndSettle();

    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();

    expect(find.byType(GameDetailsScreen), findsOneWidget);
    expect(find.byTooltip('Copy path'), findsOneWidget);
    final backButtonFinder = find.byKey(
      const ValueKey<String>('gameDetailsBackButton'),
    );
    expect(backButtonFinder, findsOneWidget);
    expect(tester.getSize(backButtonFinder).width, greaterThanOrEqualTo(56));
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
      expect(
        find.byKey(const ValueKey<String>('detailsHeaderActivityBadge')),
        findsOneWidget,
      );
      expect(find.text('Compressing now'), findsOneWidget);
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

  testWidgets(
    'Details route reuses inner details widgets within a small resize bucket',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Details Resize Bucket',
        path: r'C:\Games\details_resize_bucket',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
        compressedSize: 72 * _oneGiB,
        isCompressed: true,
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

      final initialHeader = tester.widget<GameDetailsHeader>(
        find.byType(GameDetailsHeader),
      );
      final initialInfoCard = tester.widget<Card>(
        find.byKey(const ValueKey<String>('detailsInfoCard')),
      );

      await tester.binding.setSurfaceSize(const Size(912, 900));
      await tester.pumpAndSettle();

      final withinBucketHeader = tester.widget<GameDetailsHeader>(
        find.byType(GameDetailsHeader),
      );
      final withinBucketInfoCard = tester.widget<Card>(
        find.byKey(const ValueKey<String>('detailsInfoCard')),
      );
      expect(identical(withinBucketHeader, initialHeader), isTrue);
      expect(identical(withinBucketInfoCard, initialInfoCard), isTrue);

      await tester.binding.setSurfaceSize(const Size(944, 900));
      await tester.pumpAndSettle();

      final nextBucketHeader = tester.widget<GameDetailsHeader>(
        find.byType(GameDetailsHeader),
      );
      expect(identical(nextBucketHeader, withinBucketHeader), isFalse);
      expect(tester.takeException(), isNull);
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

  testWidgets('Game card context menu stays narrower than the card', (
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

    final firstCard = find.byType(GameCard).first;
    await tester.ensureVisible(firstCard);
    await tester.pumpAndSettle();
    final cardRect = tester.getRect(firstCard);
    final firstCardTapPoint =
        tester.getTopLeft(firstCard) + const Offset(24, 24);
    await tester.tapAt(firstCardTapPoint);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('gameCardDangerDivider')),
      findsOneWidget,
    );

    final firstMenuItem = find.byType(PopupMenuItem<GameContextAction>).first;
    final menuItemRect = tester.getRect(firstMenuItem);

    expect(menuItemRect.width, lessThan(cardRect.width - 24));
    expect(menuItemRect.width, lessThanOrEqualTo(260));
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
    expect(
      find.byKey(const ValueKey<String>('detailsStorageComparisonBar')),
      findsOneWidget,
    );

    final statusRect = tester.getRect(find.text('Status'));
    final actionRect = tester.getRect(actionRowFinder);
    expect(actionRect.center.dx, greaterThan(statusRect.center.dx + 120));

    await tester.tap(find.byKey(primaryActionKey));
    await tester.pumpAndSettle();
    expect(bridge.decompressCalls, 1);

    await tester.tap(find.byKey(excludeActionKey));
    await tester.pump(const Duration(milliseconds: 600));
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

    final wideStatusRect = tester.getRect(find.text('Status'));
    final wideActionRect = tester.getRect(actionRowFinder);
    expect(
      wideActionRect.center.dx,
      greaterThan(wideStatusRect.center.dx + 120),
    );

    await tester.binding.setSurfaceSize(const Size(680, 900));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(actionRowFinder, findsOneWidget);

    final compactStatusRect = tester.getRect(find.text('Status'));
    final compactActionRect = tester.getRect(actionRowFinder);
    expect(compactActionRect.top, greaterThan(compactStatusRect.bottom));

    await tester.tap(find.byKey(excludeActionKey));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Include In Auto-Compression'), findsOneWidget);
  });

  testWidgets(
    'Game details storage comparison bar renders visible current and saved segments for compressed games',
    (WidgetTester tester) async {
      final game = GameInfo(
        name: 'Details Storage Bar',
        path: r'C:\Games\details_storage_bar',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
        compressedSize: 72 * _oneGiB,
        isCompressed: true,
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

      final barFinder = find.byKey(
        const ValueKey<String>('detailsStorageComparisonBar'),
      );
      final currentFillFinder = find.byKey(
        const ValueKey<String>('detailsStorageCurrentFill'),
      );
      final savedFillFinder = find.byKey(
        const ValueKey<String>('detailsStorageSavedFill'),
      );

      expect(barFinder, findsOneWidget);
      expect(currentFillFinder, findsOneWidget);
      expect(savedFillFinder, findsOneWidget);

      final barWidth = tester.getSize(barFinder).width;
      final currentWidth = tester.getSize(currentFillFinder).width;
      final savedWidth = tester.getSize(savedFillFinder).width;

      expect(currentWidth, closeTo(barWidth * 0.75, 1.5));
      expect(savedWidth, closeTo(barWidth * 0.25, 1.5));
      expect(currentWidth, greaterThan(savedWidth));
    },
  );

  testWidgets('Game details install path stays overflow-free at narrow width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = GameInfo(
      name: 'Details Narrow Path',
      path:
          r'C:\Program Files\Epic Games\rocketleague\Very\Long\Nested\Folder\Path\To\Game',
      platform: Platform.epicGames,
      sizeBytes: 96 * _oneGiB,
      compressedSize: 70 * _oneGiB,
      isCompressed: true,
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

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Copy path'), findsOneWidget);
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
    expect(
      find.byKey(const ValueKey<String>('detailsHeaderStatusBadge')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('detailsHeaderStatusBadge')),
        matching: find.text('Compressed'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('detailsHeaderLastCompressedBadge')),
      findsOneWidget,
    );
    expect(find.text('Last compressed Mar 4, 16:05'), findsOneWidget);
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

  testWidgets('Game cards stay stable when exclusion settings change', (
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
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialCard = tester.widget<GameCard>(find.byType(GameCard).first);

    container
        .read(settingsProvider.notifier)
        .toggleGameExclusion(_sampleGames.first.path);
    await tester.pump();

    final afterToggleCard = tester.widget<GameCard>(
      find.byType(GameCard).first,
    );
    expect(identical(afterToggleCard, initialCard), isTrue);

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'Settings screen uses a single shared SteamGridDB field and inline key actions',
    (WidgetTester tester) async {
      final persistence = _InMemorySettingsPersistence();
      await persistence.save(
        const AppSettings(
          steamGridDbApiKey: 'pressplay-demo-key',
          idleDurationMinutes: 23,
          cpuThreshold: 19,
        ),
      );
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

      final idleLabel = tester.widget<Text>(find.text('23 min'));
      final cpuLabel = tester.widget<Text>(find.text('19%'));
      expect(idleLabel.style?.color, AppColors.success);
      expect(cpuLabel.style?.color, AppColors.error);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('settingsSteamGridDbField')),
        findsOneWidget,
      );
      expect(find.text('SteamGridDB API key'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('settingsSteamGridDbSaveButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('settingsSteamGridDbRemoveButton')),
        findsOneWidget,
      );
      expect(find.byTooltip('Show key'), findsOneWidget);
      expect(find.byTooltip('Copy key'), findsOneWidget);
      expect(
        find.text(
          'SteamGridDB artwork is only fetched once per game unless you refresh it.',
        ),
        findsOneWidget,
      );

      final saveButtonSize = tester.getSize(
        find.byKey(const ValueKey<String>('settingsSteamGridDbSaveButton')),
      );
      expect(saveButtonSize.height, greaterThanOrEqualTo(40));
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

      final firstMenuItem = find.ancestor(
        of: find.text('Auto').last,
        matching: find.byWidgetPredicate(
          (widget) => widget is PopupMenuEntry<dynamic>,
        ),
      );
      expect(tester.getSize(firstMenuItem).height, greaterThanOrEqualTo(38));

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

  testWidgets(
    'Compression section shell stays stable while selector leaves update',
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
            home: const Scaffold(body: CompressionSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialCard = tester.widget<Card>(find.byType(Card));

      container
          .read(settingsProvider.notifier)
          .updateAlgorithm(CompressionAlgorithm.lzx);
      await tester.pump();

      final afterAlgorithmCard = tester.widget<Card>(find.byType(Card));
      expect(identical(afterAlgorithmCard, initialCard), isTrue);
      expect(find.text(CompressionAlgorithm.lzx.displayName), findsOneWidget);

      container.read(settingsProvider.notifier).setIoParallelismOverride(4);
      await tester.pump();

      final afterIoCard = tester.widget<Card>(find.byType(Card));
      expect(identical(afterIoCard, initialCard), isTrue);
      expect(find.text('4 threads'), findsOneWidget);

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
    'Inventory route reuses the list shell for header-only settings updates',
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
            initialRoute: AppRoutes.inventory,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialListBoundary = tester.widget<RepaintBoundary>(
        find.byKey(inventoryListBoundaryKey),
      );

      container
          .read(settingsProvider.notifier)
          .updateAlgorithm(CompressionAlgorithm.lzx);
      await tester.pump();

      final updatedListBoundary = tester.widget<RepaintBoundary>(
        find.byKey(inventoryListBoundaryKey),
      );
      expect(identical(updatedListBoundary, initialListBoundary), isTrue);
      expect(
        container.read(settingsProvider).valueOrNull?.settings.algorithm,
        CompressionAlgorithm.lzx,
      );
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Inventory route reuses the list shell for metadata-only row updates when path order is unchanged',
    (WidgetTester tester) async {
      final inventoryGames = <GameInfo>[
        GameInfo(
          name: 'Higher Savings',
          path: r'C:\Games\higher_savings',
          platform: Platform.steam,
          sizeBytes: 100 * _oneGiB,
          compressedSize: 50 * _oneGiB,
          isCompressed: true,
        ),
        GameInfo(
          name: 'Lower Savings',
          path: r'C:\Games\lower_savings',
          platform: Platform.steam,
          sizeBytes: 100 * _oneGiB,
          compressedSize: 90 * _oneGiB,
          isCompressed: true,
        ),
      ];
      final persistence = _InMemorySettingsPersistence();
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(games: inventoryGames),
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
            initialRoute: AppRoutes.inventory,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialListBoundary = tester.widget<RepaintBoundary>(
        find.byKey(inventoryListBoundaryKey),
      );

      container
          .read(gameListProvider.notifier)
          .updateGameByPath(
            inventoryGames.first.path,
            (game) => game.copyWith(name: 'Higher Savings Updated'),
          );
      await tester.pump();

      final updatedListBoundary = tester.widget<RepaintBoundary>(
        find.byKey(inventoryListBoundaryKey),
      );
      expect(identical(updatedListBoundary, initialListBoundary), isTrue);
      expect(find.text('Higher Savings Updated'), findsOneWidget);
    },
  );

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
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull?.settings.autoCompress,
      isTrue,
    );
  });
  runPhase6OversizeSplitTests();
}
