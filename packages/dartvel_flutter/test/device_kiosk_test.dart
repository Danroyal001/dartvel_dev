// DV.Platform.display.kiosk: the device-scope kiosk, under the declared
// policy.
//
// A build with a device-scope kiosk policy installs it at start; from then
// on the application observes the kiosk's state, reads what this platform
// honours, resets the session, and leaves only through the declared exit
// method. A build with no policy has no kiosk here: null, and a runtime
// call on a policy that was never declared is DV-KIOSK-005's case, not a
// crash.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVKioskPolicy devicePolicy() => DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': '/welcome',
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:KIOSK_PIN'},
      },
    });

void main() {
  late List<Object?> enforced;
  setUp(() async {
    await DVPlatform.uninstallKioskPolicy();
    enforced = <Object?>[];
    DVNativeBridge.register('kiosk.enforce', (Object? a) {
      enforced.add(a);
      return <String, Object?>{'blocked': <String>['Alt+tab'], 'confined': true};
    });
    DVNativeBridge.register('kiosk.release', (Object? _) => true);
  });
  tearDown(() async {
    await DVPlatform.uninstallKioskPolicy();
    DVNativeBridge.unregister('kiosk.enforce');
    DVNativeBridge.unregister('kiosk.release');
  });

  test('no declared policy, no kiosk', () {
    expect(DV.Platform.display.kiosk, isNull);
  });

  test('installing the declared policy makes the kiosk, active and enforced', () async {
    await DVPlatform.installKioskPolicy(devicePolicy(), readSecret: (String _) async => '4821');
    final DVDeviceKiosk kiosk = DV.Platform.display.kiosk!;
    expect(kiosk.state.value, DVKioskState.active);
    expect(kiosk.enforcement.supported, isTrue);
    expect(kiosk.enforced, isNotNull);
    expect(kiosk.enforced!.blocked, contains('Alt+tab'));
    expect(enforced, hasLength(1), reason: 'the platform was asked to hold the policy');
  });

  test('the session is reset through it', () async {
    await DVPlatform.installKioskPolicy(devicePolicy());
    final DVDeviceKiosk kiosk = DV.Platform.display.kiosk!;
    final List<DVKioskState> seen = <DVKioskState>[];
    kiosk.state.addListener(() => seen.add(kiosk.state.value));
    await kiosk.resetSession();
    expect(seen, <DVKioskState>[DVKioskState.resetting, DVKioskState.active]);
    expect(kiosk.runtime.policy.home, '/welcome');
  });

  test('it is left only through the declared method, and the platform lets go', () async {
    await DVPlatform.installKioskPolicy(devicePolicy(), readSecret: (String _) async => '4821');
    final DVDeviceKiosk kiosk = DV.Platform.display.kiosk!;
    expect((await kiosk.exit(const DVKioskExitRequest.adminAuth('x'))).granted, isFalse);
    expect(kiosk.state.value, DVKioskState.active);
    expect((await kiosk.exit(const DVKioskExitRequest.pin('4821'))).granted, isTrue);
    expect(kiosk.state.value, DVKioskState.staffMode);
    expect(kiosk.enforced, isNull, reason: 'staff mode: the platform released what it held');
    await kiosk.resume();
    expect(kiosk.state.value, DVKioskState.active);
    expect(enforced, hasLength(2), reason: 'held again on resume');
  });

  test('a disabled policy installs nothing', () async {
    await DVPlatform.installKioskPolicy(DVKioskPolicy.parse(null));
    expect(DV.Platform.display.kiosk, isNull);
  });
}
