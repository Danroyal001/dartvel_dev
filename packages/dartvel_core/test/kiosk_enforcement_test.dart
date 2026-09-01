// What a target actually honours, as against what the policy asked for.
//
// Kiosk is the one capability with no "present it another way" fallback: you
// cannot lock a watch a different way. So the honest answer is a strength
// label per target and a diagnostic when the answer is weaker than the ask --
// a kiosk that reported success while the user could swipe out of it would be
// worse than one that said it could not.
//
// Every row here is from the specification's target table, and the footnotes
// are the interesting part: Android without a device owner can be exited with
// a known gesture, and a browser reserves Esc no matter what the page does.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy policy({
  String scope = 'device',
  Map<String, Object?> input = const <String, Object?>{},
  Map<String, Object?> exit = const <String, Object?>{},
}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': scope,
        'input': input,
        'exit': exit,
      },
    });

void main() {
  group('strength per target', () {
    test('an eLinux image locks the device', () {
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
          policy: policy(), target: DVKioskTarget.sonyELinux);

      expect(e.strength, DVKioskStrength.device);
      expect(e.degradation, DVKioskDegradation.none);
    });

    test('Android with a device owner locks it; without one it supervises',
        () {
      expect(
          DVKioskEnforcement.resolve(
                  policy: policy(), target: DVKioskTarget.androidDeviceOwner)
              .strength,
          DVKioskStrength.device);

      final DVKioskEnforcement pinned = DVKioskEnforcement.resolve(
          policy: policy(), target: DVKioskTarget.androidScreenPinning);

      // Screen pinning can be left with a gesture the user may know.
      expect(pinned.strength, DVKioskStrength.supervised);
      expect(pinned.degradation, DVKioskDegradation.enforcementReduced);
      expect(pinned.code, 'DV-KIOSK-001');
    });

    test('macOS and the web are fullscreen only', () {
      // The browser reserves Esc and cannot be prevented from leaving
      // fullscreen, so anything stronger would be a claim it cannot keep.
      for (final DVKioskTarget target
          in <DVKioskTarget>[DVKioskTarget.macos, DVKioskTarget.web]) {
        expect(
            DVKioskEnforcement.resolve(policy: policy(), target: target)
                .strength,
            DVKioskStrength.fullscreenOnly,
            reason: '$target');
      }
    });

    test('a dedicated browser kiosk mode raises the web to device', () {
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(),
        target: DVKioskTarget.web,
        browserKioskDetected: true,
      );

      expect(e.strength, DVKioskStrength.device);
      expect(e.degradation, DVKioskDegradation.none);
    });

    test('a watch and a browser extension cannot be kiosks at all', () {
      for (final DVKioskTarget target in <DVKioskTarget>[
        DVKioskTarget.watch,
        DVKioskTarget.browserExtension,
      ]) {
        final DVKioskEnforcement e =
            DVKioskEnforcement.resolve(policy: policy(), target: target);

        expect(e.supported, isFalse, reason: '$target');
        expect(e.code, 'DV-KIOSK-004', reason: '$target');
      }
    });

    test('DV-KIOSK-004 is info: the API still exists there', () {
      expect(DVDiagnostics.find('DV-KIOSK-004')!.level, 'info');
    });

    test('a disabled policy enforces nothing anywhere', () {
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: DVKioskPolicy.parse(null),
        target: DVKioskTarget.sonyELinux,
      );
      expect(e.strength, DVKioskStrength.none);
    });
  });

  group('display scope', () {
    test('it needs addressable displays, and degrades without them', () {
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(scope: 'display'),
        target: DVKioskTarget.linuxDesktop,
        displayKiosk: false,
      );

      expect(e.scopeHonoured, isFalse,
          reason: 'it becomes a fullscreen page in the current surface');
      expect(e.degradation, DVKioskDegradation.enforcementReduced);
    });

    test('and is honoured where they exist', () {
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(scope: 'display'),
        target: DVKioskTarget.linuxDesktop,
        displayKiosk: true,
      );

      expect(e.scopeHonoured, isTrue);
    });

    test('blocking hardware keys there is device-wide, and says so', () {
      // A keyboard is a device and a touchscreen is a display. Blocking keys
      // for one display is not a thing an OS can do, so it is the whole
      // device -- which the staff terminal beside it will notice.
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(
          scope: 'display',
          input: <String, Object?>{'hardwareKeys': 'block'},
        ),
        // eLinux multi-head: device strength, so nothing masks the note.
        target: DVKioskTarget.sonyELinux,
        displayKiosk: true,
      );

      expect(e.inputScope, DVKioskInputScope.device);
      expect(e.codes, contains('DV-KIOSK-010'));
    });

    test('the honest default leaves them alone', () {
      // display scope defaults hardwareKeys to passthrough, so nothing is
      // widened and nothing is reported.
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(scope: 'display'),
        target: DVKioskTarget.sonyELinux,
        displayKiosk: true,
      );

      expect(e.inputScope, DVKioskInputScope.display);
      expect(e.degradation, DVKioskDegradation.none);
    });

    test('input scope is not reported at all in device scope', () {
      // Everything is device-wide there, so "widened" would be meaningless.
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(input: <String, Object?>{'hardwareKeys': 'block'}),
        target: DVKioskTarget.sonyELinux,
      );

      expect(e.inputScope, DVKioskInputScope.device);
      expect(e.degradation, DVKioskDegradation.none);
    });
  });

  group('the exit method', () {
    test('gesture+pin falls back to pin where there is no touch', () {
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(
            exit: <String, Object?>{
              'method': 'gesture+pin',
              'pin': 'secret:PIN',
            }),
        // A device-strength target, so the exit note is not masked by a
        // reduction that would be reported first.
        target: DVKioskTarget.sonyELinux,
        hasTouch: false,
      );

      expect(e.exitMethod, DVKioskExitMethod.pin);
      expect(e.code, 'DV-KIOSK-002');
    });

    test('and is kept where there is', () {
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(
            exit: <String, Object?>{
              'method': 'gesture+pin',
              'pin': 'secret:PIN',
            }),
        target: DVKioskTarget.sonyELinux,
        hasTouch: true,
      );

      expect(e.exitMethod, DVKioskExitMethod.gesturePin);
      expect(e.degradation, DVKioskDegradation.none);
    });
  });

  group('what it reports once', () {
    test('the most severe degradation wins, so boot says one thing', () {
      // Enforcement reduced matters more than an input scope note: the user
      // can leave. Reporting both at boot would bury it.
      final DVKioskEnforcement e = DVKioskEnforcement.resolve(
        policy: policy(
          scope: 'display',
          input: <String, Object?>{'hardwareKeys': 'block'},
        ),
        target: DVKioskTarget.androidScreenPinning,
        displayKiosk: false,
      );

      expect(e.degradation, DVKioskDegradation.enforcementReduced);
      expect(e.code, 'DV-KIOSK-001');
      expect(e.codes, isNot(contains('DV-KIOSK-010')),
          reason: 'display scope was not honoured, so nothing was widened');
    });

    test('every code it can emit is one the specification reserves', () {
      for (final String code in <String>[
        'DV-KIOSK-001',
        'DV-KIOSK-002',
        'DV-KIOSK-004',
        'DV-KIOSK-010',
      ]) {
        expect(DVDiagnostics.find(code), isNotNull, reason: code);
      }
    });
  });
}
