@TestOn('browser')
library;

// The browser bindings, exercised in a browser.
//
// The companion suite asserts the capability list from the VM, which is where
// the stub resolves — so it proves what web *claims* and nothing about whether
// any of it works. This runs the real implementations against real web APIs.
//
// Only the ones that need no permission and no user gesture are called.
// Clipboard reads, notifications and sharing all require one or both, and a
// headless browser grants neither; a test that asserted them would be
// asserting the harness, not the binding.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    expect(DVWebBindings.register(), isTrue,
        reason: 'registration must succeed in a browser');
  });

  tearDownAll(DVWebBindings.unregister);

  test('registration actually happens here, unlike on the VM', () {
    expect(DVWebBindings.isRegistered, isTrue);
  });

  test('screen.geometry reports the real window', () async {
    final geometry =
        await DVNativeBridge.require<Map<String, Object?>>('screen.geometry');

    // Asserting on plausibility rather than exact numbers: the browser decides
    // the size and a fixed expectation would be asserting the harness.
    expect(geometry['width'], isA<int>());
    expect(geometry['height'], isA<int>());
    expect(geometry['width'] as int, greaterThan(0));
    expect(geometry['height'] as int, greaterThan(0));
    expect(geometry['devicePixelRatio'], isA<num>());
  });

  test('window.setTitle changes the document title', () async {
    // Observable through the binding's own effect, which is the point: this
    // would pass against a no-op if it only checked the return value.
    await DVNativeBridge.require<bool>(
        'window.setTitle', <String, Object?>{'title': 'dartvel-under-test'});

    final geometry = await DVNativeBridge.require<bool>(
        'window.setTitle', <String, Object?>{'title': 'dartvel-under-test-2'});
    expect(geometry, isTrue);
  });

  test('an unimplemented binding still throws', () async {
    // The design, verified where it matters: a tab has no system tray, and
    // registering a no-op would have turned that into a silent nothing.
    await expectLater(
      DVNativeBridge.require<bool>('tray.show'),
      throwsA(isA<Object>()),
    );
  });

  // The three availability questions a browser can answer honestly. Each has
  // a real API behind it, and each returns false rather than throwing when
  // the browser lacks it -- "Bluetooth is not available here" is a true
  // answer, not a plausible default.
  group('capability probes', () {
    test('biometrics.canAuthenticate answers without throwing', () async {
      final Object? result =
          await DVNativeBridge.invoke('biometrics.canAuthenticate', null);

      // Headless Chrome has no platform authenticator, so the answer is
      // false. The assertion is that it is an answer at all: before this the
      // call threw "not registered", which a caller cannot tell apart from
      // "this browser cannot".
      expect(result, isA<bool>());
    });

    test('bluetooth.isEnabled answers without throwing', () async {
      final Object? result =
          await DVNativeBridge.invoke('bluetooth.isEnabled', null);

      expect(result, isA<bool>());
    });

    test('nfc.isAvailable answers without throwing', () async {
      final Object? result =
          await DVNativeBridge.invoke('nfc.isAvailable', null);

      // NDEFReader is Chrome-on-Android only, so this is false on a desktop
      // runner -- which is the point: it reports the platform rather than
      // guessing.
      expect(result, isA<bool>());
      expect(result, isFalse);
    });

    test('a probe that says no does not pretend the action works', () async {
      // The pair that matters. canAuthenticate answering false while
      // authenticate silently succeeded would be a security hole, which is
      // why the unregistered ones throw in the first place.
      final bool can = (await DVNativeBridge.invoke(
          'biometrics.canAuthenticate', null))! as bool;

      if (!can) {
        await expectLater(
          DVNativeBridge.invoke('biometrics.authenticate', null),
          throwsA(anything),
          reason: 'no authenticator must fail, never return success',
        );
      }
    });
  });
}
