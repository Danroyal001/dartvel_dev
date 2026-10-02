// Dartvel Preview decides what to do with a link from what the link carries
// and what this build can do, and says so on screen.
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_preview/components/open_panel.dart';
import 'package:dartvel_preview/components/preview_decision.dart';
import 'package:dartvel_preview/components/preview_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uri pairingLink() => DVDevClientPairing(
      server: Uri.parse('https://192.168.1.20:8787'),
      branch: 'main',
      publicKey: Uint8List.fromList(<int>[
        0x04,
        0x6b, 0x17, 0xd1, 0xf2, 0xe1, 0x2c, 0x42, 0x47, 0xf8, 0xbc, 0xe6, 0xe5,
        0x63, 0xa4, 0x40, 0xf2, 0x77, 0x03, 0x7d, 0x81, 0x2d, 0xeb, 0x33, 0xa0,
        0xf4, 0xa1, 0x39, 0x45, 0xd8, 0x98, 0xc2, 0x96,
        0x4f, 0xe3, 0x42, 0xe2, 0xfe, 0x1a, 0x7f, 0x9b, 0x8e, 0xe7, 0xeb, 0x4a,
        0x7c, 0x0f, 0x9e, 0x16, 0x2b, 0xce, 0x33, 0x57, 0x6b, 0x31, 0x5e, 0xce,
        0xcb, 0xb6, 0x40, 0x68, 0x37, 0xbf, 0x51, 0xf5,
      ]),
      token: dvWebPushBase64Encode(List<int>.filled(32, 7)),
    ).link;

final DVPreviewAppLink both = DVPreviewAppLink(
  name: 'shop',
  pairing: pairingLink(),
  web: Uri.parse('http://192.168.1.20:5000'),
);

void main() {
  group('what a link does', () {
    test('a development build runs the code', () {
      final PreviewDecision d =
          previewDecide(both, runsCode: true, showsWeb: false);
      expect(d.action, PreviewAction.pair);
      expect(d.url, pairingLink());
    });

    test('a browser shows the web build inside Preview', () {
      final PreviewDecision d =
          previewDecide(both, runsCode: false, showsWeb: true);
      expect(d.action, PreviewAction.showWeb);
      expect(d.url, Uri.parse('http://192.168.1.20:5000'));
    });

    test('a build that can do neither hands the address to a browser', () {
      final PreviewDecision d =
          previewDecide(both, runsCode: false, showsWeb: false);
      expect(d.action, PreviewAction.openInBrowser);
      expect(d.message, contains('cannot run code'));
    });

    test('a pairing-only link in a browser says what to run instead', () {
      final PreviewDecision d = previewDecide(
          DVPreviewAppLink(pairing: pairingLink()),
          runsCode: false,
          showsWeb: true);
      expect(d.action, PreviewAction.cannot);
      expect(d.message, contains('-d web-server'));
    });
  });

  group('the launch', () {
    test('a Preview link or a web address on the command line is opened', () {
      expect(previewLinkFromArguments(<String>['--verbose', both.toString()]),
          both.toString());
      expect(previewLinkFromArguments(<String>['http://10.0.0.2:5000']),
          'http://10.0.0.2:5000');
    });

    test('a pairing link on the command line is left to the tunnel', () {
      // The tunnel reads it when the process starts; the app acting on it
      // too would pair twice.
      expect(previewLinkFromArguments(<String>[pairingLink().toString()]),
          isNull);
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester tester, Widget panel) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: panel)));

    testWidgets('a link it cannot read says why, under the field',
        (WidgetTester tester) async {
      await pump(tester, const PreviewOpenPanel(runsCode: true, showsWeb: false));
      await tester.enterText(find.byType(TextField), 'javascript:alert(1)');
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.textContaining('not something Dartvel Preview opens'),
          findsOneWidget);
    });

    testWidgets('a development build hands the pairing to the tunnel',
        (WidgetTester tester) async {
      final List<Uri> paired = <Uri>[];
      await pump(
        tester,
        PreviewOpenPanel(
          runsCode: true,
          showsWeb: false,
          pair: (Uri link) async {
            paired.add(link);
            return 'Pairing. When dartvel dev attaches, this app restarts '
                'into the project.';
          },
        ),
      );
      await tester.enterText(find.byType(TextField), both.toString());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(paired, <Uri>[pairingLink()]);
      expect(find.textContaining('restarts into the project'), findsOneWidget);
    });

    testWidgets('a release build shows the web address to copy',
        (WidgetTester tester) async {
      await pump(tester, const PreviewOpenPanel(runsCode: false, showsWeb: false));
      await tester.enterText(find.byType(TextField), both.toString());
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.text('http://192.168.1.20:5000'), findsOneWidget);
      expect(find.byTooltip('Copy the address'), findsOneWidget);
    });
  });
}
