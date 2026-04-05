import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compact_games/core/theme/app_colors.dart';
import 'package:compact_games/core/widgets/status_badge.dart';
import 'package:compact_games/features/games/presentation/widgets/inventory_components.dart';
import 'package:compact_games/models/game_info.dart';

void main() {
  testWidgets('Inventory search and sort controls share width on wide layout', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: InventoryToolbar(
              searchController: controller,
              sortField: InventorySortField.name,
              descending: true,
              onSearchChanged: (_) {},
              onSortChanged: (_) {},
              onToggleSortDirection: () {},
            ),
          ),
        ),
      ),
    );

    final searchSize = tester.getSize(
      find.byKey(const ValueKey<String>('inventorySearchField')),
    );
    final sortSize = tester.getSize(
      find.byKey(const ValueKey<String>('inventorySortField')),
    );
    final sortDecoratorSize = tester.getSize(
      find.byKey(const ValueKey<String>('inventorySortDecorator')),
    );
    final searchRect = tester.getRect(
      find.byKey(const ValueKey<String>('inventorySearchField')),
    );
    final sortRect = tester.getRect(
      find.byKey(const ValueKey<String>('inventorySortField')),
    );
    final directionRect = tester.getRect(
      find.byKey(const ValueKey<String>('inventorySortDirectionButton')),
    );

    expect((searchSize.width - sortSize.width).abs(), lessThan(1.0));
    expect((sortSize.width - sortDecoratorSize.width).abs(), lessThan(1.0));
    expect((searchSize.height - sortDecoratorSize.height).abs(), lessThan(1.0));
    expect((searchRect.bottom - sortRect.bottom).abs(), lessThan(1.0));
    expect((sortRect.bottom - directionRect.bottom).abs(), lessThan(1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inventory sort menu opens as horizontal one-line options', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    InventorySortField? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: InventoryToolbar(
              searchController: controller,
              sortField: InventorySortField.savingsPercent,
              descending: true,
              onSearchChanged: (_) {},
              onSortChanged: (value) => selected = value,
              onToggleSortDirection: () {},
            ),
          ),
        ),
      ),
    );

    final sortFieldFinder = find.byKey(
      const ValueKey<String>('inventorySortField'),
    );
    final sortFieldSize = tester.getSize(sortFieldFinder);

    await tester.tap(sortFieldFinder);
    await tester.pumpAndSettle();

    final menuRowFinder = find.byKey(
      const ValueKey<String>('inventorySortMenuRow'),
    );
    expect(menuRowFinder, findsOneWidget);
    final menuRowSize = tester.getSize(menuRowFinder);
    expect(menuRowSize.width, greaterThan(sortFieldSize.width * 0.85));
    expect(
      (menuRowSize.height - sortFieldSize.height).abs(),
      lessThanOrEqualTo(1),
    );

    await tester.tap(find.text('Platform'));
    await tester.pumpAndSettle();

    expect(selected, InventorySortField.platform);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inventory sort field supports keyboard activation', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: InventoryToolbar(
              searchController: controller,
              sortField: InventorySortField.savingsPercent,
              descending: true,
              onSearchChanged: (_) {},
              onSortChanged: (_) {},
              onToggleSortDirection: () {},
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('inventorySortMenuRow')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Inventory header right-aligns last checked and keeps clear spacing from savings',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 1200, child: InventoryHeader())),
        ),
      );

      final savingsHeader = tester.widget<Text>(find.text('SAVINGS'));
      final lastCheckedHeader = tester.widget<Text>(find.text('LAST CHECKED'));
      final savingsRect = tester.getRect(find.text('SAVINGS'));
      final lastCheckedRect = tester.getRect(find.text('LAST CHECKED'));

      expect(savingsHeader.textAlign, TextAlign.right);
      expect(lastCheckedHeader.textAlign, TextAlign.right);
      expect(lastCheckedRect.left - savingsRect.right, greaterThan(16));
    },
  );

  testWidgets(
    'Inventory sort menu remains stable under constrained width and rapid interactions',
    (WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var selected = InventorySortField.savingsPercent;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 560,
              child: InventoryToolbar(
                searchController: controller,
                sortField: selected,
                descending: true,
                onSearchChanged: (_) {},
                onSortChanged: (value) => selected = value,
                onToggleSortDirection: () {},
              ),
            ),
          ),
        ),
      );

      final sortFieldFinder = find.byKey(
        const ValueKey<String>('inventorySortField'),
      );
      final sortFieldSize = tester.getSize(sortFieldFinder);
      const selections = <String>['Name', 'Platform', 'Original size'];

      for (final label in selections) {
        await tester.tap(sortFieldFinder);
        await tester.pumpAndSettle();

        final menuRowFinder = find.byKey(
          const ValueKey<String>('inventorySortMenuRow'),
        );
        expect(menuRowFinder, findsOneWidget);
        final menuRowSize = tester.getSize(menuRowFinder);
        expect(menuRowSize.width, greaterThan(sortFieldSize.width * 0.85));
        expect(
          (menuRowSize.height - sortFieldSize.height).abs(),
          lessThanOrEqualTo(1),
        );

        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(selected, InventorySortField.originalSize);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Inventory status row uses explicit action buttons and aligned full-rescan action',
    (WidgetTester tester) async {
      bool? watcherToggleValue;
      bool? advancedToggleValue;
      var fullRescanPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: InventoryStatusRow(
                algorithmLabel: 'XPRESS 8K (Balanced)',
                watcherActive: false,
                watcherEnabled: false,
                advancedEnabled: true,
                onWatcherEnabledChanged: (value) => watcherToggleValue = value,
                onAdvancedChanged: (value) => advancedToggleValue = value,
                onRunFullRescan: () => fullRescanPressed = true,
                canRunFullRescan: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Algorithm: XPRESS 8K (Balanced)'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Algorithm: XPRESS 8K (Balanced)'),
          matching: find.byType(ButtonStyleButton),
        ),
        findsNothing,
      );
      final algorithmBadge = tester.widget<StatusBadge>(
        find.byKey(const ValueKey<String>('inventoryAlgorithmBadge')),
      );
      expect(algorithmBadge.label, contains('Algorithm'));
      expect(algorithmBadge.color, AppColors.info);

      await tester.tap(
        find.byKey(const ValueKey<String>('inventoryWatcherToggleButton')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('inventoryAdvancedScanToggleButton')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('inventoryFullRescanButton')),
      );
      await tester.pumpAndSettle();

      expect(watcherToggleValue, isTrue);
      expect(advancedToggleValue, isFalse);
      expect(fullRescanPressed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Inventory status row renders active watcher as status tokens plus emphasized action',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: InventoryStatusRow(
                algorithmLabel: 'XPRESS 8K (Balanced)',
                watcherActive: true,
                watcherEnabled: true,
                advancedEnabled: false,
                onWatcherEnabledChanged: (_) {},
                onAdvancedChanged: (_) {},
                onRunFullRescan: () {},
              ),
            ),
          ),
        ),
      );

      final watcherBadge = tester.widget<StatusBadge>(
        find.byKey(const ValueKey<String>('inventoryWatcherBadge')),
      );
      expect(watcherBadge.label, contains('Watcher'));
      expect(watcherBadge.color, AppColors.success);

      final watcherButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey<String>('inventoryWatcherToggleButton')),
      );
      final borderSide = watcherButton.style?.side?.resolve(<WidgetState>{});
      final background = watcherButton.style?.backgroundColor?.resolve(
        <WidgetState>{},
      );

      expect(borderSide?.color, AppColors.richGold.withValues(alpha: 0.85));
      expect(borderSide?.width, greaterThan(1.5));
      expect(background, AppColors.richGold.withValues(alpha: 0.08));
      expect(find.textContaining('Interactive controls'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Inventory row keeps static striping, right-aligns numeric values, and supports keyboard activation',
    (WidgetTester tester) async {
      var opened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              child: InventoryRow(
                game: GameInfo(
                  name: 'Keyboard Row',
                  path: r'C:\Games\keyboard_row',
                  platform: Platform.steam,
                  sizeBytes: 12 * 1024 * 1024 * 1024,
                  compressedSize: 8 * 1024 * 1024 * 1024,
                  isCompressed: true,
                ),
                watcherLabel: 'Watching',
                lastCheckedLabel: '01:10',
                isStriped: true,
                onOpenDetails: () => opened = true,
              ),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(InventoryRow),
          matching: find.byType(RepaintBoundary),
        ),
        findsNothing,
      );
      final rowSurfaceFinder = find.descendant(
        of: find.byType(InventoryRow),
        matching: find.byType(InkWell),
      );
      expect(rowSurfaceFinder, findsOneWidget);
      expect(
        find.descendant(
          of: rowSurfaceFinder,
          matching: find.byType(ValueListenableBuilder<bool>),
        ),
        findsNothing,
      );
      final rowInk = tester.widget<Ink>(
        find.ancestor(of: rowSurfaceFinder, matching: find.byType(Ink)),
      );
      final rowDecoration = rowInk.decoration as BoxDecoration;
      expect(
        rowDecoration.color,
        AppColors.surfaceVariant.withValues(alpha: 0.28),
      );

      final originalText = tester.widget<Text>(find.text('12.0 GB'));
      final currentText = tester.widget<Text>(find.text('8.0 GB'));
      final savingsText = tester.widget<Text>(find.text('33.3%'));
      final lastCheckedText = tester.widget<Text>(find.text('01:10'));
      final savingsRect = tester.getRect(find.text('33.3%'));
      final lastCheckedRect = tester.getRect(find.text('01:10'));
      expect(originalText.textAlign, TextAlign.right);
      expect(currentText.textAlign, TextAlign.right);
      expect(savingsText.textAlign, TextAlign.right);
      expect(lastCheckedText.textAlign, TextAlign.right);
      expect(savingsText.style?.color, AppColors.richGold);
      expect(lastCheckedRect.left - savingsRect.right, greaterThan(12));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(opened, isTrue);
    },
  );

  testWidgets(
    'Inventory savings percentages use subdued, neutral, and highlighted colors by threshold',
    (WidgetTester tester) async {
      const oneGiB = 1024 * 1024 * 1024;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                InventoryRow(
                  game: GameInfo(
                    name: 'Zero Savings',
                    path: r'C:\Games\zero_savings',
                    platform: Platform.steam,
                    sizeBytes: 10 * oneGiB,
                    compressedSize: 10 * oneGiB,
                    isCompressed: true,
                  ),
                  watcherLabel: 'Watched',
                  lastCheckedLabel: 'Today',
                  onOpenDetails: () {},
                ),
                InventoryRow(
                  game: GameInfo(
                    name: 'Minor Savings',
                    path: r'C:\Games\minor_savings',
                    platform: Platform.steam,
                    sizeBytes: 10 * oneGiB,
                    compressedSize: (9.6 * oneGiB).round(),
                    isCompressed: true,
                  ),
                  watcherLabel: 'Watched',
                  lastCheckedLabel: 'Today',
                  onOpenDetails: () {},
                ),
                InventoryRow(
                  game: GameInfo(
                    name: 'Big Savings',
                    path: r'C:\Games\big_savings',
                    platform: Platform.steam,
                    sizeBytes: 10 * oneGiB,
                    compressedSize: (8.5 * oneGiB).round(),
                    isCompressed: true,
                  ),
                  watcherLabel: 'Watched',
                  lastCheckedLabel: 'Today',
                  onOpenDetails: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final zeroSavings = tester.widget<Text>(find.text('0.0%'));
      final minorSavings = tester.widget<Text>(find.text('4.0%'));
      final bigSavings = tester.widget<Text>(find.text('15.0%'));

      expect(zeroSavings.style?.color, AppColors.textMuted);
      expect(minorSavings.style?.color, AppColors.textPrimary);
      expect(bigSavings.style?.color, AppColors.richGold);
      expect(bigSavings.style?.fontWeight, FontWeight.w700);
    },
  );
}
