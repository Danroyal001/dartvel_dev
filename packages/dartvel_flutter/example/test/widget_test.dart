import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    dvResetAmbientSignals();
    DV.global<Shop>(const Shop(name: 'Corner Roasters', currency: 'EUR'));
  });

  testWidgets('the total follows the quantity', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Total EUR 14.50'), findsOneWidget);

    await tester.tap(find.text('Add one'));
    await tester.pump();
    expect(find.text('Total EUR 29.00'), findsOneWidget);

    await tester.tap(find.text('Remove one'));
    await tester.tap(find.text('Remove one'));
    await tester.pump();
    expect(find.text('Total EUR 0.00'), findsOneWidget);
  });

  testWidgets('ordering needs a quantity and the terms accepted',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Accept the terms to order'), findsOneWidget);

    await tester.tap(find.text('[ ] I accept the terms'));
    await tester.pump();
    expect(find.text('Ready to order'), findsOneWidget);

    await tester.tap(find.text('Remove one'));
    await tester.pump();
    expect(find.text('Accept the terms to order'), findsOneWidget);
  });
}
