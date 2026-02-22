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
}
