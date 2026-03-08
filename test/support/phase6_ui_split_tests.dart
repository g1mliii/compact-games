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
      find.textContaining('SteamGridDB API key'),
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
    final detailHintRect = tester.getRect(
      find.text('Select a game to view details'),
    );
    expect(detailHintRect.top, greaterThan(listRowRect.bottom));

    await tester.tap(find.text('Pixel Raider'));
    await tester.pumpAndSettle();

    expect(find.text('STATUS'), findsOneWidget);
    final statusRect = tester.getRect(find.text('STATUS'));
    expect(statusRect.top, greaterThan(listRowRect.bottom));
  });

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
    expect(find.text('Go to Settings'), findsOneWidget);
    expect(find.text('Select a game to view details'), findsOneWidget);

    await tester.tap(find.text('Pixel Raider'));
    await tester.pumpAndSettle();

    expect(find.text('STATUS'), findsOneWidget);
  });

  testWidgets(
    'Settings inventory layout keeps spacing and avoids overly wide controls',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

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

      final firstCardRect = tester.getRect(find.byType(Card).first);
      expect(firstCardRect.width, lessThan(1000));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
      await tester.pumpAndSettle();

      final bannerRect = tester.getRect(
        find.byKey(const ValueKey<String>('settingsWatcherStatusBanner')),
      );
      final watcherButtonRect = tester.getRect(
        find.byKey(const ValueKey<String>('settingsWatcherToggleButton')),
      );

      expect(watcherButtonRect.width, lessThan(bannerRect.width));
      expect(
        watcherButtonRect.top - bannerRect.bottom,
        greaterThanOrEqualTo(8),
      );
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

    final compressedBadge = tester.getRect(find.byType(StatusBadge).at(0));
    final directStorageBadge = tester.getRect(find.byType(StatusBadge).at(1));

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
    expect(find.text('Mark as Unsupported'), findsOneWidget);

    await tester.tap(unsupportedAction);
    await tester.pumpAndSettle();

    expect(bridge.reportUnsupportedGameCalls, 1);
    expect(bridge.lastReportedUnsupportedGamePath, game.path);
    expect(
      container.read(gameListProvider).valueOrNull?.games.first.isUnsupported,
      isTrue,
    );
    expect(find.text('Mark as Supported'), findsOneWidget);

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
    expect(find.text('Mark as Unsupported'), findsOneWidget);
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
