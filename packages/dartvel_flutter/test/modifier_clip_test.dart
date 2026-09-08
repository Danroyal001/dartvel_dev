// A rounded box rounds what is in it.
//
// The corner radius reached the decoration and nothing else, so a box drew
// rounded corners and its child squared them off again. With a flat colour
// nobody notices -- the decoration is the only thing painted there. With a
// photograph everybody notices: every circular avatar in every imported
// design came through as a square photograph with a rounded outline behind
// it, which renders and looks like somebody's decision.
//
// Clipped only where a radius was asked for. A clip on every box in every
// application, for the corners most of them do not round, is a cost nobody
// chose -- the same rule the blur and the box-on-text handovers follow.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Container boxOf(WidgetTester tester) => tester.widget<Container>(
      find.descendant(
        of: find.byType(DVBox),
        matching: find.byType(Container),
      ).first,
    );

Future<void> pump(WidgetTester tester, DVModifier modifier) =>
    tester.pumpWidget(
      MaterialApp(home: DVBox(const SizedBox(width: 80, height: 80), modifier)),
    );

void main() {
  testWidgets('a rounded box clips to its own corners',
      (WidgetTester tester) async {
    await pump(tester, const DVModifier().rounded(12));

    expect(boxOf(tester).clipBehavior, Clip.antiAlias);
  });

  testWidgets('corners that differ are clipped too',
      (WidgetTester tester) async {
    // A sheet rounded at the top is the same problem: the child squares off
    // the two corners the sheet rounds.
    await pump(
      tester,
      const DVModifier().radius(
        const BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    expect(boxOf(tester).clipBehavior, Clip.antiAlias);
  });

  testWidgets('a square box clips nothing', (WidgetTester tester) async {
    await pump(
      tester,
      const DVModifier().backgroundColor(const Color(0xFF112233)),
    );

    expect(boxOf(tester).clipBehavior, Clip.none);
  });

  testWidgets('an animated box clips the same way',
      (WidgetTester tester) async {
    // The animated branch is a second Container built from the same
    // modifier, and a rule applied to one of two branches is a rounded box
    // that clips until somebody asks it to animate.
    await tester.pumpWidget(
      MaterialApp(
        home: DVBox(
          const SizedBox(width: 80, height: 80),
          const DVModifier()
              .rounded(12)
              .animate(const Duration(milliseconds: 120)),
        ),
      ),
    );

    final AnimatedContainer animated = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    expect(animated.clipBehavior, Clip.antiAlias);
  });

  testWidgets('a box can be asked to crop what is in it',
      (WidgetTester tester) async {
    // A frame that crops its content is its own decision in a design, and it
    // has nothing to do with corners: a photograph cropped by a square frame
    // is the commonest version of it. Without this the child paints outside
    // the box and the page carries an overflow stripe, which is the design
    // arriving visibly broken rather than quietly wrong.
    await pump(tester, const DVModifier().clipContent());

    expect(boxOf(tester).clipBehavior, Clip.hardEdge);
  });

  testWidgets('cropping and rounding together antialias',
      (WidgetTester tester) async {
    // Hard edges on a straight edge, antialiased on a curve. A rectangle
    // needs no smoothing and paying for it on every cropping frame is a cost
    // with nothing to show.
    await pump(tester, const DVModifier().clipContent().rounded(10));

    expect(boxOf(tester).clipBehavior, Clip.antiAlias);
  });
}
