part of '../widget_test.dart';

void _registerProgressIndicatorWidgetTests() {
  testWidgets('Compression progress display clamps processed above total', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompressionProgressIndicator(
            activity: CompressionActivityUiModel(
              type: CompressionJobType.compression,
              gameName: 'Clamp Test',
              filesProcessed: 1000,
              filesTotal: 1000,
              percent: 100,
              bytesDelta: 0,
              hasKnownFileTotal: true,
              isFileCountApproximate: false,
              canCancel: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('1000/1000 files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compression progress shows preparing state before totals', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompressionProgressIndicator(
            activity: CompressionActivityUiModel(
              type: CompressionJobType.compression,
              gameName: 'Prep Test',
              filesProcessed: 0,
              filesTotal: 0,
              percent: 0,
              bytesDelta: 0,
              hasKnownFileTotal: false,
              isFileCountApproximate: false,
              canCancel: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.text('Scanning files...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Activity header uses a static operation icon instead of spinner',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompressionProgressIndicator(
              activity: CompressionActivityUiModel(
                type: CompressionJobType.compression,
                gameName: 'Static Icon Test',
                filesProcessed: 12,
                filesTotal: 100,
                percent: 12,
                bytesDelta: 64 * 1024 * 1024,
                hasKnownFileTotal: true,
                isFileCountApproximate: false,
                canCancel: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      final icons = tester.widgetList<Icon>(find.byType(Icon));
      expect(icons.any((icon) => icon.icon == LucideIcons.archive), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Compression progress marks bucketed file counts as approximate',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompressionProgressIndicator(
              activity: CompressionActivityUiModel(
                type: CompressionJobType.compression,
                gameName: 'Approximate File Count Test',
                filesProcessed: 100,
                filesTotal: 1000,
                percent: 10,
                bytesDelta: 512 * 1024 * 1024,
                hasKnownFileTotal: true,
                isFileCountApproximate: true,
                canCancel: true,
                etaSeconds: 60,
              ),
            ),
          ),
        ),
      );

      expect(find.text('~100/1000 files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Compression progress neutralizes inherited text decoration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTextStyle.merge(
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: Colors.green,
          ),
          child: Scaffold(
            body: CompressionProgressIndicator(
              activity: CompressionActivityUiModel(
                type: CompressionJobType.compression,
                gameName: 'Decoration Reset Test',
                filesProcessed: 100,
                filesTotal: 1000,
                percent: 10,
                bytesDelta: 512 * 1024 * 1024,
                hasKnownFileTotal: true,
                isFileCountApproximate: true,
                canCancel: true,
                etaSeconds: 60,
              ),
            ),
          ),
        ),
      ),
    );

    final richTexts = tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(CompressionProgressIndicator),
        matching: find.byType(RichText),
      ),
    );
    final statusText = richTexts.firstWhere(
      (widget) => widget.text.toPlainText() == 'Compressing',
    );
    final titleText = richTexts.firstWhere(
      (widget) => widget.text.toPlainText() == 'Decoration Reset Test',
    );

    expect(statusText.text.style?.decoration, isNot(TextDecoration.underline));
    expect(titleText.text.style?.decoration, isNot(TextDecoration.underline));
    expect(tester.takeException(), isNull);
  });

  test(
    'Active compression UI model buckets large-job progress and ETA updates',
    () async {
      final bridge = _DelayedActivityRustBridgeService(games: _sampleGames);
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(() {
        bridge.disposeStreams();
        container.dispose();
      });

      final snapshots = <CompressionActivityUiModel?>[];
      final subscription = container.listen<CompressionActivityUiModel?>(
        activeCompressionUiModelProvider,
        (_, next) => snapshots.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await container
          .read(compressionProvider.notifier)
          .startCompression(
            gamePath: _sampleGames.first.path,
            gameName: _sampleGames.first.name,
          );
      await Future<void>.delayed(Duration.zero);

      bridge.emitCompressionProgress(
        gameName: _sampleGames.first.name,
        filesProcessed: 101,
        filesTotal: 1000,
        bytesOriginal: 400 * 1024 * 1024,
        bytesCompressed: 200 * 1024 * 1024,
        estimatedTimeRemaining: const Duration(seconds: 62),
      );
      await Future<void>.delayed(Duration.zero);

      final firstBucketed = container.read(activeCompressionUiModelProvider);
      expect(firstBucketed, isNotNull);
      expect(firstBucketed!.filesProcessed, 100);
      expect(firstBucketed.isFileCountApproximate, isTrue);
      expect(firstBucketed.percent, 10);
      expect(firstBucketed.bytesDelta, 192 * 1024 * 1024);
      expect(firstBucketed.etaSeconds, 60);

      final snapshotCountAfterFirstBucket = snapshots.length;

      bridge.emitCompressionProgress(
        gameName: _sampleGames.first.name,
        filesProcessed: 109,
        filesTotal: 1000,
        bytesOriginal: 406 * 1024 * 1024,
        bytesCompressed: 200 * 1024 * 1024,
        estimatedTimeRemaining: const Duration(seconds: 61),
      );
      await Future<void>.delayed(Duration.zero);

      expect(snapshots.length, snapshotCountAfterFirstBucket);

      bridge.emitCompressionProgress(
        gameName: _sampleGames.first.name,
        filesProcessed: 126,
        filesTotal: 1000,
        bytesOriginal: 450 * 1024 * 1024,
        bytesCompressed: 224 * 1024 * 1024,
        estimatedTimeRemaining: const Duration(seconds: 54),
      );
      await Future<void>.delayed(Duration.zero);

      final secondBucketed = container.read(activeCompressionUiModelProvider);
      expect(secondBucketed, isNotNull);
      expect(secondBucketed!.filesProcessed, 125);
      expect(secondBucketed.isFileCountApproximate, isTrue);
      expect(secondBucketed.percent, 13);
      expect(secondBucketed.bytesDelta, 224 * 1024 * 1024);
      expect(secondBucketed.etaSeconds, 50);
      expect(snapshots.length, greaterThan(snapshotCountAfterFirstBucket));
    },
  );

  test(
    'Floating activity visibility follows route, dismissal, and run state',
    () async {
      final bridge = _DelayedActivityRustBridgeService(games: _sampleGames);
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(bridge),
          isHomeRouteProvider.overrideWith((ref) => false),
        ],
      );
      addTearDown(() {
        bridge.disposeStreams();
        container.dispose();
      });

      expect(container.read(showFloatingActivityOverlayProvider), isFalse);

      await container
          .read(compressionProvider.notifier)
          .startCompression(
            gamePath: _sampleGames.first.path,
            gameName: _sampleGames.first.name,
          );
      await Future<void>.delayed(Duration.zero);

      final firstRunId = container.read(activeCompressionRunIdProvider);
      expect(firstRunId, isNotNull);
      expect(container.read(showFloatingActivityOverlayProvider), isTrue);

      container.read(dismissedFloatingActivityRunIdProvider.notifier).state =
          firstRunId;
      await Future<void>.delayed(Duration.zero);

      expect(container.read(showFloatingActivityOverlayProvider), isFalse);

      bridge.finishCompression();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(showFloatingActivityOverlayProvider), isFalse);
    },
  );

  testWidgets(
    'Compact decompression activity stays overflow-free on narrow widths',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: CompressionProgressIndicator(
                  compact: true,
                  activity: CompressionActivityUiModel(
                    type: CompressionJobType.decompression,
                    gameName: 'Narrow Decompression Test',
                    filesProcessed: 48,
                    filesTotal: 120,
                    percent: 40,
                    bytesDelta: 512 * 1024 * 1024,
                    hasKnownFileTotal: true,
                    isFileCountApproximate: false,
                    canCancel: true,
                    etaSeconds: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Decompressing'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home activity banner stays stable through narrow resize during decompression',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      final game = GameInfo(
        name: 'Home Resize Decompression',
        path: r'C:\Games\home_resize_decompression',
        platform: Platform.steam,
        sizeBytes: 58 * _oneGiB,
        compressedSize: 53 * _oneGiB,
        isCompressed: true,
      );
      final bridge = _DelayedActivityRustBridgeService(games: <GameInfo>[game]);
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(() async {
        bridge.disposeStreams();
        container.dispose();
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(compressionProvider.notifier)
          .startDecompression(gamePath: game.path, gameName: game.name);
      await tester.pump();

      final inlineHost = find.byKey(compressionInlineActivityHostKey);
      expect(inlineHost, findsOneWidget);
      expect(
        find.descendant(of: inlineHost, matching: find.text('Decompressing')),
        findsOneWidget,
      );

      await tester.binding.setSurfaceSize(const Size(640, 900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(inlineHost, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
