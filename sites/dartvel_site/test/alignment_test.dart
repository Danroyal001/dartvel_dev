// Things that sit on one line line up.
//
// Seen only in a screenshot of the built site: the text link beside
// a button sat at the top of the row, a few pixels above the button's label.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child))));
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('a link beside a button is centred on it', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, 1440, const Honest());
    final double button =
        tester.getCenter(find.byType(PrimaryLink, skipOffstage: false)).dy;
    final double link =
        tester.getCenter(find.byType(ExternalLink, skipOffstage: false)).dy;
    expect((button - link).abs(), lessThan(1.5),
        reason: 'button centre $button, link centre $link');
  });
}
