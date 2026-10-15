// A page that looks alive, from modifiers: a drifting mesh behind a hero, a
// glow that follows the pointer across a card, and a row of cards that
// arrives one after another.
//
// Each is checked for what it does, not for whether the method exists. The
// first version of this file asserted `isNotNull` on the modifier each one
// returned, and passed while the "mesh" was a static linear gradient, the
// glow was a shadow that threw away the box's own hover style, and the
// stagger was revealOnScroll under a second name.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Align(alignment: .topLeft, child: child)),
    ));

Future<void> showReduced(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Align(alignment: .topLeft, child: child)),
      ),
    ));

/// The centre of every circle the box paints, in the painting layer's own
/// coordinates.
List<Offset> circlesOf(WidgetTester tester) {
  final List<Offset> centres = <Offset>[];
  expect(
    tester.renderObject(find.byType(DVBox).first),
    paints
      ..everything((Symbol method, List<dynamic> arguments) {
        if (method == #drawCircle) centres.add(arguments[0] as Offset);
        return true;
      }),
  );
  return centres;
}

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

Future<TestGesture> mouse(WidgetTester tester) async {
  final TestGesture pointer =
      await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: const Offset(790, 590));
  addTearDown(pointer.removePointer);
  await tester.pump();
  return pointer;
}

const List<Color> mesh = <Color>[
  Color(0x662F6BFF),
  Color(0x557BA2FF),
  Color(0x44FF7A59),
];

