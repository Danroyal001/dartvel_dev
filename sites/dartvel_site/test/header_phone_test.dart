// On a phone the header's site links share one line.
//
// The header wraps on a phone so nothing is clipped. With four site links it
// wrapped by one: Cloud went onto a line of its own, which read as a broken
// header on every page. Measured with Roboto, the font the site renders in,
// because the test font's square glyphs are far wider than real text.
import 'dart:io' as io;

import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Roboto from the Flutter SDK this test runs on, if it is there.
io.Directory? robotoDir() {
  final io.Directory dir = io.Directory(
    '${io.File(io.Platform.resolvedExecutable).parent.parent.parent.parent.path}'
    '/artifacts/material_fonts',
  );
  return io.File('${dir.path}/Roboto-Regular.ttf').existsSync() ? dir : null;
}

void main() {
  setUpAll(() async {
    final FontLoader roboto = FontLoader('Roboto');
    for (final String weight in <String>['Regular', 'Medium', 'Bold']) {
      final Uint8List bytes =
          io.File('${robotoDir()!.path}/Roboto-$weight.ttf').readAsBytesSync();
      roboto.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await roboto.load();
  });

  for (final double width in <double>[320, 375, 390, 430]) {
    testWidgets('at $width wide, the site links share one line',
        (WidgetTester tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp.router(
        theme: ThemeData(fontFamily: 'Roboto'),
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
      for (final String label in <String>['Features', 'Studio', 'Cloud']) {
        expect(top(label), top('Docs'), reason: '$label wrapped');
      }
    });
  }
}
