import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/core/navigation/app_routes.dart';
import 'package:pressplay/core/theme/app_theme.dart';
import 'package:pressplay/features/games/presentation/game_details_screen.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card.dart';
import 'package:pressplay/models/app_settings.dart';
import 'package:pressplay/models/automation_state.dart';
import 'package:pressplay/models/compression_algorithm.dart';
import 'package:pressplay/models/compression_estimate.dart';
import 'package:pressplay/models/compression_progress.dart';
import 'package:pressplay/models/game_info.dart';
import 'package:pressplay/models/watcher_event.dart';
import 'package:pressplay/providers/cover_art/cover_art_provider.dart';
import 'package:pressplay/providers/games/game_list_provider.dart';
import 'package:pressplay/providers/settings/settings_persistence.dart';
import 'package:pressplay/providers/settings/settings_provider.dart';
import 'package:pressplay/services/cover_art_service.dart';
import 'package:pressplay/services/rust_bridge_service.dart';

part 'support/phase6_test_doubles.dart';

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

  test('Rust bridge provider resolves to singleton instance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final a = container.read(rustBridgeServiceProvider);
    final b = container.read(rustBridgeServiceProvider);
    expect(identical(a, b), isTrue);
    expect(identical(a, RustBridgeService.instance), isTrue);
  });

  testWidgets('GameCard cover image uses cover fit to fill frame', (
    WidgetTester tester,
  ) async {
    // Use a MemoryImage so the test does not depend on network/file I/O.
    final testProvider = MemoryImage(Uint8List.fromList(
      // 1x1 transparent PNG
      [
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
        0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
        137, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 98, 0, 0, 0, 2,
        0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66,
        96, 130,
      ],
    ));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 420,
            child: GameCard(
              gameName: 'Fit Test',
              platform: Platform.steam,
              totalSizeBytes: 10 * _oneGiB,
              coverImageProvider: testProvider,
              assumeBoundedHeight: true,
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.fit, BoxFit.cover);
    expect(image.isAntiAlias, isTrue);
    expect(image.filterQuality, FilterQuality.low);
  });

  testWidgets('Refresh retries only placeholder cover entries', (
    WidgetTester tester,
  ) async {
    final placeholderPath = _sampleGames.first.path;
    final coverArtService = _RecordingCoverArtService(
      placeholders: <String>{placeholderPath},
    );
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(
          _TestRustBridgeService(games: _sampleGames),
        ),
        coverArtServiceProvider.overrideWithValue(coverArtService),
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

    await tester.tap(find.byTooltip('Refresh games'));
    await tester.pumpAndSettle();

    final expectedInputs = _sampleGames
        .map((game) => game.path)
        .toList(growable: false);
    expect(
      coverArtService.lastPlaceholderCandidatesInput,
      orderedEquals(expectedInputs),
    );
    expect(coverArtService.invalidatedPaths, <String>[placeholderPath]);
    expect(coverArtService.clearLookupCachesCalls, 1);
  });

  test(
    'Settings custom path input resolves exe paths to folder targets',
    () async {
      final persistence = _InMemorySettingsPersistence();
      final container = ProviderContainer(
        overrides: [settingsPersistenceProvider.overrideWithValue(persistence)],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(settingsProvider.notifier);

      notifier.addCustomFolder(r'C:\Games\ManualEntry\game.exe');
      notifier.addCustomFolder(r'C:\Games\ManualEntry\game.exe');

      final folders =
          container
              .read(settingsProvider)
              .valueOrNull
              ?.settings
              .customFolders ??
          const <String>[];
      expect(folders.length, 1);
      expect(folders.first.toLowerCase().endsWith('.exe'), isFalse);
    },
  );
}
