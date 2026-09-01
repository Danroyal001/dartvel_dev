// Hover and reveal, as modifiers.
//
// A card that lifts under the pointer and a section that fades in as it is
// scrolled to are the two pieces of motion nearly every page has, and neither
// could be expressed with a DVModifier. So both were hand-written in the site
// as StatefulWidgets over MouseRegion, NotificationListener and a Timer --
// application code doing framework work, and the one place the site's own
// reduced-motion handling had to be remembered by hand rather than enforced.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

Future<void> showReduced(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    ));

BoxDecoration decorationOf(WidgetTester tester) {
  for (final Container box in tester.widgetList<Container>(
    find.descendant(of: find.byType(DVBox), matching: find.byType(Container)),
  )) {
    if (box.decoration is BoxDecoration) return box.decoration! as BoxDecoration;
  }
  for (final AnimatedContainer box in tester.widgetList<AnimatedContainer>(
    find.descendant(
        of: find.byType(DVBox), matching: find.byType(AnimatedContainer)),
  )) {
    if (box.decoration is BoxDecoration) return box.decoration! as BoxDecoration;
  }
  fail('DVBox painted no BoxDecoration');
}

Future<void> hoverOver(WidgetTester tester, Finder target) async {
  final TestGesture pointer =
      await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: Offset.zero);
  addTearDown(pointer.removePointer);
  await tester.pump();
  await pointer.moveTo(tester.getCenter(target));
  await tester.pumpAndSettle();
}

void main() {
  group('hover', () {
    testWidgets('the hover modifier applies while the pointer is over it',
        (WidgetTester tester) async {
      final Widget card = DVBox(
        const DVText('card'),
        const DVModifier()
            .backgroundColor(const Color(0xFFFFFFFF))
            .hover(const DVModifier().backgroundColor(const Color(0xFF2F6BFF))),
      );

      await show(tester, card);
      expect(decorationOf(tester).color, const Color(0xFFFFFFFF));

      await hoverOver(tester, find.byType(DVBox));
      expect(decorationOf(tester).color, const Color(0xFF2F6BFF));
    });

    testWidgets('it reverts when the pointer leaves',
        (WidgetTester tester) async {
      await show(
        tester,
        DVBox(
          const DVText('card'),
          const DVModifier()
              .backgroundColor(const Color(0xFFFFFFFF))
              .hover(const DVModifier().backgroundColor(const Color(0xFF2F6BFF))),
        ),
      );

      final TestGesture pointer =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.byType(DVBox)));
      await tester.pumpAndSettle();
      expect(decorationOf(tester).color, const Color(0xFF2F6BFF));

      await pointer.moveTo(const Offset(2000, 2000));
      await tester.pumpAndSettle();
      expect(decorationOf(tester).color, const Color(0xFFFFFFFF));
    });

    testWidgets('the base modifier survives underneath',
        (WidgetTester tester) async {
      // A hover state that says only "blue border" must not drop the padding
      // and radius the base set, which is what a plain replace would do.
      await show(
        tester,
        DVBox(
          const DVText('card'),
          const DVModifier()
              .rounded(12)
              .backgroundColor(const Color(0xFFFFFFFF))
              .hover(const DVModifier().border(const Border.fromBorderSide(
                  BorderSide(color: Color(0xFF2F6BFF))))),
        ),
      );

      await hoverOver(tester, find.byType(DVBox));
      final BoxDecoration decoration = decorationOf(tester);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      expect(decoration.color, const Color(0xFFFFFFFF));
      expect(decoration.border, isNotNull);
    });

    testWidgets('a box with no hover modifier gets no MouseRegion',
        (WidgetTester tester) async {
      // Every box on a page listening for the pointer is a cost nobody asked
      // for, and it makes hit-testing harder to reason about.
      await show(tester, DVBox(const DVText('plain'),
          const DVModifier().backgroundColor(const Color(0xFFFFFFFF))));

      expect(
        find.descendant(
            of: find.byType(DVBox), matching: find.byType(MouseRegion)),
        findsNothing,
      );
    });
  });

  group('reveal on scroll', () {
    testWidgets('it ends up fully visible', (WidgetTester tester) async {
      // Whatever the animation does, content must not be able to stay
      // invisible. A decoration that can permanently hide a section is a
      // worse bug than no decoration.
      await show(
        tester,
        DVBox(const DVText('section'), const DVModifier().revealOnScroll()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final Iterable<Opacity> fades =
          tester.widgetList<Opacity>(find.byType(Opacity));
      for (final Opacity fade in fades) {
        expect(fade.opacity, 1.0);
      }
      expect(find.text('section'), findsOneWidget);
    });

    testWidgets('reduced motion shows it at once, with no animation',
        (WidgetTester tester) async {
      await showReduced(
        tester,
        DVBox(const DVText('section'), const DVModifier().revealOnScroll()),
      );
      // One pump, no settling: it is already there.
      expect(find.text('section'), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsNothing);
    });

    testWidgets('the content stays in the semantics tree while it is faded',
        (WidgetTester tester) async {
      // Opacity 0 drops its children from semantics by default, and a
      // reveal-on-scroll starts every section at 0 -- so the crawler-visible
      // HTML, which is built from that tree, loses every section the reader
      // has not reached.
      final SemanticsHandle handle = tester.ensureSemantics();
      await show(
        tester,
        DVBox(const DVText('findable'), const DVModifier().revealOnScroll()),
      );

      expect(
        find.bySemanticsLabel('findable'),
        findsOneWidget,
        reason: 'a faded section must still be readable and crawlable',
      );
      handle.dispose();
    });
  });
  group('reporting hover', () {
    testWidgets('it reports entering and leaving', (WidgetTester tester) async {
      // hover() restyles the same box. Revealing a sibling -- a label beside
      // a rail indicator, a caption under a card -- needs the fact itself, so
      // application code can put it in a signal and build from it.
      final List<bool> seen = <bool>[];

      await show(
        tester,
        DVBox(
          const DVText('dot'),
          const DVModifier()
              .backgroundColor(const Color(0xFFFFFFFF))
              .onHoverChanged(seen.add),
        ),
      );
      expect(seen, isEmpty);

      final TestGesture pointer =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.byType(DVBox)));
      await tester.pumpAndSettle();
      expect(seen, <bool>[true]);

      await pointer.moveTo(const Offset(2000, 2000));
      await tester.pumpAndSettle();
      expect(seen, <bool>[true, false]);
    });

    testWidgets('it composes with hover styling', (WidgetTester tester) async {
      // Both use the same MouseRegion, so asking for one must not lose the
      // other.
      final List<bool> seen = <bool>[];

      await show(
        tester,
        DVBox(
          const DVText('dot'),
          const DVModifier()
              .backgroundColor(const Color(0xFFFFFFFF))
              .hover(const DVModifier().backgroundColor(const Color(0xFF2F6BFF)))
              .onHoverChanged(seen.add),
        ),
      );

      await hoverOver(tester, find.byType(DVBox));
      expect(seen, <bool>[true]);
      expect(decorationOf(tester).color, const Color(0xFF2F6BFF));
    });
  });

}