// Box styling on text, which went nowhere.
//
// DVText draws text and drew only text: a modifier carrying padding, a
// background, a corner radius or a border reached it and did nothing, on a
// build that succeeded. This framework's own code does it in two places --
// the studio's Close button and a tab label, both asking for padding round a
// tap target and getting the glyphs -- so a tab strip is cramped and both
// targets are the size of the words rather than the size somebody chose.
//
// It is the same shape as the bug the semantic fields had on this widget
// before they were read: the call goes where it naturally goes, and the
// widget it goes to never looks at it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: child));

void main() {
  testWidgets('padding round text is padding round text',
      (WidgetTester tester) async {
    await pump(
      tester,
      const DVText('padded').modifier(const DVModifier().padding(8)),
    );

    expect(
      tester.widget<Container>(find.byType(Container)).padding,
      const EdgeInsets.all(8),
    );
  });

  testWidgets('a background behind text is drawn', (WidgetTester tester) async {
    await pump(
      tester,
      const DVText('on a chip')
          .modifier(
            const DVModifier().backgroundColor(const Color(0xFF112233)),
          ),
    );

    final BoxDecoration decoration = tester
        .widget<Container>(find.byType(Container))
        .decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF112233));
  });

  testWidgets('text that asked for no box gets no box',
      (WidgetTester tester) async {
    // A container round every DVText in every application, for the styling
    // most of them do not use, is the cost this check exists to keep off.
    await pump(
      tester,
      const DVText('plain').modifier(const DVModifier().fontSize(18)),
    );

    expect(find.byType(Container), findsNothing);
    expect(tester.widget<Text>(find.text('plain')).style?.fontSize, 18);
  });

  testWidgets('a tap on padded text fires once, not twice',
      (WidgetTester tester) async {
    // The box round the text and the text itself would each carry the
    // callback if the handover were careless, and a button that runs its
    // action twice is worse than one that does not pad.
    int taps = 0;
    await pump(
      tester,
      const DVText('Close')
          .modifier(const DVModifier().padding(6).onTap(() => taps++)),
    );

    await tester.tap(find.text('Close'));
    expect(taps, 1);
  });

  testWidgets('a heading is announced once', (WidgetTester tester) async {
    // Two Semantics nodes carrying the same level is a screen reader saying
    // "heading" twice, and it is what handing the whole modifier to the box
    // would produce.
    await pump(
      tester,
      const DVText('Title').modifier(
        const DVModifier().padding(8).semanticHeading(2),
      ),
    );

    final Iterable<Semantics> headings = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((Semantics s) => s.properties.headingLevel != null);
    expect(headings.length, 1);
  });

  testWidgets('a rotated or faded label is rotated and faded',
      (WidgetTester tester) async {
    // Every other box property goes the same way as padding, and the point of
    // naming two here is that the list is a list rather than one special
    // case.
    await pump(
      tester,
      const DVText('tilted').modifier(
        const DVModifier().rotate(45).opacity(0.5),
      ),
    );

    expect(find.byType(Transform), findsWidgets);
    expect(
      tester.widgetList<Opacity>(find.byType(Opacity)).map((Opacity o) => o.opacity),
      contains(0.5),
    );
  });

  testWidgets('a heading that reveals on scroll reveals',
      (WidgetTester tester) async {
    // The reveal is a box behaviour like the rest, and nothing in this
    // repository puts one on text yet -- which is why it is worth a test
    // rather than a note: the next person to write it should not have to
    // find out it does nothing.
    await pump(
      tester,
      const DVText('section').modifier(const DVModifier().revealOnScroll()),
    );

    expect(find.byType(AnimatedOpacity), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('section'), findsOneWidget);
  });

  testWidgets('a centred heading is centred', (WidgetTester tester) async {
    // The fifth place this cost something, and the one with a claim attached
    // to it: a page document says a text node is centred with `align`, that
    // becomes DVModifier.align, and DVText looked straight past it. So every
    // centred heading in every imported design came through left-aligned
    // while the feature list said centred text survives the import.
    await pump(
      tester,
      const DVText('Centred').modifier(
        const DVModifier().align(Alignment.center),
      ),
    );

    expect(
      tester.widget<Container>(find.byType(Container)).alignment,
      Alignment.center,
    );
  });
}
