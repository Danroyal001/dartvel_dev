// The rule is "never a raw Container in a Dartvel project", and a rule the
// primitives cannot keep is a rule that gets broken quietly.
//
// Every Container left in Dartvel's own site was there for something DVModifier
// could not express: a gradient behind a hero, a maximum width on a reading
// column, symmetric padding, a colour that animates on hover. So the site was
// half Dartvel and half Flutter, and the parts written in raw Flutter are
// exactly the parts that stopped being responsive or themeable.
//
// These are the gaps, closed.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

/// The decorated box DVBox paints, whichever container type it used.
BoxDecoration decorationOf(WidgetTester tester) {
  final Iterable<Container> boxes = tester.widgetList<Container>(
    find.descendant(of: find.byType(DVBox), matching: find.byType(Container)),
  );
  for (final Container box in boxes) {
    final Decoration? d = box.decoration;
    if (d is BoxDecoration) return d;
  }
  fail('DVBox painted no BoxDecoration');
}

void main() {
  testWidgets('a gradient', (WidgetTester tester) async {
    // The hero band. Expressed with a Container it stops following the theme,
    // because the theme lookup lives on the Dartvel side.
    const RadialGradient bloom = RadialGradient(
      center: Alignment(0.92, -1.1),
      radius: 1.15,
      colors: <Color>[Color(0x332F6BFF), Color(0x002F6BFF)],
    );

    await show(
      tester,
      DVBox(const DVText('hero'), const DVModifier().gradient(bloom)),
    );

    expect(decorationOf(tester).gradient, bloom);
  });

  testWidgets('a maximum width, for a column of prose',
      (WidgetTester tester) async {
    // 1040 is the site's reading column. Without this every section pins its
    // own ConstrainedBox and the number is written out eight times.
    await show(
      tester,
      DVBox(const DVText('body'), const DVModifier().maxWidth(1040)),
    );

    final ConstrainedBox box = tester.widgetList<ConstrainedBox>(
      find.descendant(
          of: find.byType(DVBox), matching: find.byType(ConstrainedBox)),
    ).firstWhere((ConstrainedBox b) => b.constraints.maxWidth == 1040);
    expect(box.constraints.maxWidth, 1040);
  });

  testWidgets('a maximum width does not force that width',
      (WidgetTester tester) async {
    // The difference between a constraint and a size. On a phone a 1040
    // maxWidth must let the box be 390 wide, not overflow by 650.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await show(
      tester,
      DVBox(const DVText('body'), const DVModifier().maxWidth(1040)),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(DVBox)).width, lessThanOrEqualTo(390));
  });

  testWidgets('padding on one axis at a time', (WidgetTester tester) async {
    // padding(double) is uniform, and a page gutter is never uniform: 56
    // horizontal against 64 vertical is the whole shape of a section band.
    await show(
      tester,
      DVBox(
        const DVText('x'),
        const DVModifier().paddingSymmetric(horizontal: 56, vertical: 12),
      ),
    );

    final Container box = tester.widgetList<Container>(
      find.descendant(of: find.byType(DVBox), matching: find.byType(Container)),
    ).firstWhere((Container c) => c.padding != null);
    expect(box.padding, const EdgeInsets.symmetric(horizontal: 56, vertical: 12));
  });

  testWidgets('padding on named edges', (WidgetTester tester) async {
    await show(
      tester,
      DVBox(
        const DVText('x'),
        const DVModifier().paddingOnly(left: 4, top: 8, bottom: 2),
      ),
    );

    final Container box = tester.widgetList<Container>(
      find.descendant(of: find.byType(DVBox), matching: find.byType(Container)),
    ).firstWhere((Container c) => c.padding != null);
    expect(box.padding,
        const EdgeInsets.only(left: 4, top: 8, bottom: 2));
  });

  group('animation', () {
    testWidgets('an animated box uses AnimatedContainer',
        (WidgetTester tester) async {
      // A card whose border takes the accent on hover. Done with a plain
      // Container the colour snaps, which reads as a glitch rather than a
      // response.
      await show(
        tester,
        DVBox(
          const DVText('card'),
          const DVModifier()
              .backgroundColor(const Color(0xFFFFFFFF))
              .animate(const Duration(milliseconds: 180)),
        ),
      );

      expect(find.byType(AnimatedContainer), findsOneWidget);
    });

    testWidgets('it actually interpolates rather than snapping',
        (WidgetTester tester) async {
      // The assertion that matters. Finding an AnimatedContainer only proves
      // the widget type; this proves the colour is mid-transition partway
      // through, which is what a snapping implementation would fail.
      Widget at(Color color) => MaterialApp(
            home: Scaffold(
              body: DVBox(
                const DVText('card'),
                DVModifier()
                    .backgroundColor(color)
                    .animate(const Duration(milliseconds: 200)),
              ),
            ),
          );

      await tester.pumpWidget(at(const Color(0xFF000000)));
      await tester.pumpWidget(at(const Color(0xFFFFFFFF)));
      await tester.pump(const Duration(milliseconds: 100));

      final AnimatedContainer widget =
          tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(widget.duration, const Duration(milliseconds: 200));

      final RenderDecoratedBox render = tester.renderObject<RenderDecoratedBox>(
        find.descendant(
          of: find.byType(AnimatedContainer),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final Color painted = (render.decoration as BoxDecoration).color!;
      expect(painted, isNot(const Color(0xFF000000)));
      expect(painted, isNot(const Color(0xFFFFFFFF)));
    });

    testWidgets('an unanimated box stays a plain Container',
        (WidgetTester tester) async {
      // No animation machinery for the overwhelming majority of boxes that
      // never change.
      await show(tester, DVBox(const DVText('x'),
          const DVModifier().backgroundColor(const Color(0xFF112233))));
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('reduced motion drops the animation',
        (WidgetTester tester) async {
      // The setting is not a preference about taste. A box that keeps
      // animating through it has ignored it.
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: DVBox(
                const DVText('card'),
                const DVModifier()
                    .backgroundColor(const Color(0xFFFFFFFF))
                    .animate(const Duration(milliseconds: 180)),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedContainer), findsNothing);
    });
  });

  testWidgets('opacity', (WidgetTester tester) async {
    await show(
      tester,
      DVBox(const DVText('faded'), const DVModifier().opacity(0.5)),
    );
    expect(
      tester.widget<Opacity>(find.byType(Opacity).first).opacity,
      0.5,
    );
  });

  testWidgets('the modifiers compose', (WidgetTester tester) async {
    // Each returns a DVModifier, so a real one is a chain. If any of them
    // dropped the fields set before it, this is where it shows.
    await show(
      tester,
      DVBox(
        const DVText('all'),
        const DVModifier()
            .paddingSymmetric(horizontal: 20, vertical: 10)
            .maxWidth(600)
            .rounded(12)
            .gradient(const LinearGradient(
                colors: <Color>[Color(0xFF111111), Color(0xFF222222)])),
      ),
    );

    final BoxDecoration decoration = decorationOf(tester);
    expect(decoration.gradient, isA<LinearGradient>());
    expect(decoration.borderRadius, BorderRadius.circular(12));
  });
}
