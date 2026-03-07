import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/core/performance/perf_overlay.dart';

void main() {
  testWidgets('F12 overlay toggle works without Directionality crashes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const PerfOverlayManager(
        child: SizedBox.expand(),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
    await tester.pump();

    expect(find.textContaining('FPS:'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('F12 overlay toggle still works when a descendant has focus', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const PerfOverlayManager(
        child: MaterialApp(
          home: Scaffold(
            body: TextField(autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
    await tester.pump();

    expect(find.textContaining('FPS:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Shift+F12 toggles Flutter performance overlay with descendant focus',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const PerfOverlayManager(
          child: MaterialApp(
            home: Scaffold(
              body: TextField(autofocus: true),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PerformanceOverlay), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(find.byType(PerformanceOverlay), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(find.byType(PerformanceOverlay), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
