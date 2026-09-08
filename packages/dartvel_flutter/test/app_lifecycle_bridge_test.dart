// DV.lifecycle.app reported two of its ten states.
//
// Only booting and ready were ever set, both by the generated runtime at
// start. So an application observing the signal to save a draft when it goes
// into the background never saw backgrounded, and one refreshing on the way
// back never saw the return. The enum said those states existed and nothing
// produced them, which reads as an application that is never backgrounded.
//
// Flutter reports exactly this through its own lifecycle, so what was
// missing is the mapping -- and the mapping is where the judgement is: two
// of Flutter's five states are not what they look like.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what a platform state means', () {
    test('paused is the background', () {
      expect(
        dvAppLifecycleFor(AppLifecycleState.paused),
        DVAppLifecycle.backgrounded,
      );
    });

    test('hidden is the background too', () {
      // Flutter sends hidden before paused on every platform now, and on
      // desktop it is the whole of it: a window that is covered or minimised
      // never reaches paused. An application that only listened for paused
      // would save nothing on a desktop.
      expect(
        dvAppLifecycleFor(AppLifecycleState.hidden),
        DVAppLifecycle.backgrounded,
      );
    });

    test('resumed is ready, not resuming', () {
      // resumed is the settled state, not the transition into it. Reporting
      // resuming for it would name a moment that has already passed.
      expect(
        dvAppLifecycleFor(AppLifecycleState.resumed),
        DVAppLifecycle.ready,
      );
    });

    test('detached is shutting down', () {
      expect(
        dvAppLifecycleFor(AppLifecycleState.detached),
        DVAppLifecycle.shuttingDown,
      );
    });

    test('inactive is not the background, and reports nothing', () {
      // inactive is a notification banner, the app switcher, a phone call --
      // the application is on screen and about to be interrupted. Calling it
      // backgrounded would have an application save a draft and flush its
      // state every time a message arrives, and would make the signal say
      // the app went away when it did not.
      expect(dvAppLifecycleFor(AppLifecycleState.inactive), isNull);
    });
  });

  group('the bridge drives the signal', () {
    tearDown(dvStopAppLifecycleBridge);

    testWidgets('going to the background reports it', (tester) async {
      dvStartAppLifecycleBridge();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);

      expect(DV.lifecycle.app.value, DVAppLifecycle.backgrounded);
    });

    testWidgets('coming back reports ready', (tester) async {
      dvStartAppLifecycleBridge();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(DV.lifecycle.app.value, DVAppLifecycle.ready);
    });

    testWidgets('an interruption changes nothing', (tester) async {
      dvStartAppLifecycleBridge();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

      expect(DV.lifecycle.app.value, DVAppLifecycle.ready);
    });

    testWidgets('stopping it stops the reports', (tester) async {
      // A second bridge over the same binding would report every transition
      // twice, and a test that started one and left it would leak into the
      // next.
      dvStartAppLifecycleBridge();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      dvStopAppLifecycleBridge();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);

      expect(DV.lifecycle.app.value, DVAppLifecycle.ready);
    });

    testWidgets('starting twice does not report twice', (tester) async {
      final List<DVAppLifecycle> seen = <DVAppLifecycle>[];
      dvStartAppLifecycleBridge();
      dvStartAppLifecycleBridge();
      DV.lifecycle.app.listen(seen.add);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      expect(seen, <DVAppLifecycle>[DVAppLifecycle.backgrounded]);
    });
  });
}
