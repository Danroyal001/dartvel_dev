// A button is as wide as its label.
//
// The closing call to action sat directly in a Section's column, which
// stretches its children, so on a desktop it was a 1040-pixel bar while every
// other button on the page was sized to its text. Seen only in a screenshot.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the closing call to action is not stretched across the page', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: StartNow()))));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final Finder cta = find.byType(PrimaryLink, skipOffstage: false);
    expect(cta, findsOneWidget);
    expect(tester.getSize(cta).width, lessThan(400));
  });
}
