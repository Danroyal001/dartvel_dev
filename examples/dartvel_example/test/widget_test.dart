import 'package:flutter_test/flutter_test.dart';

import 'package:dartvel_example/main.dart';

void main() {
  testWidgets('Dartvel showcase renders generated app shell',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DartvelExampleApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Dartvel Platform Showcase'), findsOneWidget);
    expect(find.text('1. Signals State Management'), findsOneWidget);
    expect(find.text('13. AI, Observability & Logging'), findsOneWidget);
    expect(find.text('Local counter signal value: 0'), findsOneWidget);

    await tester.tap(find.text('Increment Counter Signal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Local counter signal value: 1'), findsOneWidget);
  });
}
