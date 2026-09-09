// The two reset reasons nothing ever passed.
//
// DVKioskResetReason has four values and the runtime used two of them. A
// listener switching on the reason -- to audit differently, or to skip a
// welcome animation on a restart -- could never see `startup` or `staffExit`,
// so both were documentation.
//
// Neither is a label looking for an event. Each names a moment where a
// session was carried across when it should have been dropped:
//
// `staffExit` is the specification's own rule that resume() returns to kiosk
// and resets the session. Without it an engineer's diagnostics page, their
// filled form, and whatever they signed into stayed on the screen for the
// next person who walked up.
//
// `startup` is the restart. A kiosk is supervised -- systemd on eLinux, lock
// task on Android -- so a crash mid-order brings the process back in seconds,
// and the parts of a session that outlive a process (the shared store, the
// client cache, an auth token) come back with it. The kiosk then shows the
// previous customer's session to whoever is standing there.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy _policy({bool enabled = true}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': enabled,
        'home': '/welcome',
        'session': <String, Object?>{
          'clearOnReset': <String>['signals', 'forms', 'clientCache'],
        },
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

void main() {
  late List<DVKioskReset> resets;
  late List<Set<DVKioskClearable>> cleared;

  DVKioskRuntime runtime({bool enabled = true}) {
    final DVKioskRuntime r = DVKioskRuntime(
      _policy(enabled: enabled),
      readSecret: (String _) async => '4821',
      clear: (Set<DVKioskClearable> what) async => cleared.add(what),
    );
    r.resets.listen(resets.add);
    addTearDown(r.stop);
    return r;
  }

  setUp(() {
    resets = <DVKioskReset>[];
    cleared = <Set<DVKioskClearable>>[];
  });

  group('starting up', () {
    test('the first entry into kiosk drops whatever survived the restart',
        () async {
      final DVKioskRuntime r = runtime();

      await r.resume();

      expect(resets.single.reason, DVKioskResetReason.startup);
      expect(cleared.single, contains(DVKioskClearable.clientCache));
      expect(resets.single.home, '/welcome');
      expect(r.state.value, DVKioskState.active);
    });

    test('resuming again does not reset the customer standing there',
        () async {
      // The obvious wrong implementation resets on every resume. A kiosk
      // that wipes a half-filled order because something called resume()
      // twice is worse than one that never resets at all: the second is
      // visible on the first test, and this one only happens to a customer.
      final DVKioskRuntime r = runtime();
      await r.resume();
      resets.clear();
      cleared.clear();

      await r.resume();

      expect(resets, isEmpty);
      expect(cleared, isEmpty);
    });

    test('a build with no kiosk policy resets nothing', () async {
      final DVKioskRuntime r = runtime(enabled: false);

      await r.resume();

      expect(resets, isEmpty);
      expect(r.state.value, DVKioskState.off);
    });
  });

  group('coming back from staff mode', () {
    test('the engineer session does not stay on screen', () async {
      final DVKioskRuntime r = runtime();
      await r.resume();
      await r.exit(const DVKioskExitRequest.pin('4821'));
      expect(r.state.value, DVKioskState.staffMode);
      resets.clear();
      cleared.clear();

      await r.resume();

      expect(resets.single.reason, DVKioskResetReason.staffExit);
      expect(cleared.single, contains(DVKioskClearable.forms));
      expect(r.state.value, DVKioskState.active);
    });

    test('the reset passes through resetting, so a watcher sees the wipe',
        () async {
      final DVKioskRuntime r = runtime();
      await r.resume();
      await r.exit(const DVKioskExitRequest.pin('4821'));
      final List<DVKioskState> seen = <DVKioskState>[];
      r.state.addListener(() => seen.add(r.state.value));

      await r.resume();

      expect(seen, <DVKioskState>[
        DVKioskState.resetting,
        DVKioskState.active,
      ]);
    });

    test('a lockout still outlasts a resume', () async {
      // Resetting the session on the way back must not become a way to
      // clear the count: five wrong PINs and a resume would be a kiosk
      // anyone can stand in front of until it opens.
      final DVKioskRuntime r = runtime();
      await r.resume();
      for (int i = 0; i < 5; i++) {
        await r.exit(const DVKioskExitRequest.pin('0000'));
      }
      expect(r.state.value, DVKioskState.locked);

      await r.resume();
      final DVKioskExitResult result =
          await r.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.granted, isFalse);
      expect(result.code, 'DV-KIOSK-003');
    });
  });
}
