// The kiosk darkens its own surface, which display.screenDim asked for.
//
// The decision -- how long, and whether the configuration can ever fire --
// is tested in core, where it is a function of a clock. This is the other
// half: that the host draws it, that it sits over everything including the
// countdown, and that the tap which wakes the screen is spent waking it.
//
// Everything here comes through the dartvel_flutter barrel, which is what an
// application imports; naming dartvel_core as well is an unnecessary import
// and flutter analyze makes that fatal.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

late DateTime now;

DVKioskRuntime kioskThatDims({String onIdle = 'reset'}) {
  now = DateTime(2026, 1, 1, 9);
  return DVKioskRuntime(
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'session': <String, Object?>{'idleTimeout': '90s', 'onIdle': onIdle},
        'display': <String, Object?>{'screenDim': '30s'},
      },
    }),
    clock: () => now,
  );
}

Finder get dim => find.byWidgetPredicate(
      (Widget w) => w is ColoredBox && w.color == const Color(0xE6000000),
    );

Future<void> pump(WidgetTester tester, DVKioskRuntime runtime) async {
  addTearDown(runtime.stop);
  await tester.pumpWidget(
    MaterialApp(
      home: DVKioskHost(
        runtime: runtime,
        onHome: (String _) {},
        child: Center(
          child: TextButton(onPressed: () {}, child: const Text('Buy')),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('nothing is drawn over a kiosk somebody is using',
      (WidgetTester tester) async {
    final DVKioskRuntime kiosk = kioskThatDims();
    await pump(tester, kiosk);
    await kiosk.resume();
    await tester.pump();

    expect(dim, findsNothing);
  });

  testWidgets('the surface darkens once the clock says so',
      (WidgetTester tester) async {
    final DVKioskRuntime kiosk = kioskThatDims();
    await pump(tester, kiosk);
    await kiosk.resume();

    now = now.add(const Duration(seconds: 31));
    await kiosk.tick();
    await tester.pump();

    expect(dim, findsOneWidget);
  });

  testWidgets('the tap that wakes it is spent waking it',
      (WidgetTester tester) async {
    // Somebody touching a dark panel means "come back", not "buy the thing
    // under my finger" -- and they cannot see what is under their finger,
    // which is the whole problem with letting the tap through.
    bool bought = false;
    final DVKioskRuntime kiosk = kioskThatDims();
    addTearDown(kiosk.stop);
    await tester.pumpWidget(
      MaterialApp(
        home: DVKioskHost(
          runtime: kiosk,
          onHome: (String _) {},
          child: Center(
            child: TextButton(
              onPressed: () => bought = true,
              child: const Text('Buy'),
            ),
          ),
        ),
      ),
    );
    await kiosk.resume();
    now = now.add(const Duration(seconds: 31));
    await kiosk.tick();
    await tester.pump();
    expect(dim, findsOneWidget);

    await tester.tap(find.text('Buy'), warnIfMissed: false);
    await tester.pump();

    expect(bought, isFalse, reason: 'the tap reached the page underneath');
    expect(dim, findsNothing, reason: 'the tap did not wake the screen');
  });

  testWidgets('a kiosk that configured no dim never darkens',
      (WidgetTester tester) async {
    final DVKioskRuntime kiosk = DVKioskRuntime(
      DVKioskPolicy.parse(<String, Object?>{
        'kiosk': <String, Object?>{
          'enabled': true,
          'session': <String, Object?>{'idleTimeout': '90s'},
        },
      }),
      clock: () => now,
    );
    now = DateTime(2026, 1, 1, 9);
    await pump(tester, kiosk);
    await kiosk.resume();

    now = now.add(const Duration(seconds: 89));
    await kiosk.tick();
    await tester.pump();

    expect(dim, findsNothing);
  });
}
