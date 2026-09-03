// Web platform bindings.
//
// Before this, `DV.Platform` had bindings on exactly one platform — Linux —
// and every call on web threw "not registered". The browser can serve nine of
// those names through ordinary web APIs, and the point of doing it is that no
// FFI, no toolchain and no vendor SDK is involved: it is the one platform
// where the whole gap is closeable in Dart.
//
// It is deliberately partial, and the partiality is the design. A browser tab
// has no system tray and cannot maximise itself, so those stay unregistered and
// keep throwing rather than returning a plausible lie.
import 'package:dartvel_flutter/src/platform/web/web_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the browser can and cannot do', () {
    test('it claims exactly the names it implements', () {
      expect(
        DVWebBindings.implemented,
        <String>{
          'clipboard.copy',
          'clipboard.paste',
          'screen.geometry',
          'notifications.sendLocal',
          'share.text',
          'haptics.vibrate',
          'haptics.lightVibrate',
          'haptics.impact',
          'window.setTitle',

          // Availability questions the browser can answer through
          // PublicKeyCredential, navigator.bluetooth and NDEFReader. Each
          // answers false where the API is absent, which is a fact about the
          // platform rather than a plausible default.
          'biometrics.canAuthenticate',
          'bluetooth.isEnabled',
          'nfc.isAvailable',

          // WebAuthn with userVerification required.
          'biometrics.authenticate',

          // Fullscreen, Keyboard Lock and Pointer Lock, each needing a user
          // gesture and reported refused when it is absent.
          'kiosk.enforce',
          'kiosk.release',
        },
      );
    });

    test('it does not claim what a tab cannot do', () {
      // Each of these has a call site in the framework and no browser
      // equivalent. Registering a no-op would turn "this platform cannot do
      // that" into "this silently did nothing", which is worse.
      //
      // biometrics.authenticate used to be here. WebAuthn is the browser
      // equivalent and it is bound now; nfc.readTag stays, because NDEFReader
      // reading a tag is Chrome on Android alone.
      for (final unavailable in <String>[
        'tray.show',
        'tray.hide',
        'window.maximize',
        'window.minimize',
        'window.restore',
        'window.setSize',
        'nfc.readTag',
      ]) {
        expect(DVWebBindings.implemented, isNot(contains(unavailable)),
            reason: '$unavailable has no browser equivalent, so it must keep '
                'throwing rather than appear to work');
      }
    });

    test('every name it claims is one the framework actually calls', () {
      // A binding nothing calls is dead weight, and a typo in a name is
      // invisible — it registers happily under the wrong string and the real
      // one still throws.
      const callable = <String>{
        'clipboard.copy',
        'clipboard.paste',
        'screen.geometry',
        'notifications.sendLocal',
        'share.text',
        'haptics.vibrate',
        'haptics.lightVibrate',
        'haptics.impact',
        'window.setTitle',
        'window.maximize',
        'window.minimize',
        'window.restore',
        'window.setSize',
        'window.persistState',
        'window.restoreState',
        'tray.show',
        'tray.hide',
        'nfc.isAvailable',
        'nfc.readTag',
        'bluetooth.isEnabled',
        'biometrics.authenticate',
        'biometrics.canAuthenticate',
        'kiosk.enforce',
        'kiosk.release',
      };
      expect(DVWebBindings.implemented.difference(callable), isEmpty);
    });
  });

  group('off the web', () {
    test('register reports false rather than pretending', () {
      // This suite runs on the VM, where the stub is what resolves. It has to
      // expose the same surface or code that compiles on web fails elsewhere.
      expect(DVWebBindings.register(), isFalse);
      expect(DVWebBindings.isRegistered, isFalse);
    });
  });
}
