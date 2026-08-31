// DV.Platform.screen has to be a media query, not a snapshot of the window.
//
// It was neither reactive nor scoped: every getter read
// `ui.PlatformDispatcher.instance.views.first` directly. Reading it from a
// build method therefore registered no dependency, so the widget was never
// rebuilt when the window changed size -- it rendered at whatever the size
// happened to be on the first frame and stayed there. That is why application
// code kept reaching past it for MediaQuery, and why "responsive by default"
// did not hold: the primitives could not see a resize.
//
// `context.screen` is the reactive surface. It reads MediaQuery, so it takes
// a dependency and rebuilds, and it sees a MediaQuery an ancestor overrode
// rather than the raw window behind it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders [build] at a given logical size, the way a device would.
Future<void> at(
  WidgetTester tester,
  Size size,
  Widget Function(BuildContext context) build,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Builder(builder: build)),
  );
}

void main() {
  group('breakpoints', () {
    testWidgets('a phone is mobile', (WidgetTester tester) async {
      late DVBreakpoint seen;
      await at(tester, const Size(390, 844), (BuildContext context) {
        seen = context.screen.breakpoint;
        return const SizedBox();
      });
      expect(seen, DVBreakpoint.mobile);
    });

    testWidgets('a tablet is tablet', (WidgetTester tester) async {
      late DVBreakpoint seen;
      await at(tester, const Size(900, 1200), (BuildContext context) {
        seen = context.screen.breakpoint;
        return const SizedBox();
      });
      expect(seen, DVBreakpoint.tablet);
    });

    testWidgets('a laptop is desktop', (WidgetTester tester) async {
      late DVBreakpoint seen;
      await at(tester, const Size(1440, 900), (BuildContext context) {
        seen = context.screen.breakpoint;
        return const SizedBox();
      });
      expect(seen, DVBreakpoint.desktop);
    });
  });

  testWidgets('it rebuilds when the window resizes', (WidgetTester tester) async {
    // The whole point. The old getters took no dependency, so this second
    // pump reported the first size -- a layout chosen once and never revised.
    final List<DVBreakpoint> seen = <DVBreakpoint>[];
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (BuildContext context) {
          seen.add(context.screen.breakpoint);
          return const SizedBox();
        }),
      ),
    );
    expect(seen.last, DVBreakpoint.mobile);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();

    expect(seen.last, DVBreakpoint.desktop,
        reason: 'a resize must reach the widget that asked about the screen');
  });

  testWidgets('it sees an overridden MediaQuery, not the raw window',
      (WidgetTester tester) async {
    // A pane, a dialog, a preview frame: anything that narrows MediaQuery for
    // its subtree. Reading the window behind it gives a child the size of the
    // whole screen and it lays out for space it does not have.
    late DVBreakpoint seen;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: Builder(builder: (BuildContext context) {
            seen = context.screen.breakpoint;
            return const SizedBox();
          }),
        ),
      ),
    );

    expect(seen, DVBreakpoint.mobile);
  });

  group('choosing a value per breakpoint', () {
    testWidgets('it falls back down the ladder', (WidgetTester tester) async {
      // Only `mobile` is required. A value given for desktop alone still has
      // to answer on a phone, or every call site needs all four.
      late double phone;
      late double laptop;

      await at(tester, const Size(390, 844), (BuildContext context) {
        phone = context.screen.value<double>(mobile: 16, desktop: 64);
        return const SizedBox();
      });
      await at(tester, const Size(1440, 900), (BuildContext context) {
        laptop = context.screen.value<double>(mobile: 16, desktop: 64);
        return const SizedBox();
      });

      expect(phone, 16);
      expect(laptop, 64);
    });

    testWidgets('a tablet takes the mobile value when none is given',
        (WidgetTester tester) async {
      late double value;
      await at(tester, const Size(900, 1200), (BuildContext context) {
        value = context.screen.value<double>(mobile: 16, desktop: 64);
        return const SizedBox();
      });
      // Not 64: a tablet is closer to a phone than to a 27-inch display, and
      // guessing upward is what overflows.
      expect(value, 16);
    });
  });

  group('reduced motion', () {
    testWidgets('it reads the reader setting, not just the app override',
        (WidgetTester tester) async {
      // This is an accessibility setting people turn on because movement
      // makes them ill. Reporting false unless the application remembered to
      // call useReducedMotion is the same as ignoring it.
      late bool reduced;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(builder: (BuildContext context) {
              reduced = context.screen.reducedMotion;
              return const SizedBox();
            }),
          ),
        ),
      );
      expect(reduced, isTrue);
    });

    testWidgets('an explicit override still wins', (WidgetTester tester) async {
      const DVAccessibility().useReducedMotion(true);
      addTearDown(() => const DVAccessibility().clearReducedMotion());

      late bool reduced;
      await at(tester, const Size(1440, 900), (BuildContext context) {
        reduced = context.screen.reducedMotion;
        return const SizedBox();
      });
      expect(reduced, isTrue);
    });
  });

  testWidgets('safe areas come through', (WidgetTester tester) async {
    late EdgeInsets safe;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: Builder(builder: (BuildContext context) {
            safe = context.screen.safeArea;
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(safe.top, 47);
    expect(safe.bottom, 34);
  });

  testWidgets('orientation follows the box, not the platform',
      (WidgetTester tester) async {
    late Orientation seen;
    await at(tester, const Size(844, 390), (BuildContext context) {
      seen = context.screen.orientation;
      return const SizedBox();
    });
    expect(seen, Orientation.landscape);
  });
}
