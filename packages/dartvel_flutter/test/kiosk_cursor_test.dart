// The kiosk hides the pointer, which is what display.hideCursor asks for and
// nothing did.
//
// A pointer nobody can move is what a touchscreen kiosk shows when the cursor
// is left on: it sits wherever the last mouse left it and reads as a frozen
// screen. The key was in the specification with three modes and the parser
// walked straight past it.
//
// The decision is tested in core, where it is a function of the mode and
// whether a pointing device is attached. This is the other half: that the
// host actually applies it.
// Everything here comes through the dartvel_flutter barrel, which is what
// an application imports; naming dartvel_core as well is an unnecessary
// import and flutter analyze makes that fatal.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVKioskRuntime _kiosk(String? hideCursor) => DVKioskRuntime(
      DVKioskPolicy.parse(<String, Object?>{
        'kiosk': <String, Object?>{
          'enabled': true,
          if (hideCursor != null)
            'display': <String, Object?>{'hideCursor': hideCursor},
        },
      }),
    );

Finder get _hidden => find.byWidgetPredicate(
      (Widget w) => w is MouseRegion && w.cursor == SystemMouseCursors.none,
    );

Future<void> _pump(WidgetTester tester, DVKioskRuntime runtime) async {
  addTearDown(runtime.stop);
  await tester.pumpWidget(
    MaterialApp(
      home: DVKioskHost(
        runtime: runtime,
        onHome: (String _) {},
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

void main() {
  testWidgets('always hides it', (WidgetTester tester) async {
    await _pump(tester, _kiosk('always'));

    expect(_hidden, findsOneWidget);
  });

  testWidgets('never leaves it alone', (WidgetTester tester) async {
    await _pump(tester, _kiosk('never'));

    expect(_hidden, findsNothing);
  });

  testWidgets('auto hides it when no pointing device is attached',
      (WidgetTester tester) async {
    // Which is the case in a test, and the case on the touchscreen the mode
    // exists for. "Touch-only" cannot be read off the build target: a kiosk
    // on a Linux box with a touchscreen is a desktop build.
    await _pump(tester, _kiosk('auto'));

    expect(WidgetsBinding.instance.mouseTracker.mouseIsConnected, isFalse);
    expect(_hidden, findsOneWidget);
  });

  testWidgets('auto is the default, so a policy that says nothing still hides',
      (WidgetTester tester) async {
    await _pump(tester, _kiosk(null));

    expect(_hidden, findsOneWidget);
  });

  testWidgets('a kiosk that is off hides nothing', (WidgetTester tester) async {
    // The host returns the child untouched when the policy is disabled, and
    // a cursor hidden by a kiosk nobody enabled would be a pointer that
    // vanishes on an ordinary desktop application.
    final DVKioskRuntime runtime = DVKioskRuntime(
      DVKioskPolicy.parse(<String, Object?>{
        'kiosk': <String, Object?>{
          'enabled': false,
          'display': <String, Object?>{'hideCursor': 'always'},
        },
      }),
    );
    await _pump(tester, runtime);

    expect(_hidden, findsNothing);
  });
}