void main() {
  group('meshGradient', () {
    Widget hero({VoidCallback? onTap}) {
      DVModifier modifier = const DVModifier()
          .width(400)
          .height(240)
          .backgroundColor(const Color(0xFFFFFFFF))
          .meshGradient(mesh);
      if (onTap != null) modifier = modifier.onTap(onTap).tooltip('Go');
      return DVBox(const DVText('Go'), modifier);
    }

    testWidgets('paints one soft blob per colour behind the content',
        (WidgetTester tester) async {
      await show(tester, hero());
      expect(circlesOf(tester), hasLength(mesh.length));
      expect(find.text('Go'), findsOneWidget);
    });

    testWidgets('the blobs drift while it is on screen',
        (WidgetTester tester) async {
      await show(tester, hero());
      final List<Offset> before = circlesOf(tester);
      await tester.pump(const Duration(seconds: 2));
      final List<Offset> after = circlesOf(tester);

      expect(after, isNot(equals(before)),
          reason: 'a mesh that never moves is a gradient');
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('reduced motion holds it still and asks for no frames',
        (WidgetTester tester) async {
      await showReduced(tester, hero());
      final List<Offset> before = circlesOf(tester);
      await tester.pump(const Duration(seconds: 2));

      expect(circlesOf(tester), equals(before));
      expect(before, hasLength(mesh.length),
          reason: 'still means a still picture, not no picture');
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'a held mesh must not keep a ticker running');
    });

    testWidgets('the content on it is still tapped and still read',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      int taps = 0;
      await show(tester, hero(onTap: () => taps++));
      await tester.tap(find.text('Go'));
      expect(taps, 1);
      expect(find.bySemanticsLabel('Go'), findsOneWidget,
          reason: 'the mesh is decoration and must add no node of its own');
      handle.dispose();
    });

    testWidgets('it covers the padding, not only the content',
        (WidgetTester tester) async {
      await show(
        tester,
        DVBox(
          const DVText('Go'),
          const DVModifier().width(400).height(240).padding(40).meshGradient(mesh),
        ),
      );
      final RenderBox layer = tester.renderObject<RenderBox>(find
          .descendant(of: find.byType(DVBox), matching: find.byType(CustomPaint))
          .first);
      expect(layer.size, const Size(400, 240));
    });

    test('fewer than two colours is not a mesh', () {
      expect(() => const DVModifier().meshGradient(<Color>[Colors.blue]),
          throwsArgumentError);
    });
  });

  group('hoverGlow', () {
    // Chained onto the base rather than merged into it: merge() leaves out
    // hover states on purpose, so a merged glow would test nothing.
    DVModifier base() => const DVModifier()
        .width(300)
        .height(200)
        .backgroundColor(const Color(0xFFFFFFFF));
    Widget card(DVModifier modifier) => DVBox(const DVText('card'), modifier);

    testWidgets('nothing glows until the pointer is over the box',
        (WidgetTester tester) async {
      await show(tester, card(base().hoverGlow()));
      expect(circlesOf(tester), isEmpty);
    });

    testWidgets('the glow follows the pointer', (WidgetTester tester) async {
      await show(tester, card(base().hoverGlow()));
      final TestGesture pointer = await mouse(tester);
      final Offset origin = tester.getTopLeft(find.byType(DVBox).first);

      await pointer.moveTo(origin + const Offset(40, 50));
      await tester.pump();
      expect(circlesOf(tester), <Offset>[const Offset(40, 50)]);

      await pointer.moveTo(origin + const Offset(260, 150));
      await tester.pump();
      expect(circlesOf(tester), <Offset>[const Offset(260, 150)]);
    });

    testWidgets('it goes when the pointer leaves', (WidgetTester tester) async {
      await show(tester, card(base().hoverGlow()));
      final TestGesture pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.byType(DVBox).first));
      await tester.pump();
      await pointer.moveTo(const Offset(790, 590));
      await tester.pump();
      expect(circlesOf(tester), isEmpty);
    });

    testWidgets("the box's own hover style survives it, in either order",
        (WidgetTester tester) async {
      // The first version was hover(shadow), so adding a glow replaced
      // whatever hover the card already had.
      const DVModifier blue =
          DVModifier(boxColor: Color(0xFF2F6BFF));
      for (final DVModifier modifier in <DVModifier>[
        base().hover(blue).hoverGlow(),
        base().hoverGlow().hover(blue),
      ]) {
        await show(tester, card(modifier));
        final TestGesture pointer = await mouse(tester);
        await pointer.moveTo(tester.getCenter(find.byType(DVBox).first));
        await tester.pumpAndSettle();
        expect(decorationOf(tester).color, const Color(0xFF2F6BFF));
        expect(circlesOf(tester), hasLength(1));
        await pointer.removePointer();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('reduced motion: the glow sits still at the centre',
        (WidgetTester tester) async {
      await showReduced(tester, card(base().hoverGlow()));
      final TestGesture pointer = await mouse(tester);
      final Offset origin = tester.getTopLeft(find.byType(DVBox).first);

      await pointer.moveTo(origin + const Offset(40, 50));
      await tester.pump();
      expect(circlesOf(tester), <Offset>[const Offset(150, 100)]);
      await pointer.moveTo(origin + const Offset(260, 150));
      await tester.pump();
      expect(circlesOf(tester), <Offset>[const Offset(150, 100)]);
    });

    testWidgets('moving the pointer repaints without rebuilding',
        (WidgetTester tester) async {
      int builds = 0;
      await show(
        tester,
        DVBox(
          Builder(builder: (BuildContext context) {
            builds++;
            return const DVText('card');
          }),
          const DVModifier().width(300).height(200).hoverGlow(),
        ),
      );
      final TestGesture pointer = await mouse(tester);
      final Offset origin = tester.getTopLeft(find.byType(DVBox).first);
      await pointer.moveTo(origin + const Offset(20, 20));
      await tester.pump();
      final int entered = builds;
      for (int x = 30; x < 280; x += 25) {
        await pointer.moveTo(origin + Offset(x.toDouble(), 100));
        await tester.pump();
      }
      expect(builds, entered,
          reason: 'a card rebuilt on every mouse move is a page that stutters');
    });
  });

  group('revealChildren', () {
    double opacityOf(WidgetTester tester, String text) => tester
        .widget<AnimatedOpacity>(find.ancestor(
            of: find.text(text), matching: find.byType(AnimatedOpacity)))
        .opacity;

    Widget row() => const DVBox.row(<Widget>[
          DVText('a'),
          DVText('b'),
          DVText('c'),
        ]).modifier(const DVModifier()
            .revealChildren(step: const Duration(milliseconds: 200)));

    testWidgets('children arrive one after another',
        (WidgetTester tester) async {
      await show(tester, row());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, 'a'), 1);
      expect(opacityOf(tester, 'b'), 0);
      expect(opacityOf(tester, 'c'), 0);

      await tester.pump(const Duration(milliseconds: 200));
      expect(opacityOf(tester, 'b'), 1);
      expect(opacityOf(tester, 'c'), 0);

      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(opacityOf(tester, 'c'), 1);
    });

    testWidgets('reduced motion shows every child at once',
        (WidgetTester tester) async {
      await showReduced(tester, row());
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(find.text('c'), findsOneWidget);
    });

    testWidgets('an Expanded child stays a direct child of its row',
        (WidgetTester tester) async {
      await show(
        tester,
        SizedBox(
          width: 400,
          child: const DVBox.row(<Widget>[
            Expanded(child: DVText('wide')),
            DVText('narrow'),
          ]).modifier(const DVModifier().revealChildren()),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Expanded)).width, greaterThan(200));
    });

    testWidgets('faded children stay in the semantics tree',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await show(tester, row());
      expect(find.bySemanticsLabel('c'), findsOneWidget);
      handle.dispose();
    });
  });
}
