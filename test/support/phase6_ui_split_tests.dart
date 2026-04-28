part of '../phase6_ui_test.dart';

void runPhase6OversizeSplitTests() {
  testWidgets('Home header reflows actions below search at very narrow width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    expect(tester.takeException(), isNull);

    final searchRect = tester.getRect(find.byType(TextField).first);
    final refreshRect = tester.getRect(find.byTooltip('Refresh games'));
    expect(refreshRect.top, greaterThan(searchRect.bottom));
  });

  testWidgets('Home header reuses responsive subtree within the wide layout', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(980, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    final finder = find.byKey(
      const ValueKey<String>('homeHeaderLayout:wide-grouped'),
    );
    final initialLayout = tester.widget<KeyedSubtree>(finder);

    await tester.binding.setSurfaceSize(const Size(1008, 900));
    await tester.pumpAndSettle();

    final resizedLayout = tester.widget<KeyedSubtree>(finder);
    expect(identical(resizedLayout, initialLayout), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home header keeps one review action on wide layouts and groups view toggles separately',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final persistence = _InMemorySettingsPersistence();
      await persistence.save(
        const AppSettings(homeViewMode: HomeViewMode.grid),
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
          child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review eligible games'), findsOneWidget);

      final viewGroupRect = tester.getRect(
        find.byKey(const ValueKey<String>('homeHeaderViewModeGroup')),
      );
      final addGameRect = tester.getRect(find.byTooltip('Add game'));
      expect(addGameRect.left, greaterThan(viewGroupRect.right + 8));
    },
  );

  testWidgets('Home overview panel reuses shell within the same layout mode', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(980, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          home: const Scaffold(
            body: HomeOverviewPanel(useCompactSummaryOverride: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey<String>('homeOverviewPanelShell'));
    final initialShell = tester.widget<Padding>(finder);

    await tester.binding.setSurfaceSize(const Size(1008, 900));
    await tester.pumpAndSettle();

    final resizedShell = tester.widget<Padding>(finder);
    expect(identical(resizedShell, initialShell), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home overview panel can collapse into a compact summary', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final persistence = _InMemorySettingsPersistence();
    await persistence.save(const AppSettings(homeViewMode: HomeViewMode.grid));
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
          home: const Scaffold(
            body: HomeOverviewPanel(useCompactSummaryOverride: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shellFinder = find.byKey(
      const ValueKey<String>('homeOverviewPanelShell'),
    );
    expect(shellFinder, findsOneWidget);
    final compactLeadFinder = find.byKey(
      const ValueKey<String>('homeOverviewCompactLead'),
    );
    final startedCompact = compactLeadFinder.evaluate().isNotEmpty;

    final collapseButton = find.byKey(
      const ValueKey<String>('homeOverviewToggleButton'),
    );
    expect(collapseButton, findsOneWidget);
    final expandedShellRect = tester.getRect(shellFinder);
    final expandedButtonRect = tester.getRect(collapseButton);
    expect(
      (expandedButtonRect.center.dx - expandedShellRect.center.dx).abs(),
      lessThanOrEqualTo(1),
    );
    expect(expandedButtonRect.width, greaterThanOrEqualTo(88));
    expect(
      (expandedShellRect.bottom - expandedButtonRect.bottom).abs(),
      lessThanOrEqualTo(1),
    );
    await tester.tap(collapseButton);
    await tester.pumpAndSettle();

    expect(compactLeadFinder.evaluate().isNotEmpty, isNot(startedCompact));

    final expandButton = find.byKey(
      const ValueKey<String>('homeOverviewToggleButton'),
    );
    expect(expandButton, findsOneWidget);
    final compactShellRect = tester.getRect(shellFinder);
    final compactButtonRect = tester.getRect(expandButton);
    expect(
      (compactButtonRect.center.dx - compactShellRect.center.dx).abs(),
      lessThanOrEqualTo(1),
    );
    expect(compactButtonRect.width, greaterThanOrEqualTo(88));
    expect(
      (compactShellRect.bottom - compactButtonRect.bottom).abs(),
      lessThanOrEqualTo(1),
    );
    await tester.tap(expandButton);
    await tester.pumpAndSettle();

    expect(compactLeadFinder.evaluate().isNotEmpty, startedCompact);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home overview toggle stays below stacked stats content', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final persistence = _InMemorySettingsPersistence();
    await persistence.save(const AppSettings(homeViewMode: HomeViewMode.grid));
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
          home: const Scaffold(
            body: HomeOverviewPanel(useCompactSummaryOverride: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statsRect = tester.getRect(
      find.byKey(const ValueKey<String>('homeOverviewStatsCard')),
    );
    final toggleRect = tester.getRect(
      find.byKey(const ValueKey<String>('homeOverviewToggleButton')),
    );

    expect(toggleRect.top, greaterThanOrEqualTo(statsRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home compact overview keeps lead copy expanded, trailing actions pinned right, and hides the dead toggle',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
            home: const Scaffold(body: HomeOverviewPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shellFinder = find.byKey(
        const ValueKey<String>('homeOverviewPanelShell'),
      );
      final leadFinder = find.byKey(
        const ValueKey<String>('homeOverviewCompactLead'),
      );
      final trailingFinder = find.byKey(
        const ValueKey<String>('homeOverviewCompactTrailing'),
      );
      final initialLeadRect = tester.getRect(leadFinder);
      final initialTrailingRect = tester.getRect(trailingFinder);
      final initialShellRect = tester.getRect(shellFinder);

      expect(initialTrailingRect.right, greaterThan(initialLeadRect.right));
      expect(
        initialShellRect.right - initialTrailingRect.right,
        lessThanOrEqualTo(56),
      );
      expect(
        find.byKey(const ValueKey<String>('homeOverviewToggleButton')),
        findsNothing,
      );

      await tester.binding.setSurfaceSize(const Size(1400, 720));
      await tester.pumpAndSettle();

      final widenedLeadRect = tester.getRect(leadFinder);
      final widenedTrailingRect = tester.getRect(trailingFinder);
      final widenedShellRect = tester.getRect(shellFinder);

      expect(widenedLeadRect.width, greaterThan(initialLeadRect.width));
      expect(
        widenedShellRect.right - widenedTrailingRect.right,
        lessThanOrEqualTo(56),
      );
      expect(
        find.byKey(const ValueKey<String>('homeOverviewToggleButton')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home cover-art nudge reflows actions at very narrow width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          home: const Scaffold(body: HomeCoverArtNudge()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final messageRect = tester.getRect(
      find.textContaining('Connect SteamGridDB in Settings'),
    );
    final settingsRect = tester.getRect(find.text('Go to Settings'));
    expect(settingsRect.top, greaterThan(messageRect.bottom));
  });

  testWidgets('Home list view stacks details below the list at narrow width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          home: const Scaffold(body: HomeGameListView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final listRowRect = tester.getRect(find.text('Pixel Raider'));
    final detailHintRect = tester.getRect(find.text('Choose a game'));
    expect(detailHintRect.top, greaterThan(listRowRect.bottom));

    await tester.tap(find.text('Pixel Raider'));
    await tester.pumpAndSettle();

    expect(find.text('Status'), findsOneWidget);
    final statusRect = tester.getRect(find.text('Status'));
    expect(statusRect.top, greaterThan(listRowRect.bottom));
  });

  test('Home list view stacked-height bucketing preserves its minimum', () {
    expect(bucketHomeGameListPanelHeight(290), 90);
    expect(bucketHomeGameListPanelHeight(double.infinity), 240);
  });

  testWidgets(
    'Home list view keeps cover and status side by side in split mode',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
            home: const Scaffold(body: HomeGameListView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pixel Raider'));
      await tester.pumpAndSettle();

      final coverRect = tester.getRect(find.byType(GameDetailsCover));
      final statusRect = tester.getRect(find.text('Status'));

      expect(coverRect.left, lessThan(statusRect.left));
      expect(statusRect.top, lessThan(coverRect.bottom));
    },
  );

  testWidgets('Home list rows support keyboard activation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          home: const Scaffold(body: HomeGameListView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      container.read(selectedGameProvider),
      anyOf(_sampleGames[0].path, _sampleGames[1].path),
    );
    expect(find.text('Status'), findsOneWidget);
  });

  testWidgets(
    'Home list rows avoid row-wide ValueListenableBuilder hover wrappers',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
            home: const Scaffold(body: HomeGameListView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rowFinder = find.ancestor(
        of: find.text('Pixel Raider'),
        matching: find.byType(InkWell),
      );
      expect(rowFinder, findsOneWidget);
      expect(
        find.descendant(
          of: rowFinder,
          matching: find.byType(ValueListenableBuilder<bool>),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: rowFinder, matching: find.byType(RepaintBoundary)),
        findsNothing,
      );
      expect(tester.getSize(rowFinder).height, greaterThanOrEqualTo(55));

      await tester.tap(find.text('Pixel Raider'));
      await tester.pumpAndSettle();

      final selectedSurface = tester.widget<Ink>(
        find.ancestor(
          of: find.text('Pixel Raider'),
          matching: find.byType(Ink),
        ),
      );
      final selectedDecoration = selectedSurface.decoration as BoxDecoration;
      expect(selectedDecoration.gradient, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home grid cards avoid adapter-local repaint boundaries', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          home: const Scaffold(body: HomeGameGrid()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final adapterFinder = find.byType(GameCardAdapter).first;
    expect(adapterFinder, findsOneWidget);
    expect(
      find.descendant(
        of: adapterFinder,
        matching: find.byType(RepaintBoundary),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home grid card refreshes same-URI cover art without recreating grid shell',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Cover Refresh Grid',
        path: r'C:\Games\cover_refresh_grid',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
      );
      final coverService = _VersionedSameUriCoverArtService(
        coverUri: _sameUriCoverFixture('grid-cover-refresh'),
      );
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(games: <GameInfo>[game]),
          ),
          coverArtServiceProvider.overrideWithValue(coverService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: HomeGameGrid()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final initialGrid = tester.widget<GridView>(find.byType(GridView));
      final initialCard = tester.widget<GameCard>(find.byType(GameCard).first);
      final initialProvider = initialCard.coverImageProvider;
      expect(initialProvider, isNotNull);

      coverService.rewriteCover(game.path);
      container.invalidate(coverArtProvider(game.path));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final updatedGrid = tester.widget<GridView>(find.byType(GridView));
      final updatedCard = tester.widget<GameCard>(find.byType(GameCard).first);
      final updatedProvider = updatedCard.coverImageProvider;
      expect(identical(updatedGrid, initialGrid), isTrue);
      expect(updatedProvider, isNotNull);
      expect(updatedProvider, isNot(equals(initialProvider)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home grid card retries pending community estimate warm-up', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = GameInfo(
      name: 'Community Retry Grid',
      path: r'C:\Games\community_retry_grid',
      platform: Platform.steam,
      sizeBytes: 100 * _oneGiB,
      steamAppId: 440,
    );
    final bridge = _TestRustBridgeService(
      games: <GameInfo>[game],
      compressionEstimates: <CompressionEstimate>[
        CompressionEstimate(
          scannedFiles: 12,
          sampledBytes: game.sizeBytes,
          estimatedCompressedBytes: 90 * _oneGiB,
          estimatedSavedBytes: 10 * _oneGiB,
          estimatedSavingsRatio: 0.10,
          communityLookupPending: true,
        ),
        CompressionEstimate(
          scannedFiles: 0,
          sampledBytes: game.sizeBytes,
          estimatedCompressedBytes: 78 * _oneGiB,
          estimatedSavedBytes: 22 * _oneGiB,
          estimatedSavingsRatio: 0.22,
          baseSource: EstimateSource.communityDb,
          communitySamples: 20,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: HomeGameGrid()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    var card = tester.widget<GameCard>(find.byType(GameCard).first);
    expect(bridge.estimateCompressionSavingsCalls, 1);
    expect(card.estimatedSavedBytes, 10 * _oneGiB);
    expect(card.estimatedFromCommunity, isFalse);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    card = tester.widget<GameCard>(find.byType(GameCard).first);
    expect(bridge.estimateCompressionSavingsCalls, 2);
    expect(card.estimatedSavedBytes, 22 * _oneGiB);
    expect(card.estimatedFromCommunity, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home list view remove action uses injected bridge and clears selection',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Resident Evil Requiem',
        path: r'C:\Games\resident_evil_requiem',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
      );
      final bridge = _DeferredRemoveRustBridgeService(games: <GameInfo>[game]);
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: HomeGameListView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resident Evil Requiem'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove from Library'));
      await tester.pump();

      expect(bridge.removeGameFromDiscoveryCalls, 1);
      expect(bridge.lastRemovedGamePath, game.path);
      expect(container.read(selectedGameProvider), isNull);
      expect(container.read(gameListProvider).valueOrNull?.games, isEmpty);
      expect(find.text('Choose a game'), findsOneWidget);
      expect(find.text('Nothing matches this view'), findsOneWidget);

      bridge.completeRemoval();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Home list view remove action decompresses compressed games before removal',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Compressed Tool Folder',
        path: r'C:\Games\compressed_tool_folder',
        platform: Platform.application,
        sizeBytes: 16 * _oneGiB,
        compressedSize: 9 * _oneGiB,
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
            home: const Scaffold(body: HomeGameListView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compressed Tool Folder'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove from Library'));
      await tester.pumpAndSettle();

      expect(bridge.decompressCalls, 1);
      expect(bridge.removeGameFromDiscoveryCalls, 1);
      expect(bridge.lastRemovedGamePath, game.path);
      expect(container.read(selectedGameProvider), isNull);
      expect(container.read(gameListProvider).valueOrNull?.games, isEmpty);
    },
  );

  testWidgets(
    'Game details refresh same-URI cover art without rebuilding the info card',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Details Cover Refresh',
        path: r'C:\Games\details_cover_refresh',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
      );
      final coverService = _VersionedSameUriCoverArtService(
        coverUri: _sameUriCoverFixture('details-cover-refresh'),
      );
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(
            _TestRustBridgeService(games: <GameInfo>[game]),
          ),
          coverArtServiceProvider.overrideWithValue(coverService),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final initialInfoCard = tester.widget<Card>(
        find.byKey(const ValueKey<String>('detailsInfoCard')),
      );
      final initialCover = tester.widget<GameDetailsCover>(
        find.byType(GameDetailsCover),
      );
      final initialCoverResult = container
          .read(coverArtProvider(game.path))
          .valueOrNull;
      final initialCoverProvider = initialCover.coverProvider;
      expect(initialCoverResult?.revision, 1);
      expect(initialCoverProvider, isNotNull);

      coverService.rewriteCover(game.path);
      container.invalidate(coverArtProvider(game.path));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      final updatedCoverResult = container
          .read(coverArtProvider(game.path))
          .valueOrNull;
      final updatedInfoCard = tester.widget<Card>(
        find.byKey(const ValueKey<String>('detailsInfoCard')),
      );
      final updatedCover = tester.widget<GameDetailsCover>(
        find.byType(GameDetailsCover),
      );
      expect(updatedCoverResult?.revision, 2);
      expect(identical(updatedInfoCard, initialInfoCard), isTrue);
      expect(updatedCover.coverProvider, isNot(equals(initialCoverProvider)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home screen stays stable at very narrow width in list mode', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final persistence = _InMemorySettingsPersistence();
    await persistence.save(const AppSettings(homeViewMode: HomeViewMode.list));
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
        child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Go to Settings'), findsNothing);
    expect(find.text('Choose a game'), findsOneWidget);

    await tester.ensureVisible(find.text('Pixel Raider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pixel Raider'));
    await tester.pumpAndSettle();

    expect(find.text('Status'), findsOneWidget);
  });

  testWidgets(
    'Home grid mode keeps breathing room between overview and first card',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
          child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final overviewRect = tester.getRect(
        find.byKey(const ValueKey<String>('homeOverviewPanelShell')),
      );
      final firstCardRect = tester.getRect(find.byType(GameCard).first);

      expect(firstCardRect.top, greaterThan(overviewRect.bottom + 8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home list mode keeps breathing room between overview and first row',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final persistence = _InMemorySettingsPersistence();
      await persistence.save(
        const AppSettings(homeViewMode: HomeViewMode.list),
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
          child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final overviewRect = tester.getRect(
        find.byKey(const ValueKey<String>('homeOverviewPanelShell')),
      );
      final firstRowFinder = find.ancestor(
        of: find.text('Pixel Raider'),
        matching: find.byType(InkWell),
      );
      final firstRowRect = tester.getRect(firstRowFinder.first);

      expect(firstRowRect.top, greaterThan(overviewRect.bottom + 8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home list mode uses the compact overview shell to keep split content higher',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final persistence = _InMemorySettingsPersistence();
      await persistence.save(
        const AppSettings(homeViewMode: HomeViewMode.list),
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
          child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('homeOverviewCompactLead')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('homeOverviewCompactTrailing')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('Rust bridge provider resolves to singleton instance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final a = container.read(rustBridgeServiceProvider);
    final b = container.read(rustBridgeServiceProvider);
    expect(identical(a, b), isTrue);
    expect(identical(a, RustBridgeService.instance), isTrue);
  });

  testWidgets('GameCard cover image uses contain fit to avoid cropping', (
    WidgetTester tester,
  ) async {
    // Use a MemoryImage so the test does not depend on network/file I/O.
    final testProvider = MemoryImage(
      Uint8List.fromList(
        // 1x1 transparent PNG
        [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          0,
          0,
          0,
          13,
          73,
          72,
          68,
          82,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          1,
          8,
          6,
          0,
          0,
          0,
          31,
          21,
          196,
          137,
          0,
          0,
          0,
          10,
          73,
          68,
          65,
          84,
          120,
          156,
          98,
          0,
          0,
          0,
          2,
          0,
          1,
          226,
          33,
          188,
          51,
          0,
          0,
          0,
          0,
          73,
          69,
          78,
          68,
          174,
          66,
          96,
          130,
        ],
      ),
    );
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
    expect(image.fit, BoxFit.contain);
    expect(image.isAntiAlias, isTrue);
    expect(image.filterQuality, FilterQuality.low);
  });

  testWidgets('GameCard renders metadata above a bottom cover panel', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 420,
            child: GameCard(
              gameName: 'Flipped Card',
              platform: Platform.steam,
              totalSizeBytes: 10 * _oneGiB,
              assumeBoundedHeight: true,
            ),
          ),
        ),
      ),
    );

    final infoPanelFinder = find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) {
        return false;
      }
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color == AppColors.nightDune.withValues(alpha: 0.58) &&
          decoration.borderRadius ==
              const BorderRadius.vertical(top: Radius.circular(12));
    });
    final coverFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ClipRRect &&
          widget.borderRadius ==
              const BorderRadius.vertical(bottom: Radius.circular(12)),
    );

    expect(infoPanelFinder, findsOneWidget);
    expect(coverFinder, findsOneWidget);
    expect(
      find.descendant(of: infoPanelFinder, matching: find.text('Flipped Card')),
      findsOneWidget,
    );

    final titleRect = tester.getRect(find.text('Flipped Card'));
    final coverRect = tester.getRect(coverFinder);
    expect(titleRect.top, lessThan(coverRect.top));
    expect(coverRect.height, greaterThan(305));
    expect(tester.takeException(), isNull);
  });

  testWidgets('GameCard renders last compressed metadata when provided', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 420,
            child: GameCard(
              gameName: 'Last Compressed Test',
              platform: Platform.steam,
              totalSizeBytes: 10 * _oneGiB,
              compressedSizeBytes: 8 * _oneGiB,
              isCompressed: true,
              lastCompressedText: 'Mar 4, 16:05',
              assumeBoundedHeight: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mar 4, 16:05'), findsOneWidget);
  });

  testWidgets('GameCard keeps last compressed inline at narrow widths', (
    WidgetTester tester,
  ) async {
    final totalBytes = (11.1 * 1024 * 1024 * 1024).toInt();
    final compressedBytes = (10.1 * 1024 * 1024 * 1024).toInt();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 420,
            child: GameCard(
              gameName: 'Cairn',
              platform: Platform.steam,
              totalSizeBytes: totalBytes,
              compressedSizeBytes: compressedBytes,
              isCompressed: true,
              lastCompressedText: 'Mar 6, 21:19',
              assumeBoundedHeight: true,
            ),
          ),
        ),
      ),
    );

    final sizeRect = tester.getRect(find.text('10.1 GB'));
    final timestampRect = tester.getRect(find.text('Mar 6, 21:19'));
    final cardRect = tester.getRect(find.byType(GameCard));

    expect(timestampRect.top, lessThan(sizeRect.bottom));
    expect(timestampRect.bottom, greaterThan(sizeRect.top));
    expect(timestampRect.right, lessThanOrEqualTo(cardRect.right - 8));
  });

  testWidgets('GameCard keeps badge row aligned across card states', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 280,
                height: 420,
                child: GameCard(
                  gameName: 'Compressed Card',
                  platform: Platform.steam,
                  totalSizeBytes: 58 * _oneGiB,
                  compressedSizeBytes: 53 * _oneGiB,
                  isCompressed: true,
                  lastCompressedText: 'Feb 16, 17:36',
                  assumeBoundedHeight: true,
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 280,
                height: 420,
                child: const GameCard(
                  gameName: 'DirectStorage Card',
                  platform: Platform.steam,
                  totalSizeBytes: 1 * _oneGiB,
                  isDirectStorage: true,
                  assumeBoundedHeight: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final compressedBadge = tester.getRect(find.textContaining('Saved'));
    final directStorageBadge = tester.getRect(find.text('DirectStorage'));

    expect(compressedBadge.top, directStorageBadge.top);
    expect(compressedBadge.height, directStorageBadge.height);
  });

  testWidgets(
    'Game details compress action honors DirectStorage override setting',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Details DS Override',
        path: r'C:\Games\details_ds_override',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
        isDirectStorage: true,
      );
      final bridge = _TestRustBridgeService(games: <GameInfo>[game]);
      final persistence = _InMemorySettingsPersistence();
      await persistence.save(
        const AppSettings(directStorageOverrideEnabled: true),
      );
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

      final primaryAction = find.byKey(
        const ValueKey<String>('detailsStatusPrimaryAction'),
      );
      await tester.ensureVisible(primaryAction);
      await tester.tap(primaryAction);
      await tester.pump();

      expect(bridge.compressCalls, 1);
      expect(bridge.lastAllowDirectStorageOverride, isTrue);
    },
  );

  testWidgets(
    'Game details disable recompress for compressed DirectStorage games while keeping decompression available',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Details DS Recompress Guard',
        path: r'C:\Games\details_ds_recompress_guard',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
        compressedSize: 72 * _oneGiB,
        isCompressed: true,
        isDirectStorage: true,
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

      final primaryAction = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('detailsStatusPrimaryAction')),
      );
      final decompressAction = find.byKey(
        const ValueKey<String>('detailsStatusDecompressAction'),
      );

      expect(find.text('Recompress'), findsOneWidget);
      expect(find.text('Decompress'), findsOneWidget);
      expect(primaryAction.onPressed, isNull);

      await tester.tap(decompressAction);
      await tester.pumpAndSettle();

      expect(bridge.compressCalls, 0);
      expect(bridge.decompressCalls, 1);
    },
  );

  testWidgets(
    'Game details compress action allows unsupported games without DirectStorage override',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Details Unsupported Compression',
        path: r'C:\Games\details_unsupported_compression',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
        isUnsupported: true,
      );
      final bridge = _TestRustBridgeService(games: <GameInfo>[game]);
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(bridge),
          settingsPersistenceProvider.overrideWithValue(
            _InMemorySettingsPersistence(),
          ),
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

      final primaryAction = find.byKey(
        const ValueKey<String>('detailsStatusPrimaryAction'),
      );
      await tester.ensureVisible(primaryAction);
      await tester.tap(primaryAction);
      await tester.pump();

      expect(bridge.compressCalls, 1);
      expect(bridge.lastAllowDirectStorageOverride, isFalse);
    },
  );

  testWidgets('Game details can mark and unmark unsupported state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = GameInfo(
      name: 'Details Unsupported Toggle',
      path: r'C:\Games\details_unsupported_toggle',
      platform: Platform.steam,
      sizeBytes: 96 * _oneGiB,
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

    final unsupportedAction = find.byKey(
      const ValueKey<String>('detailsStatusUnsupportedAction'),
    );
    await tester.ensureVisible(unsupportedAction);
    expect(find.byTooltip('Mark as Unsupported'), findsOneWidget);

    await tester.tap(unsupportedAction);
    await tester.pumpAndSettle();

    expect(bridge.reportUnsupportedGameCalls, 1);
    expect(bridge.lastReportedUnsupportedGamePath, game.path);
    expect(
      container.read(gameListProvider).valueOrNull?.games.first.isUnsupported,
      isTrue,
    );
    expect(find.byTooltip('Mark as Supported'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('detailsStatusUnsupportedAction')),
    );
    await tester.pumpAndSettle();

    expect(bridge.unreportUnsupportedGameCalls, 1);
    expect(bridge.lastUnreportedUnsupportedGamePath, game.path);
    expect(
      container.read(gameListProvider).valueOrNull?.games.first.isUnsupported,
      isFalse,
    );
    expect(find.byTooltip('Mark as Unsupported'), findsOneWidget);
  });

  testWidgets('Game details unsupported toggle only rebuilds status metadata', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = GameInfo(
      name: 'Details Unsupported Media Stability',
      path: r'C:\Games\details_unsupported_media_stability',
      platform: Platform.steam,
      sizeBytes: 96 * _oneGiB,
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

    final unsupportedAction = find.byKey(
      const ValueKey<String>('detailsStatusUnsupportedAction'),
    );
    await tester.ensureVisible(unsupportedAction);
    await tester.tap(unsupportedAction);
    await tester.pumpAndSettle();

    final updatedCover = tester.widget<GameDetailsCover>(
      find.byType(GameDetailsCover),
    );

    expect(identical(updatedCover, initialCover), isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('detailsHeaderStatusBadge')),
        matching: find.text('Unsupported'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Mark as Supported'), findsOneWidget);
  });

  testWidgets(
    'Game details remove action updates immediately before async persistence completes',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Details Remove Async',
        path: r'C:\Games\details_remove_async',
        platform: Platform.steam,
        sizeBytes: 96 * _oneGiB,
      );
      final bridge = _DeferredRemoveRustBridgeService(games: <GameInfo>[game]);
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

      await tester.tap(find.byTooltip('Remove from Library'));
      await tester.pump();

      expect(bridge.removeGameFromDiscoveryCalls, 1);
      expect(bridge.lastRemovedGamePath, game.path);
      expect(container.read(selectedGameProvider), isNull);
      expect(container.read(gameListProvider).valueOrNull?.games, isEmpty);
      expect(find.text('Game not found.'), findsOneWidget);

      bridge.completeRemoval();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Game details remove action decompresses compressed games before removal',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final game = GameInfo(
        name: 'Details Compressed Remove',
        path: r'C:\Games\details_compressed_remove',
        platform: Platform.application,
        sizeBytes: 18 * _oneGiB,
        compressedSize: 11 * _oneGiB,
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

      await tester.tap(find.byTooltip('Remove from Library'));
      await tester.pumpAndSettle();

      expect(bridge.decompressCalls, 1);
      expect(bridge.removeGameFromDiscoveryCalls, 1);
      expect(bridge.lastRemovedGamePath, game.path);
      expect(container.read(selectedGameProvider), isNull);
      expect(container.read(gameListProvider).valueOrNull?.games, isEmpty);
      expect(find.text('Game not found.'), findsOneWidget);
    },
  );

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
