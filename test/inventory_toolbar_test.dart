import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/features/games/presentation/widgets/inventory_components.dart';

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

    expect((searchSize.width - sortSize.width).abs(), lessThan(1.0));
    expect((sortSize.width - sortDecoratorSize.width).abs(), lessThan(1.0));
    expect((searchSize.height - sortDecoratorSize.height).abs(), lessThan(1.0));
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

    await tester.tap(find.text('Platform'));
    await tester.pumpAndSettle();

    expect(selected, InventorySortField.platform);
    expect(tester.takeException(), isNull);
  });

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
}
