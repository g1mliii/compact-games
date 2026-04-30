import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:compact_games/core/navigation/app_routes.dart';
import 'package:compact_games/core/config/cover_art_proxy_config.dart';
import 'package:compact_games/core/theme/app_colors.dart';
import 'package:compact_games/core/theme/app_theme.dart';
import 'package:compact_games/features/games/presentation/game_details_screen.dart';
import 'package:compact_games/features/games/presentation/home_screen.dart';
import 'package:compact_games/features/games/presentation/inventory_screen.dart';
import 'package:compact_games/features/games/presentation/widgets/compression_activity_overlay.dart';
import 'package:compact_games/features/games/presentation/widgets/game_card.dart';
import 'package:compact_games/features/games/presentation/widgets/game_card_adapter.dart';
import 'package:compact_games/features/games/presentation/widgets/game_card_adapter_intents.dart';
import 'package:compact_games/features/games/presentation/widgets/game_details/details_media.dart';
import 'package:compact_games/features/games/presentation/widgets/home_compression_banner.dart';
import 'package:compact_games/features/games/presentation/widgets/home_cover_art_nudge.dart';
import 'package:compact_games/features/games/presentation/widgets/home_game_grid.dart';
import 'package:compact_games/features/games/presentation/widgets/home_game_list_view.dart';
import 'package:compact_games/features/games/presentation/widgets/home_header.dart';
import 'package:compact_games/features/games/presentation/widgets/home_overview_panel.dart';
import 'package:compact_games/features/games/presentation/widgets/inventory_components.dart';
import 'package:compact_games/features/settings/presentation/settings_screen.dart';
import 'package:compact_games/features/settings/presentation/sections/compression_section.dart';
import 'package:compact_games/features/settings/presentation/widgets/scaled_switch_row.dart';
import 'package:compact_games/features/settings/presentation/widgets/settings_slider_row.dart';
import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/models/automation_state.dart';
import 'package:compact_games/models/compression_algorithm.dart';
import 'package:compact_games/models/compression_estimate.dart';
import 'package:compact_games/models/compression_progress.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/models/watcher_event.dart';
import 'package:compact_games/providers/cover_art/cover_art_provider.dart';
import 'package:compact_games/providers/compression/compression_provider.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/games/selected_game_provider.dart';
import 'package:compact_games/providers/settings/settings_persistence.dart';
import 'package:compact_games/providers/settings/settings_provider.dart';
import 'package:compact_games/providers/system/route_state_provider.dart';
import 'package:compact_games/services/cover_art_service.dart';
import 'package:compact_games/services/rust_bridge_service.dart';
import 'package:compact_games/src/rust/api/update.dart' as rust_update;

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
  return Uri.file('C:\\CompactGamesCoverFixtures\\$name.png').toString();
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
    expect(find.byKey(InventoryScreen.backButtonKey), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);
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

    await tester.tap(find.byTooltip('Open settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(SettingsScreen.backButtonKey), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);
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
    expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);
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

      final decompressAction = find.byKey(
        const ValueKey<String>('detailsStatusDecompressAction'),
      );
      await tester.ensureVisible(decompressAction);
      await tester.tap(decompressAction);
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

      final initialCover = tester.widget<GameDetailsCover>(
        find.byType(GameDetailsCover),
      );
      final initialInfoCard = tester.widget<Card>(
        find.byKey(const ValueKey<String>('detailsInfoCard')),
      );

      await tester.binding.setSurfaceSize(const Size(912, 900));
      await tester.pumpAndSettle();

      final withinBucketCover = tester.widget<GameDetailsCover>(
        find.byType(GameDetailsCover),
      );
      final withinBucketInfoCard = tester.widget<Card>(
        find.byKey(const ValueKey<String>('detailsInfoCard')),
      );
      expect(identical(withinBucketCover, initialCover), isTrue);
      expect(identical(withinBucketInfoCard, initialInfoCard), isTrue);

      await tester.binding.setSurfaceSize(const Size(944, 900));
      await tester.pumpAndSettle();

      final nextBucketCover = tester.widget<GameDetailsCover>(
        find.byType(GameDetailsCover),
      );
      expect(identical(nextBucketCover, withinBucketCover), isFalse);
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
    const decompressActionKey = ValueKey<String>(
      'detailsStatusDecompressAction',
    );
    const excludeActionKey = ValueKey<String>('detailsStatusExcludeAction');
    Finder tooltipMessage(String message) => find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == message,
    );

    final infoCardFinder = find.byKey(infoCardKey);
    final actionRowFinder = find.byKey(actionRowKey);

    expect(infoCardFinder, findsOneWidget);
    expect(
      find.descendant(of: infoCardFinder, matching: actionRowFinder),
      findsOneWidget,
    );
    expect(find.byKey(primaryActionKey), findsOneWidget);
    expect(find.byKey(decompressActionKey), findsOneWidget);
    expect(find.byKey(excludeActionKey), findsOneWidget);
    expect(find.text('Recompress'), findsOneWidget);
    expect(find.text('Decompress'), findsOneWidget);
    expect(tooltipMessage('Exclude From Auto-Compression'), findsOneWidget);

    final statusRect = tester.getRect(find.text('Status'));
    final actionRect = tester.getRect(actionRowFinder);
    expect(actionRect.center.dx, greaterThan(statusRect.center.dx + 120));
    final alignmentDelta =
        (tester.getCenter(find.byKey(primaryActionKey)).dy -
                tester.getCenter(find.byKey(excludeActionKey)).dy)
            .abs();
    expect(alignmentDelta, lessThanOrEqualTo(2));

    await tester.tap(find.byKey(primaryActionKey));
    await tester.pumpAndSettle();
    expect(bridge.compressCalls, 1);
    expect(bridge.decompressCalls, 0);

    await tester.tap(find.byKey(decompressActionKey));
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
    expect(tooltipMessage('Include In Auto-Compression'), findsOneWidget);
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
    Finder tooltipMessage(String message) => find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == message,
    );

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
    expect(tooltipMessage('Include In Auto-Compression'), findsOneWidget);
  });

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

  testWidgets('Game details stat labels stay visually tight to their values', (
    WidgetTester tester,
  ) async {
    final game = GameInfo(
      name: 'Details Stat Alignment',
      path: r'C:\Games\details_stat_alignment',
      platform: Platform.steam,
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

    final infoCard = find.byKey(const ValueKey<String>('detailsInfoCard'));
    final platformLabel = find.descendant(
      of: infoCard,
      matching: find.text('Platform'),
    );
    final platformValue = find.descendant(
      of: infoCard,
      matching: find.text('Steam'),
    );

    expect(platformLabel, findsOneWidget);
    expect(platformValue, findsOneWidget);

    final gap =
        tester.getRect(platformValue).left -
        tester.getRect(platformLabel).right;
    expect(gap, lessThanOrEqualTo(18));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Game details install path box keeps vertical breathing room', (
    WidgetTester tester,
  ) async {
    final game = GameInfo(
      name: 'Details Path Breathing Room',
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

    final pathBlock = find.byKey(
      const ValueKey<String>('detailsInstallPathBlock'),
    );
    final pathText = find.descendant(
      of: pathBlock,
      matching: find.byType(SelectableText),
    );

    expect(pathBlock, findsOneWidget);
    expect(pathText, findsOneWidget);

    final pathBlockRect = tester.getRect(pathBlock);
    final pathTextRect = tester.getRect(pathText);

    expect(pathTextRect.top - pathBlockRect.top, greaterThanOrEqualTo(9));
    expect(pathBlockRect.bottom - pathTextRect.bottom, greaterThanOrEqualTo(9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Game details overlay shows status badge on the cover', (
    WidgetTester tester,
  ) async {
    final game = GameInfo(
      name: 'Details Status Badge',
      path: r'C:\Games\details_status_badge',
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

    expect(
      find.descendant(
        of: find.byType(GameDetailsCover),
        matching: find.byKey(
          const ValueKey<String>('detailsHeaderStatusBadge'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('detailsHeaderLastCompressedBadge')),
      findsNothing,
    );
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
    'Settings screen shows own-key SteamGridDB field and inline key actions',
    (WidgetTester tester) async {
      final persistence = _InMemorySettingsPersistence();
      await persistence.save(
        const AppSettings(
          steamGridDbApiKey: 'compact-games-demo-key',
          coverArtProviderMode: CoverArtProviderMode.userKey,
          idleDurationMinutes: 14,
          cpuThreshold: 72,
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

      final idleLabel = tester.widget<Text>(find.text('14 min'));
      final cpuLabel = tester.widget<Text>(find.text('72%'));
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

      final saveButtonSize = tester.getSize(
        find.byKey(const ValueKey<String>('settingsSteamGridDbSaveButton')),
      );
      expect(saveButtonSize.height, greaterThanOrEqualTo(40));
    },
  );

  test(
    'Cover art provider watches SteamGridDB key and provider mode',
    () async {
      final game = _sampleGames.first.copyWith(
        path: r'C:\Games\cover_provider_settings_watch',
        platform: Platform.custom,
      );
      final persistence = _InMemorySettingsPersistence();
      await persistence.save(const AppSettings());
      final coverService = _RecordingCoverArtService(placeholders: const {});
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(games: <GameInfo>[game]),
          ),
          settingsPersistenceProvider.overrideWithValue(persistence),
          coverArtServiceProvider.overrideWithValue(coverService),
        ],
      );
      addTearDown(container.dispose);

      await container.read(gameListProvider.future);
      await container.read(settingsProvider.future);
      await container.read(coverArtProvider(game.path).future);
      expect(
        coverService.lastCoverArtProviderMode,
        CoverArtProviderMode.bundledProxy,
      );
      expect(coverService.lastSteamGridDbApiKey, isNull);

      container
          .read(settingsProvider.notifier)
          .setCoverArtProviderMode(CoverArtProviderMode.userKey);
      await container.pump();
      await container.read(coverArtProvider(game.path).future);
      expect(
        coverService.lastCoverArtProviderMode,
        CoverArtProviderMode.userKey,
      );

      container
          .read(settingsProvider.notifier)
          .setSteamGridDbApiKey('compact-games-demo-key');
      await container.pump();
      await container.read(coverArtProvider(game.path).future);
      expect(coverService.lastSteamGridDbApiKey, 'compact-games-demo-key');
    },
  );

  test(
    'Cover art provider waits for settings before resolving through proxy',
    () async {
      final game = _sampleGames.first.copyWith(
        path: r'C:\Games\cover_provider_waits_for_settings',
        platform: Platform.steam,
        steamAppId: () => 730,
      );
      final persistence = _DeferredSettingsPersistence();
      final coverService = _RecordingCoverArtService(placeholders: const {});
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(games: <GameInfo>[game]),
          ),
          settingsPersistenceProvider.overrideWithValue(persistence),
          coverArtServiceProvider.overrideWithValue(coverService),
        ],
      );
      addTearDown(container.dispose);

      await container.read(gameListProvider.future);
      final coverFuture = container.read(coverArtProvider(game.path).future);
      await container.pump();
      expect(coverService.lastCoverArtProviderMode, isNull);
      expect(coverService.lastSteamGridDbApiKey, isNull);

      persistence.complete(
        const AppSettings(
          coverArtProviderMode: CoverArtProviderMode.userKey,
          steamGridDbApiKey: 'delayed-user-key',
        ),
      );
      await coverFuture;

      expect(
        coverService.lastCoverArtProviderMode,
        CoverArtProviderMode.userKey,
      );
      expect(coverService.lastSteamGridDbApiKey, 'delayed-user-key');
    },
  );

  testWidgets('Settings threshold value chips allow exact numeric entry', (
    WidgetTester tester,
  ) async {
    final persistence = _InMemorySettingsPersistence();
    await persistence.save(
      const AppSettings(idleDurationMinutes: 9, cpuThreshold: 11),
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

    await tester.tap(
      find.byKey(const ValueKey<String>('settingsIdleThresholdValue')),
    );
    await tester.pumpAndSettle();

    final sliderValueField = find.byKey(
      const ValueKey<String>('settingsSliderValueField'),
    );
    expect(sliderValueField, findsOneWidget);
    await tester.enterText(sliderValueField, '16');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Set'));
    await tester.pumpAndSettle();

    expect(
      container
          .read(settingsProvider)
          .valueOrNull
          ?.settings
          .idleDurationMinutes,
      15,
    );
    expect(find.text('15 min'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('settingsCpuThresholdValue')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(sliderValueField, '81');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Set'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).valueOrNull?.settings.cpuThreshold,
      80,
    );
    expect(find.text('80%'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'Settings slider exact-value trigger supports keyboard activation',
    (WidgetTester tester) async {
      double? committedValue;
      var requestCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SettingsSliderRow(
              label: 'Idle threshold',
              value: 9,
              min: 5,
              max: 30,
              divisions: 25,
              valueKey: const ValueKey<String>('sliderDirectEntryButton'),
              valueLabelBuilder: (value) => '${value.round()} min',
              onRequestDirectEntry:
                  (context, currentValue, minValue, maxValue) async {
                    requestCount += 1;
                    return 12;
                  },
              onChangedCommitted: (value) {
                committedValue = value;
              },
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(requestCount, 1);
      expect(committedValue, 12);
    },
  );

  testWidgets('Scaled switch row label surface supports keyboard activation', (
    WidgetTester tester,
  ) async {
    var currentValue = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: ScaledSwitchRow(
                label: 'Allow DirectStorage override',
                value: currentValue,
                onChanged: (value) {
                  setState(() {
                    currentValue = value;
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(currentValue, isTrue);
    final labelInk = tester.widget<Ink>(
      find.descendant(
        of: find.byType(ScaledSwitchRow),
        matching: find.byType(Ink),
      ),
    );
    final decoration = labelInk.decoration as BoxDecoration;
    expect(decoration.color, AppColors.selectionSurface);
  });

  testWidgets('Safety toggle stays vertically centered with its label', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    final toggleRow = find.byKey(
      const ValueKey<String>('settingsDirectStorageToggle'),
    );
    await tester.ensureVisible(toggleRow);
    await tester.pumpAndSettle();

    final switchFinder = find.descendant(
      of: toggleRow,
      matching: find.byType(Switch),
    );
    final labelFinder = find.descendant(
      of: toggleRow,
      matching: find.text('Allow DirectStorage override'),
    );
    final labelSurface = tester.widget<InkWell>(
      find.descendant(of: toggleRow, matching: find.byType(InkWell)),
    );

    expect(switchFinder, findsOneWidget);
    expect(labelFinder, findsOneWidget);
    expect(labelSurface.hoverColor, Colors.transparent);
    expect(labelSurface.focusColor, Colors.transparent);
    final labelInk = tester.widget<Ink>(
      find.descendant(of: toggleRow, matching: find.byType(Ink)),
    );
    final decoration = labelInk.decoration as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.border?.top.color, Colors.transparent);

    final centerDelta =
        (tester.getCenter(switchFinder).dy - tester.getCenter(labelFinder).dy)
            .abs();
    expect(centerDelta, lessThanOrEqualTo(3));
  });

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
      await tester.enterText(selectorFinder, '4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
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
      await tester.enterText(selectorFinder, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
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
    'Settings I/O override selector ignores unchanged submit commits',
    (WidgetTester tester) async {
      final persistence = _InMemorySettingsPersistence();
      await persistence.save(const AppSettings(ioParallelismOverride: 4));
      persistence.resetSaveCalls();
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

      await tester.tap(selectorFinder);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(persistence.saveCalls, 0);
      expect(
        container
            .read(settingsProvider)
            .valueOrNull
            ?.settings
            .ioParallelismOverride,
        4,
      );
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
      final ioField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('settingsIoOverrideSelector')),
      );
      expect(ioField.controller?.text, '4');

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

  runPhase6OversizeSplitTests();
}
