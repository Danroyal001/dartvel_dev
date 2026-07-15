import 'package:basic_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('basic app renders generated Dartvel route',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Your Dartvel app is ready!'), findsOneWidget);
  });
}
