// Run with: flutter test --platform chrome test/lazy_rows_reachable_browser_test.dart
//
// In a browser the rows a lazy list holds back are built while the page is
// idle with nothing turned on: see lazy_rows_reachable_test.dart, which
// drives the same steps by hand off the web.
@TestOn('browser')
library;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/lists/backfill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the footer of a long layout is built once the page is idle', (WidgetTester tester) async {
    expect(DVLazyBackfill.enabled, isTrue, reason: 'on by default on the web');
    await tester.pumpWidget(MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Long page'),
        child: DVBox.list(<Widget>[
          const Text('Site header'),
          DVBox.list(<Widget>[for (int i = 0; i < 80; i++) Text('Paragraph $i')], spacing: 12),
          const Text('Footer made by somebody'),
        ], spacing: 0).scrollable(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Footer made by somebody', skipOffstage: false), findsNothing);

    // The browser's own timer, which a widget test's clock does not move.
    bool built() =>
        find.text('Footer made by somebody', skipOffstage: false).evaluate().isNotEmpty &&
        find.text('Paragraph 79', skipOffstage: false).evaluate().isNotEmpty;
    for (int wait = 0; wait < 80 && !built(); wait++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
      await tester.pump();
    }
    expect(find.text('Footer made by somebody', skipOffstage: false), findsOneWidget);
    expect(find.text('Paragraph 79', skipOffstage: false), findsOneWidget);
    expect(tester.getTopLeft(find.text('Site header')).dy, lessThan(100), reason: 'nothing scrolled');
  });
}
