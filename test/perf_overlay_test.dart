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
}
