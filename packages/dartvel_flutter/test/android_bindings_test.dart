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
    test('it claims clipboard, haptics and sharing', () {
      expect(
        DVAndroidBindings.implemented,
        <String>{
          'clipboard.copy',
          'clipboard.paste',
          'haptics.vibrate',
          'haptics.lightVibrate',
          'haptics.impact',
          'share.text',
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

  // share.text needs no Activity. Intent.ACTION_SEND started from the
  // application Context works as long as FLAG_ACTIVITY_NEW_TASK is set --
  // without it Android throws "Calling startActivity() from outside of an
  // Activity context requires the FLAG_ACTIVITY_NEW_TASK flag", at run time,
  // on the device, with nothing to catch it earlier.
  group('sharing text', () {
    test('it is a claimed binding', () {
      expect(DVAndroidBindings.implemented, contains('share.text'));
    });

    test('the share intent carries the new-task flag', () {
      // 0x10000000 is FLAG_ACTIVITY_NEW_TASK. Hard-coded because the
      // generated Intent bindings expose it as a static field whose value is
      // fixed by the platform, and a wrong value here throws only on device.
      expect(dvAndroidShareIntentFlags & 0x10000000, 0x10000000);
    });

    test('the chooser is used rather than a bare intent', () {
      // A bare ACTION_SEND resolves to whatever the user last picked, or to
      // nothing at all if no default is set. The chooser always resolves.
      expect(dvAndroidShareUsesChooser, isTrue);
    });

    test('the payload is typed as plain text', () {
      // An intent with no type is delivered to nothing: resolution matches on
      // action and MIME type together.
      expect(dvAndroidShareMimeType, 'text/plain');
    });
  });
}
