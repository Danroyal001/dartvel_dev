import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartvel_site/main.dart';

void main() {
  testWidgets('Dartvel application starts', (WidgetTester tester) async {
    await tester.pumpWidget(createDartvelApp());
    expect(find.byType(WidgetsApp), findsOneWidget);
  });
}
