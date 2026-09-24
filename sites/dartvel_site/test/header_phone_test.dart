// On a phone the header's site links share one line.
//
// The header wraps on a phone so nothing is clipped. With four site links it
// wrapped by one: Cloud went onto a line of its own, which read as a broken
// header on every page.
//
// This measured Roboto, which was the font the site rendered in until it was
// given one somebody chose. Loading a font the site does not use meant the
// check went on passing through a typeface change that pushed Compared onto
// a second line, and it never looked at Compared in the first place: the
// list of labels stopped at Cloud, one short, so the last link on the row
// was the one nothing measured.
import 'dart:io' as io;

import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every link the header puts on the site row, in the order it draws them.
const List<String> kSiteLinks = <String>[
  'Docs',
  'Features',
  'Studio',
  'Cloud',
  'Compared',
];

void main() {
  setUpAll(() async {
    // The face the site actually renders in. The test font's square glyphs
    // are far wider than real text, so measuring without this measures the
    // harness.
    final FontLoader manrope = FontLoader('Manrope')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(
        io.File('fonts/Manrope.ttf').readAsBytesSync(),
      )));
    await manrope.load();
  });

  // 360 up. Five links cannot share one line at 320 in this face at any
  // size worth reading: the labels and their padding alone are 319 points
  // and a 320-point phone leaves 276 after its gutters. 320 is the first
  // iPhone SE; every phone sold since is 360 or wider.
  for (final double width in <double>[360, 375, 390, 430]) {
    testWidgets('at $width wide, the site links share one line',
        (WidgetTester tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp.router(
        theme: dartvelSiteTheme(Brightness.light),
        routerConfig: GoRouter(routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: SiteHeader()),
          ),
        ]),
      ));
      await tester.pump();

      double top(String label) => tester
          .getTopLeft(find.descendant(
              of: find.byType(SiteHeader), matching: find.text(label)))
          .dy;
      for (final String label in kSiteLinks.skip(1)) {
        expect(top(label), top(kSiteLinks.first), reason: '$label wrapped');
      }
    });
  }
}
