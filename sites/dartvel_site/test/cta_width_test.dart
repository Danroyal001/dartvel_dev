// A button is as wide as its label.
//
// The closing call to action sat directly in a Section's column, which
// stretches its children, so on a desktop it was a 1040-pixel bar while every
// other button on the page was sized to its text. Seen only in a screenshot.
// It came back twice more the same way: the routing section's docs link on
// the home page, and the features page's closing button.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'responsive_layout_test.dart' show routed;

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void expectNarrowButtons(WidgetTester tester) {
  final Finder buttons = find.byWidgetPredicate(
      (Widget w) => w is PrimaryLink || w is GhostLink,
      skipOffstage: false);
  expect(buttons, findsWidgets);
  for (final Element button in buttons.evaluate()) {
    expect(tester.getSize(find.byElementPredicate((Element e) => e == button,
            skipOffstage: false)).width,
        lessThan(400),
        reason: '${button.widget} is stretched across the page');
  }
}

void main() {
  setUpAll(FeaturesPageGeneratedPage.loadLibrary);

  for (final (String name, Widget section) in <(String, Widget)>[
    ('the closing call to action', const StartNow()),
    ('the routing section\'s docs link', const RoutingProof()),
  ]) {
    testWidgets('$name is not stretched across the page', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: section))));
      await settle(tester);
      expectNarrowButtons(tester);
    });
  }

  testWidgets('no button on the features page is stretched across it', (
    WidgetTester tester,
  ) async {
    dvResetDeferredPages();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routed(const FeaturesPageGeneratedPage()));
    await tester.pumpAndSettle();
    expectNarrowButtons(tester);
  });
}
