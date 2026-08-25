// Android platform bindings.
//
// Android was the one platform with nothing, and the reason given was that
// package:jni exposed no application Context. That was wrong: it exports
// GetApplicationContext() from its C header, documented as returning exactly
// that, and reachable with plain dart:ffi.
//
// The intended fallback was wrong too, and generation proved it —
// ActivityThread is hidden and absent from the public android.jar, so jnigen
// found every other class and reported that one "Not found". The C export is
// not a workaround for that; it is the better answer.
//
// This suite runs anywhere and asserts the capability list and the refusal to
// register off-Android. The bindings themselves need a device, and the
// emulator job in runtime-verification is where they are exercised.
import 'dart:io' show Platform;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capability list', () {
    test('it claims clipboard and haptics', () {
      expect(
        DVAndroidBindings.implemented,
        <String>{
          'clipboard.copy',
          'clipboard.paste',
          'haptics.vibrate',
          'haptics.lightVibrate',
          'haptics.impact',
        },
      );
    });

    test('it is no longer empty, which is the point', () {
      // It was empty, with a blocker recorded against it. Asserting the
      // opposite now stops the empty set quietly returning.
      expect(DVAndroidBindings.implemented, isNotEmpty);
    });

    test('what needs an Activity is absent', () {
      // BiometricPrompt attaches to an Activity and NFC dispatch is delivered
      // to one. A Context is not enough, and pretending otherwise would fail
      // on a device rather than here.
      for (final name in <String>[
        'biometrics.authenticate',
        'biometrics.canAuthenticate',
        'nfc.readTag',
        'notifications.sendLocal',
      ]) {
        expect(DVAndroidBindings.implemented, isNot(contains(name)));
      }
    });
  });

  group('registration', () {
    test('off Android it declines rather than throwing', () {
      if (Platform.isAndroid) return;
      expect(DVAndroidBindings.register(), isFalse);
      expect(DVAndroidBindings.isRegistered, isFalse);
    });
  });
}
