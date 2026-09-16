// Two copies of the docs page at once.
//
// Hovering the Docs link shows a live preview of the page, and a click
// navigates while that preview is still up, so for a moment the page exists
// twice. Its step keys were one global map of GlobalKeys, the second copy
// could not take them, and in a release build every step after the contents
// was dropped: the page showed its table of contents and then the footer.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('both copies of the page build every step', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Row(children: <Widget>[
          Expanded(child: DocsPageGeneratedPage()),
          Expanded(child: DocsPageGeneratedPage()),
        ]),
      ),
    ));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(Install, skipOffstage: false), findsNWidgets(2));
    expect(find.byType(Honesty, skipOffstage: false), findsNWidgets(2));
  });
}
