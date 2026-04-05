import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compact_games/core/theme/app_colors.dart';
import 'package:compact_games/core/widgets/desktop_window_frame.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets('Desktop window frame title bar stays lightweight', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DesktopWindowFrame(child: SizedBox.expand())),
    );

    expect(find.byType(DragToMoveArea), findsOneWidget);
    expect(find.byType(WindowCaptionButton), findsNWidgets(3));
    expect(find.byType(FutureBuilder<dynamic>), findsNothing);
    expect(find.text('Compact Games'), findsNothing);

    final titleBarDecoratedBox = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('desktopWindowTitleBarDecoration')),
    );
    final titleBarDecoration = titleBarDecoratedBox.decoration as BoxDecoration;
    expect(titleBarDecoration.gradient, isNull);
    expect(titleBarDecoration.color, AppColors.surfaceElevated);

    expect(tester.takeException(), isNull);
  });
}
