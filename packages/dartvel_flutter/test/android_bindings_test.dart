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
          // One sample each, taken by registering a SensorManager listener
          // and dropping it when the first event lands.
          'sensors.accelerometer',
          'sensors.gyroscope',
          // BiometricManager, a system service like any other. The prompt is
          // the part still missing, and it is missing for a reason the test
          // below states.
          'biometrics.canAuthenticate',
          // NotificationManager. It was recorded as needing an Activity; it
          // does not.
          'notifications.sendLocal',
          // The shared device runtime, reading procfs. All six, because four
          // of six would leave DV.Platform.device half working.
          'device.capabilityManifest',
          'device.health',
          'device.watchdog.arm',
          'device.watchdog.heartbeat',
          'device.fleet.provision',
          'device.diagnostics.collect',
          // Files, confined to the directory the application owns.
          'files.readBytes',
          'files.writeBytes',
          'files.delete',
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

    test('what still has nowhere to land is absent', () {
      // This list was longer, and two of its entries were on it for a reason
      // that did not survive being checked. NotificationManager is a system
      // service on the application Context, not an Activity's; so is
      // BiometricManager, which is all canAuthenticate needs.
      //
      // What is left is genuinely blocked, and not by the Activity either.
      // BiometricPrompt.authenticate reports its result to an
      // AuthenticationCallback, which is an abstract class -- jnigen
      // implements interfaces and cannot subclass one, so the answer has
      // nowhere to arrive. It needs a Java shim written beside the Context
      // provider. NFC dispatch really is the Activity's.
      for (final name in <String>[
        'biometrics.authenticate',
        'nfc.readTag',
      ]) {
        expect(DVAndroidBindings.implemented, isNot(contains(name)));
      }
    });

    test('a bound name is not a name proven on a device', () {
      // The header of android_bindings_jni.dart records the case this guards
      // against: every Android binding looked right, the capability list
      // claimed them all, and each one was dead in a real application
      // because the Context behind them came from a symbol with no
      // definition. This suite never crosses into Java, and a green run here
      // says the Dart side decided correctly and nothing more.
      expect(DVAndroidBindings.isRegistered, isFalse,
          reason: 'this suite does not run on Android and must not pretend '
              'the JNI calls were exercised');
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
