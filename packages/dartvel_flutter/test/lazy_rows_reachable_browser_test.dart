// Run with: flutter test --platform chrome test/lazy_rows_reachable_browser_test.dart
//
// In a browser, with the application opted in (dartvel.web.lazyBackfill:
// true, the DARTVEL_LAZY_BACKFILL define), the rows a lazy list holds back
// are built while the page is idle; with no opt-in nothing is built ahead
// (off by default since 3.47.9: it cost heap and frames on long lists). See
// lazy_rows_reachable_test.dart, which drives the same steps off the web.
@TestOn('browser')
library;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/lists/backfill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DVLazyBackfill.reset);

  Widget longLayout() => MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Long page'),
        child: DVBox.list(<Widget>[
          const Text('Site header'),
          DVBox.list(<Widget>[for (int i = 0; i < 80; i++) Text('Paragraph $i')], spacing: 12),
          const Text('Footer made by somebody'),
        ], spacing: 0).scrollable(),
      ),
    );

  testWidgets('with no opt-in, nothing is built ahead on the web', (WidgetTester tester) async {
    expect(DVLazyBackfill.enabled, isFalse, reason: 'off by default on the web');
    await tester.pumpWidget(longLayout());
    await tester.pumpAndSettle();
    for (int wait = 0; wait < 10; wait++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
      await tester.pump();
    }
    expect(find.text('Footer made by somebody', skipOffstage: false), findsNothing);
  });

  testWidgets('opted in, the footer of a long layout is built once the page is idle', (WidgetTester tester) async {
    DVLazyBackfill.enabled = true;
    await tester.pumpWidget(longLayout());
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
