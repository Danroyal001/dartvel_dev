// DV.Accessibility, against WCAG's published numbers.
//
// The status file recorded this section as designed with no evidence, which
// understated it: the checks were built. What was missing was any assertion
// that they compute the right thing, and contrast is the kind of calculation
// that is wrong quietly. A ratio produced by averaging channels, or by
// weighting them without linearising sRGB first, looks entirely plausible --
// it is a number between 1 and 21 that moves the right way when colours
// change. Only the published values tell the two apart.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contrast ratio', () {
    test('black on white is exactly 21:1', () {
      // The maximum the formula can produce, and the one value every
      // implementation agrees on.
      final check = DV.Accessibility.contrast(
        foreground: const Color(0xFF000000),
        background: const Color(0xFFFFFFFF),
      );

      expect(check.ratio, closeTo(21.0, 0.0001));
      expect(check.passed, isTrue);
    });

    test('a colour against itself is 1:1', () {
      final check = DV.Accessibility.contrast(
        foreground: const Color(0xFFFFFFFF),
        background: const Color(0xFFFFFFFF),
      );

      expect(check.ratio, closeTo(1.0, 0.0001));
      expect(check.passed, isFalse);
    });

    // The discriminating case. #767676 is the darkest grey that passes 4.5:1
    // on white and #777777 is one hex step darker and fails, so a formula
    // that skips the sRGB linearisation puts both on the same side of the
    // threshold while still returning believable numbers.
    test('#767676 passes AA on white and #777777 does not', () {
      final passes = DV.Accessibility.contrast(
        foreground: const Color(0xFF767676),
        background: const Color(0xFFFFFFFF),
      );
      final fails = DV.Accessibility.contrast(
        foreground: const Color(0xFF777777),
        background: const Color(0xFFFFFFFF),
      );

      expect(passes.ratio, closeTo(4.5422, 0.001));
      expect(passes.passed, isTrue);
      expect(fails.ratio, closeTo(4.4781, 0.001));
      expect(fails.passed, isFalse);
    });

    test('the channel weights are not equal', () {
      // Pure blue and pure red on white differ by more than a factor of two
      // because luminance weights green far above blue. An unweighted formula
      // would return the same ratio for both.
      final blue = DV.Accessibility.contrast(
        foreground: const Color(0xFF0000FF),
        background: const Color(0xFFFFFFFF),
      );
      final red = DV.Accessibility.contrast(
        foreground: const Color(0xFFFF0000),
        background: const Color(0xFFFFFFFF),
      );

      expect(blue.ratio, closeTo(8.5925, 0.001));
      expect(red.ratio, closeTo(3.9985, 0.001));
    });

    test('the order of the two colours does not change the ratio', () {
      // Contrast is a property of the pair. Reporting light-on-dark and
      // dark-on-light differently would fail a design for choosing a
      // background.
      final forward = DV.Accessibility.contrast(
        foreground: const Color(0xFF123456),
        background: const Color(0xFFFEDCBA),
      );
      final reverse = DV.Accessibility.contrast(
        foreground: const Color(0xFFFEDCBA),
        background: const Color(0xFF123456),
      );

      expect(forward.ratio, closeTo(reverse.ratio, 1e-12));
    });

    test('the threshold it was judged against is carried on the result', () {
      // A release gate needs to say what it required, not only that
      // something failed.
      final check = DV.Accessibility.contrast(
        foreground: const Color(0xFF777777),
        background: const Color(0xFFFFFFFF),
        requiredRatio: 3,
      );

      expect(check.requiredRatio, 3);
      expect(check.passed, isTrue,
          reason: '4.48 clears the 3:1 required of large text');
    });
  });

  group('tap targets', () {
    test('the default minimum is 48 by 48', () {
      // Material's minimum, which is stricter than the 44 of WCAG 2.5.5 and
      // of the iOS guidance. Stricter is the safe direction for a default.
      expect(DV.Accessibility.tapTarget(size: const Size(48, 48)).passed,
          isTrue);
      expect(DV.Accessibility.tapTarget(size: const Size(44, 44)).passed,
          isFalse);
    });

    test('both dimensions have to clear it', () {
      // A control 200 wide and 20 tall is as hard to hit as a small square,
      // and an implementation checking area rather than each side passes it.
      expect(DV.Accessibility.tapTarget(size: const Size(200, 20)).passed,
          isFalse);
      expect(DV.Accessibility.tapTarget(size: const Size(20, 200)).passed,
          isFalse);
    });

    test('the minimum can be relaxed to the WCAG figure', () {
      final check = DV.Accessibility.tapTarget(
        size: const Size(44, 44),
        minimumSize: const Size(44, 44),
      );

      expect(check.passed, isTrue);
      expect(check.minimumSize, const Size(44, 44));
    });
  });

  group('reports', () {
    test('a report passes only when every check does', () {
      final good = DV.Accessibility.contrast(
        foreground: const Color(0xFF000000),
        background: const Color(0xFFFFFFFF),
      );
      final bad = DV.Accessibility.tapTarget(size: const Size(10, 10));

      expect(DV.Accessibility.report(<DVAccessibilityCheck>[good]).passed,
          isTrue);
      expect(DV.Accessibility.report(<DVAccessibilityCheck>[good, bad]).passed,
          isFalse);
    });

    test('it names what failed, not just that something did', () {
      final bad = DV.Accessibility.tapTarget(size: const Size(10, 10));
      final report =
          DV.Accessibility.report(<DVAccessibilityCheck>[bad]);

      expect(report.failures, hasLength(1));
      expect(report.failures.single.name, 'tapTarget');
      expect(report.failures.single.message, isNotEmpty);
    });

    test('an empty report passes rather than throwing', () {
      // A release gate runs over whatever checks a page produced, and a page
      // with none is not a failure.
      expect(DV.Accessibility.report(const <DVAccessibilityCheck>[]).passed,
          isTrue);
    });
  });

  group('reduced motion', () {
    tearDown(() => DV.Accessibility.useReducedMotion(false));

    test('it is off until asked for, and then it stays on', () {
      expect(DV.Accessibility.reducedMotion, isFalse);

      DV.Accessibility.useReducedMotion(true);

      expect(DV.Accessibility.reducedMotion, isTrue);
    });
  });

  // The modifiers store a label and the build applies a Semantics widget. A
  // stored label that never reached the tree would be the worst kind of
  // accessibility bug: the API reads as though the app is labelled, and a
  // screen reader announces nothing. These read the semantics tree itself.
  group('semantic modifiers reach the tree', () {
    testWidgets('a label is announced', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DVBox(const DVText('Submit')).modifier(
            const DVModifier()
                .semanticLabel('Submit order')
                .semanticHint('Sends the order for processing')
                .semanticButton(),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Submit order'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a labelled box replaces its child in the tree, not adds to it',
        (WidgetTester tester) async {
      // excludeSemantics is on when a label is set. That is right for a
      // control whose accessible name differs from its visible text, and it
      // means anything interactive inside a labelled box disappears from a
      // screen reader. Asserted because it is a trap worth knowing about
      // rather than discovering.
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DVBox(const DVText('Raw text'))
              .modifier(const DVModifier().semanticLabel('Outer label')),
        ),
      );

      expect(find.bySemanticsLabel('Outer label'), findsOneWidget);
      expect(find.bySemanticsLabel('Raw text'), findsNothing);
      handle.dispose();
    });

    testWidgets('an unlabelled box leaves its child audible',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DVBox(const DVText('Raw text')),
        ),
      );

      expect(find.bySemanticsLabel('Raw text'), findsOneWidget);
      handle.dispose();
    });
  });
}
