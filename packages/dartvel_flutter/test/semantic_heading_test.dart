// Heading levels, which nothing could express.
//
// A page's structure is carried by its headings: a screen reader user moves
// between them, and a crawler reads the document outline from them. Dartvel
// had no way to say a piece of text was a heading, so the semantics tree
// contained no headings at all -- every DVText was a flat label, and the
// generated static HTML had nothing to build an outline from either.
//
// Checked against the built site before writing this: the semantics DOM
// carried real <a href> anchors and not one heading node.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('a heading level reaches the semantics tree',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(
      tester,
      // ignore: prefer_const_constructors
      DVText('Getting started').modifier(DVModifier().semanticHeading(1)),
    );

    // Read off the node rather than through matchesSemantics, which has no
    // headingLevel argument in this Flutter.
    final SemanticsNode heading =
        tester.getSemantics(find.text('Getting started'));
    expect(heading.headingLevel, 1);
    expect(heading.label, 'Getting started');
    handle.dispose();
  });

  testWidgets('the level is the one asked for', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(
      tester,
      // ignore: prefer_const_constructors
      DVText('Install').modifier(DVModifier().semanticHeading(2)),
    );

    expect(tester.getSemantics(find.text('Install')).headingLevel, 2);
    handle.dispose();
  });

  testWidgets('text with no heading is not one', (WidgetTester tester) async {
    // The default has to stay a plain label, or every string becomes an
    // outline entry and the outline stops meaning anything.
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, const DVText('Ordinary prose'));

    final SemanticsNode plain = tester.getSemantics(find.text('Ordinary prose'));
    expect(plain.headingLevel, 0, reason: 'a heading by default would make '
        'every string an outline entry, and the outline would stop meaning '
        'anything');
    expect(plain.label, 'Ordinary prose');
    handle.dispose();
  });

  test('a level outside 1-6 is refused', () {
    // HTML has six. Accepting a seventh would produce a semantics node no
    // platform can express and an <h7> that does not exist.
    expect(() => const DVModifier().semanticHeading(0), throwsArgumentError);
    expect(() => const DVModifier().semanticHeading(7), throwsArgumentError);
  });
}
