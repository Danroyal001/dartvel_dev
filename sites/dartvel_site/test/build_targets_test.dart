// The build-target chips name targets, not browsers.
//
// "Chrome" and "Firefox" sat in this list beside "web", which reads as three
// ways to ship a web application. They are not: they are the two browser
// extension targets, and an extension is a different artifact with a manifest,
// a background worker and a store review. Somebody scanning the row for what
// Dartvel builds should not have to already know that.
//
// The names here are the ones `dartvel build` takes, so what the site says and
// what you type are the same string.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: IndexPageGeneratedPage())),
  );
  // Pumped rather than settled: the bands reveal themselves as they come into
  // view, so the tree is never completely still.
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('the extension targets say they are extensions', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester);

    expect(find.text('chrome-extension'), findsOneWidget);
    expect(find.text('firefox-extension'), findsOneWidget);
  });

  testWidgets('and a bare browser name is not offered as a target', (
    WidgetTester tester,
  ) async {
    // The failure this guards is a chip reading "Chrome" next to one reading
    // "web", which invites somebody to think they are alternatives.
    await pumpHome(tester);

    expect(find.text('Chrome'), findsNothing);
    expect(find.text('Firefox'), findsNothing);
  });
}
