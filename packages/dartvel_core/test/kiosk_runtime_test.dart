// Leaving a kiosk, and failing to.
//
// The exit method is the whole of "cannot be left by the user": staff get out
// with a PIN, and everyone else does not. The rules that make that true are
// the counting ones -- maxAttempts, then a lockout that outlasts the person
// trying -- and none of them existed.
//
// A build with no kiosk policy has no kiosk runtime: the calls exist, report
// DV-KIOSK-005 and change nothing. That is the case worth getting right first,
// because it is what every non-kiosk application hits.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy policyWith(Map<String, Object?> exit, {String scope = 'device'}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': scope,
        'home': '/welcome',
        'exit': exit,
      },
    });

void main() {
  group('with no policy', () {
    late DVKioskRuntime runtime;
    setUp(() => runtime = DVKioskRuntime(DVKioskPolicy.parse(null)));

    test('it is off, and stays off', () async {
      expect(runtime.state.value, DVKioskState.off);
      await runtime.resume();
      expect(runtime.state.value, DVKioskState.off);
    });

    test('an exit attempt reports DV-KIOSK-005 and changes nothing', () async {
      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.granted, isFalse);
      expect(result.code, 'DV-KIOSK-005');
      expect(runtime.state.value, DVKioskState.off);
    });

    test('DV-KIOSK-005 is a warning: the call was written for nothing', () {
      expect(DVDiagnostics.find('DV-KIOSK-005')!.level, 'warning');
    });
  });

  group('entering and leaving', () {
    late DVKioskRuntime runtime;
    setUp(() {
      runtime = DVKioskRuntime(
        policyWith(<String, Object?>{
          'method': 'pin',
          'pin': 'secret:PIN',
          'maxAttempts': 3,
          'lockoutFor': '10m',
        }),
        readSecret: (String name) async => name == 'PIN' ? '4821' : null,
      );
    });

    test('resume puts it in kiosk', () async {
      await runtime.resume();
      expect(runtime.state.value, DVKioskState.active);
    });

    test('the right PIN leaves for staff mode', () async {
      await runtime.resume();

      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.granted, isTrue);
      expect(runtime.state.value, DVKioskState.staffMode);
    });

    test('a wrong PIN does not, and says so without saying why', () async {
      await runtime.resume();

      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('0000'));

      expect(result.granted, isFalse);
      expect(runtime.state.value, DVKioskState.active);
      expect(result.message, isNot(contains('4821')));
    });

    test('resuming from staff mode goes back into kiosk', () async {
      await runtime.resume();
      await runtime.exit(const DVKioskExitRequest.pin('4821'));
      await runtime.resume();

      expect(runtime.state.value, DVKioskState.active);
    });

    test('a PIN request against an adminAuth policy is refused', () async {
      final DVKioskRuntime other = DVKioskRuntime(
          policyWith(<String, Object?>{'method': 'adminAuth'}));
      await other.resume();

      final DVKioskExitResult result =
          await other.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.granted, isFalse,
          reason: 'the declared method is the only way out');
    });
  });

  group('lockout', () {
    late DVKioskRuntime runtime;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 9, 1, 12);
      runtime = DVKioskRuntime(
        policyWith(<String, Object?>{
          'method': 'pin',
          'pin': 'secret:PIN',
          'maxAttempts': 3,
          'lockoutFor': '10m',
        }),
        readSecret: (String name) async => '4821',
        clock: () => now,
      );
    });

    Future<void> wrong(int times) async {
      for (var i = 0; i < times; i++) {
        await runtime.exit(const DVKioskExitRequest.pin('0000'));
      }
    }

    test('it takes maxAttempts wrong PINs to lock out', () async {
      await runtime.resume();
      await wrong(2);
      expect(runtime.state.value, DVKioskState.active);

      await wrong(1);
      expect(runtime.state.value, DVKioskState.locked);
    });

    test('a locked kiosk refuses even the right PIN', () async {
      // Otherwise the lockout counts attempts and stops nothing.
      await runtime.resume();
      await wrong(3);

      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.granted, isFalse);
      expect(result.code, 'DV-KIOSK-003');
    });

    test('the lockout ends after lockoutFor, not before', () async {
      await runtime.resume();
      await wrong(3);

      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect((await runtime.exit(const DVKioskExitRequest.pin('4821'))).granted,
          isFalse);

      now = now.add(const Duration(seconds: 2));
      expect((await runtime.exit(const DVKioskExitRequest.pin('4821'))).granted,
          isTrue);
    });

    test('a correct PIN forgets the failed attempts', () async {
      // Otherwise two wrong entries today and one tomorrow lock a kiosk out
      // for no reason anyone can see.
      await runtime.resume();
      await wrong(2);
      await runtime.exit(const DVKioskExitRequest.pin('4821'));
      await runtime.resume();
      await wrong(2);

      expect(runtime.state.value, DVKioskState.active,
          reason: 'the counter restarted');
    });

    test('the lockout survives a resume, so it cannot be cleared by one',
        () async {
      await runtime.resume();
      await wrong(3);
      await runtime.resume();

      expect((await runtime.exit(const DVKioskExitRequest.pin('4821'))).granted,
          isFalse);
    });
  });

  group('session reset', () {
    late DVKioskRuntime runtime;
    setUp(() => runtime = DVKioskRuntime(DVKioskPolicy.parse(<String, Object?>{
          'kiosk': <String, Object?>{
            'enabled': true,
            'home': '/welcome',
            'session': <String, Object?>{
              'clearOnReset': <String>['signals', 'forms'],
            },
          },
        })));

    test('it passes through resetting and back to active', () async {
      // The specification names the transition, and a workspace watching the
      // signal needs the intermediate state to show a wipe is happening.
      await runtime.resume();
      final List<DVKioskState> seen = <DVKioskState>[];
      runtime.state.addListener(() => seen.add(runtime.state.value));

      await runtime.resetSession(reason: DVKioskResetReason.idle);

      expect(seen, <DVKioskState>[DVKioskState.resetting, DVKioskState.active]);
    });

    test('it reports what it cleared and where it went', () async {
      await runtime.resume();
      final DVKioskReset reset =
          await runtime.resetSession(reason: DVKioskResetReason.idle);

      expect(reset.cleared,
          <DVKioskClearable>{DVKioskClearable.signals, DVKioskClearable.forms});
      expect(reset.home, '/welcome');
      expect(reset.reason, DVKioskResetReason.idle);
    });

    test('resetting a kiosk that is off does nothing', () async {
      final DVKioskRuntime off = DVKioskRuntime(DVKioskPolicy.parse(null));
      final DVKioskReset reset =
          await off.resetSession(reason: DVKioskResetReason.idle);

      expect(reset.cleared, isEmpty);
      expect(off.state.value, DVKioskState.off);
    });
  });
}
