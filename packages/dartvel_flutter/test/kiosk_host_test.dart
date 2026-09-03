// The kiosk's screen-side half: activity feeds the session clock, the
// countdown shows before a reset, a reset sends the app home, and a restart
// loop lands on the diagnostics screen instead of the attract route.
//
// The runtime owns the clock; these widgets are its hands. What the tests
// hold to: any pointer or key is activity; the countdown appears only while
// the runtime is warning and says how long is left; a reset calls the
// app's go-home once, after the clear; and the diagnostics screen replaces
// the page when the watchdog reports a loop.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

DVKioskPolicy policy() => DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': '/welcome',
        'session': <String, Object?>{'idleTimeout': '60s', 'idleWarning': '10s', 'onIdle': 'reset'},
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

void main() {
  late DateTime now;
  late DVKioskRuntime runtime;
  late List<String> homes;

  setUp(() {
    now = DateTime.utc(2026, 9, 3, 12);
    runtime = DVKioskRuntime(policy(), clock: () => now, tickEvery: const Duration(days: 1));
    homes = <String>[];
  });
  tearDown(() => runtime.stop());

  Widget host({Widget? child}) => MaterialApp(
        home: DVKioskHost(
          runtime: runtime,
          onHome: (String route) => homes.add(route),
          child: child ?? const Scaffold(body: Center(child: Text('Attract'))),
        ),
      );

  Future<void> pass(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await runtime.tick();
    await tester.pump();
  }

  testWidgets('a tap or a key is activity', (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await runtime.resume();
    await pass(tester, const Duration(seconds: 55));
    expect(find.byKey(const ValueKey<String>('dv-kiosk-countdown')), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await runtime.tick();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('dv-kiosk-countdown')), findsNothing, reason: 'the tap reset the clock');

    await pass(tester, const Duration(seconds: 55));
    expect(find.byKey(const ValueKey<String>('dv-kiosk-countdown')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await runtime.tick();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('dv-kiosk-countdown')), findsNothing, reason: 'so did the key');
    runtime.stop();
  });

  testWidgets('the countdown says how long is left, and only while warning', (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await runtime.resume();
    expect(find.byKey(const ValueKey<String>('dv-kiosk-countdown')), findsNothing);
    await pass(tester, const Duration(seconds: 52));
    expect(find.textContaining('8'), findsOneWidget);
    await pass(tester, const Duration(seconds: 3));
    expect(find.textContaining('5'), findsOneWidget);
    expect(find.text('Attract'), findsOneWidget, reason: 'the page stays underneath');
    runtime.stop();
  });

  testWidgets('a reset sends the app home, once', (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await runtime.resume();
    await pass(tester, const Duration(seconds: 60));
    expect(homes, <String>['/welcome']);
    await runtime.reset(DVKioskResetReason.explicit);
    await tester.pump();
    expect(homes, <String>['/welcome', '/welcome']);
    runtime.stop();
  });

  testWidgets('a restart loop lands on the diagnostics screen', (WidgetTester tester) async {
    await tester.pumpWidget(host());
    DVKioskHost.reportRestartLoop('DV-KIOSK-008: restarted more than three times in five minutes');
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('dv-kiosk-diagnostics')), findsOneWidget);
    expect(find.textContaining('DV-KIOSK-008'), findsOneWidget);
    expect(find.text('Attract'), findsNothing);
    DVKioskHost.clearRestartLoop();
    await tester.pump();
    expect(find.text('Attract'), findsOneWidget);
  });

  testWidgets('a disabled policy is just the child', (WidgetTester tester) async {
    final DVKioskRuntime off = DVKioskRuntime(DVKioskPolicy.parse(null));
    await tester.pumpWidget(MaterialApp(
      home: DVKioskHost(runtime: off, onHome: (_) {}, child: const Text('Plain')),
    ));
    expect(find.text('Plain'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('dv-kiosk-countdown')), findsNothing);
  });

  testWidgets('the host mirrors the runtime into DV.lifecycle.kiosk', (WidgetTester tester) async {
    // A runtime the app built without the registry still shows up on the
    // lifecycle signal once a host is on screen: pages observe the kiosk the
    // way they observe the app.
    DV.lifecycle.resetForTesting();
    await tester.pumpWidget(host());
    expect(DV.lifecycle.kiosk.value, DVKioskState.off);
    await runtime.resume();
    await tester.pump();
    expect(DV.lifecycle.kiosk.value, DVKioskState.active);
    await runtime.reset(DVKioskResetReason.explicit);
    await tester.pump();
    expect(DV.lifecycle.kiosk.value, DVKioskState.active);
    runtime.stop();
    DV.lifecycle.resetForTesting();
  });
}
