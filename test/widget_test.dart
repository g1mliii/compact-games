import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/app.dart';
import 'package:pressplay/core/widgets/status_badge.dart';
import 'package:pressplay/features/games/presentation/component_test_screen.dart';
import 'package:pressplay/features/games/presentation/widgets/compression_progress_indicator.dart';
import 'package:pressplay/features/games/presentation/widgets/game_card.dart';

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PressPlayApp());
    expect(find.text('PressPlay'), findsOneWidget);
    expect(find.text('Game grid coming soon'), findsOneWidget);
  });

  testWidgets('Section 2.2 components render in test screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ComponentTestScreen())),
    );

    expect(find.text('Component Test Screen'), findsOneWidget);
    expect(find.byType(GameCard), findsNWidgets(3));
    expect(find.byType(CompressionProgressIndicator), findsOneWidget);
    expect(find.byType(StatusBadge), findsAtLeastNWidgets(3));
  });
}
