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
    test('it claims clipboard, haptics, sharing and the kiosk', () {
      expect(
        DVAndroidBindings.implemented,
        <String>{
          'clipboard.copy',
          'clipboard.paste',
          'haptics.vibrate',
          'haptics.lightVibrate',
          'haptics.impact',
          'share.text',
          'kiosk.enforce',
          'kiosk.release',
          // The launch Intent's URI. It belongs to the Activity, so it
          // arrived with the Activity -- and a home widget's tap is a deep
          // link, so without it a widget opened the application's home route.
          'deepLinks.initial',
          // What a home-screen widget shows. The provider is a receiver in
          // this application's own process, so both ends reach the same
          // SharedPreferences -- but the launcher composes the widget, so
          // what crosses is the data and never the tree.
          'homeWidgets.publish',
          // The display, from the Context's own DisplayMetrics. Not the
          // window Flutter reports: on a device in split screen they are
          // different numbers answering different questions.
          'screen.geometry',
          // Whether there is a reader and it is switched on. Reading and
          // writing a tag are not here; see the absence test below.
          'nfc.isAvailable',
          // Bluetooth, read rather than driven. Android has no device-level
          // connect to bind, so the four action names Linux binds cannot all
          // be honoured -- pairing can, and is.
          'bluetooth.isEnabled',
          'bluetooth.adapters',
          'bluetooth.devices',
          'bluetooth.scanDevices',
          'bluetooth.pair',
        },
      );
    });

    test('the kiosk is here because the Activity is now reachable', () {
      // It was absent for the same reason biometrics and NFC still are: lock
      // task mode belongs to an Activity, and the application Context that
      // package:jni hands back is not one. The difference is that Android
      // offers a way to be told which Activity is in front --
      // Application.registerActivityLifecycleCallbacks -- and jnigen can
      // implement a Java interface, so the callback is Dart's. No platform
      // channel, which is what the native integration rule asks for.
      expect(DVAndroidBindings.implemented, contains('kiosk.enforce'));
    });

    test('it is no longer empty, which is the point', () {
      // It was empty, with a blocker recorded against it. Asserting the
      // opposite now stops the empty set quietly returning.
      expect(DVAndroidBindings.implemented, isNotEmpty);
    });

    test('what needs an Activity is absent', () {
      // BiometricPrompt attaches to an Activity, and a tag reaches an
      // application only through foreground dispatch or reader mode, both of
      // which are Activity callbacks. A Context is not enough, and pretending
      // otherwise would fail on a device rather than here. Asking whether
      // there is a reader at all needs no Activity, which is why
      // nfc.isAvailable is bound and nfc.readTag is not.
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
