import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/app.dart';

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PressPlayApp());
    expect(find.text('PressPlay'), findsOneWidget);
  });
}
