import 'package:class_widgets_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('class widget app renders generated Dartvel route',
      (WidgetTester tester) async {
    await tester.pumpWidget(createDartvelApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Your Class-Based Dartvel app is ready!'),
      findsOneWidget,
    );
  });
}
