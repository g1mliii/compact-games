part of '../widget_test.dart';

void _registerProgressIndicatorWidgetTests() {
  testWidgets('Compression progress display clamps processed above total', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompressionProgressIndicator(
            gameName: 'Clamp Test',
            filesProcessed: 1000,
            filesTotal: 100,
            bytesSaved: 0,
          ),
        ),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('1000 / 1000 files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compression progress shows preparing state before totals', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompressionProgressIndicator(
            gameName: 'Prep Test',
            filesProcessed: 0,
            filesTotal: 0,
            bytesSaved: 0,
          ),
        ),
      ),
    );

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.text('Scanning files...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
