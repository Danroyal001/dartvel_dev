// A card's status is a badge, not the last word of its paragraph.
//
// Nine cards on the cloud page ended their prose with a bare "Built." and one
// with "Planned; not yet built." — a status marker written as a sentence. It
// reads as filler, it repeats nine times down one page, and a reader scanning
// for what is ready has to reach the end of every paragraph to find out.
//
// A badge sits where the eye already is, next to the title.
import 'dart:io';

import 'package:dartvel_site/components/docs.dart' show kDocsSpecStatus;
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, Widget card) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: card))),
    );

void main() {
  testWidgets('a built card says so beside its title, not in its prose',
      (WidgetTester tester) async {
    await pump(
      tester,
      const SiteCard('Figma import', 'Paste a file URL.', built: true),
    );

    expect(find.text('Built'), findsOneWidget);
    // And the body is only the body.
    expect(find.text('Paste a file URL.'), findsOneWidget);
  });

  testWidgets('one that is not built says that instead', (tester) async {
    await pump(
      tester,
      const SiteCard('Enterprise SSO', 'SAML and SCIM.', built: false),
    );

    expect(find.text('Planned'), findsOneWidget);
    expect(find.text('Built'), findsNothing);
  });

  // A card that is neither — an ordinary explainer — should carry no badge
  // at all rather than a default one that claims something.
  testWidgets('a card that declares nothing claims nothing', (tester) async {
    await pump(tester, const SiteCard('One command', 'dartvel deploy.'));

    expect(find.text('Built'), findsNothing);
    expect(find.text('Planned'), findsNothing);
  });

  // A card for a spec section takes its badge from the index, so a partly
  // built section reads Partial and nobody can badge it Built by hand.
  testWidgets('a card for a partly built section is badged Partial',
      (WidgetTester tester) async {
    await pump(
      tester,
      const SiteCard('Content review', 'Draft, review, publish.',
          section: 'Content Workflow'),
    );

    expect(find.text('Partial'), findsOneWidget);
    expect(find.text('Built'), findsNothing);
  });

  testWidgets('and one for a shipped section is badged Built', (tester) async {
    await pump(
      tester,
      const SiteCard('Page builder', 'Drag and drop.',
          section: 'Dartvel Studio'),
    );

    expect(find.text('Built'), findsOneWidget);
  });

  test('every card that names a spec section names one the index records', () {
    final List<String> unknown = <String>[
      for (final FileSystemEntity e
          in Directory('lib/pages').listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart'))
          for (final Match m in RegExp(r"SiteCard\([^;]*?section:\s*'([^']+)'")
              .allMatches(e.readAsStringSync()))
            if (!kDocsSpecStatus.containsKey(m[1])) '${e.path}: ${m[1]}',
    ];
    expect(unknown, isEmpty, reason: unknown.join('\n'));
  });
}
