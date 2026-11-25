// The one check every animation Dartvel runs goes through.
//
// Studio's toggles, the pulsing status line and the page transitions call
// dvMotionDuration / dvReducedMotion rather than each reading MediaQuery its
// own way: the per-site checks read `disableAnimations` only, and missed iOS
// Reduce Motion (`MediaQueryData.reduceMotion`, Flutter 3.50).
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/accessibility/reduced_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> contextUnder(WidgetTester tester, MediaQueryData data) async {
  late BuildContext captured;
  await tester.pumpWidget(MediaQuery(
    data: data,
    child: Builder(builder: (BuildContext context) {
      captured = context;
      return const SizedBox();
    }),
  ));
  return captured;
}

void main() {
  const Duration motion = Duration(milliseconds: 120);

  tearDown(() => const DVAccessibility().clearReducedMotion());

  testWidgets('Reduce Motion takes the duration to zero', (WidgetTester tester) async {
    final BuildContext context =
        await contextUnder(tester, const MediaQueryData(reduceMotion: true));
    expect(dvReducedMotion(context), isTrue);
    expect(dvMotionDuration(context, motion), Duration.zero);
  });

  testWidgets('so does Remove animations', (WidgetTester tester) async {
    final BuildContext context =
        await contextUnder(tester, const MediaQueryData(disableAnimations: true));
    expect(dvMotionDuration(context, motion), Duration.zero);
  });

  testWidgets('so does the application override', (WidgetTester tester) async {
    DV.Accessibility.useReducedMotion(true);
    final BuildContext context = await contextUnder(tester, const MediaQueryData());
    expect(dvMotionDuration(context, motion), Duration.zero);
  });

  testWidgets('otherwise the duration is kept', (WidgetTester tester) async {
    final BuildContext context = await contextUnder(tester, const MediaQueryData());
    expect(dvReducedMotion(context), isFalse);
    expect(dvMotionDuration(context, motion), motion);
  });

  testWidgets('with no widget to ask, the platform Reduce Motion feature counts', (WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    expect(dvPlatformReducedMotion(), isTrue);
  });
}
