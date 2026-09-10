// Android platform bindings.
//
// Android was the one platform with nothing, and the reason given was that
// package:jni exposed no application Context. The answer written here then
// was GetApplicationContext(), from package:jni's C header — which is
// declared there and never defined, so every binding this file asserts was
// dead in every real application until an emulator said "undefined symbol".
// The Context now comes from a ContentProvider `dartvel build android`
// writes, and the Activity that the permission dialog, the camera and the
// picker need comes from a transparent Activity written beside it.
//
// The intended fallback was wrong too, and generation proved it —
// ActivityThread is hidden and absent from the public android.jar, so jnigen
// found every other class and reported that one "Not found".
//
// This suite runs anywhere and asserts the capability list and the refusal to
// register off-Android. The bindings themselves need a device, and the
// emulator job in runtime-verification is where they are exercised.
import 'dart:io' show Directory, File, FileSystemEntity, Platform;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/android/android_capture_jni.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capability list', () {
    test('it claims clipboard, haptics, sharing and the kiosk', () {
      expect(DVAndroidBindings.implemented, <String>{
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
        // The permission dialog and the four APIs that need one. All of
        // them wait on a result Android delivers to an Activity, which the
        // application Context is not -- so they arrive at the transparent
        // Activity `dartvel build android` writes.
        'permissions.isGranted',
        'permissions.request',
        'camera.takePhoto',
        'media.pick',
        'contacts.getContacts',
        'location.current',
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
        // One sample each, taken by registering a SensorManager listener and
        // dropping it when the first event lands.
        'sensors.accelerometer',
        'sensors.gyroscope',
        // BiometricManager, a system service like any other. The prompt is
        // the part still missing, for the reason the absence test states.
        'biometrics.canAuthenticate',
        // NotificationManager. This was recorded as needing an Activity; it
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
      });
    });

    test('the capture bindings are all claimed together', () {
      // They share one Activity and one result map. Half of them present
      // would mean a build wrote the bridge for some and not others, and the
      // ones left out would answer null -- which reads as "this platform
      // cannot" rather than "this build is broken".
      expect(
        DVAndroidBindings.implemented,
        containsAll(DVAndroidCapture.implemented),
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

  group('the list and the registrations agree', () {
    // There is an on-device gate that asserts every claimed name has a real
    // handler and that nothing is registered which the list omits. It runs in
    // the emulator job, which is slow and does not run on every push, and by
    // then the mismatch has already been merged. This asks the same question
    // of the source, here, in seconds.
    //
    // It reads the source rather than calling register(), because register()
    // returns false off Android and there is no Android here. That is a
    // weaker instrument -- it can only see literals -- and it is the strongest
    // one available on this machine.
    // `\s*` after the parenthesis, because the name is not always on the same
    // line as the call. A wrapped `DVNativeBridge.register(\n  'sensors.
    // accelerometer',` is what the formatter produces once the handler is long
    // enough, and the first version of this pattern read that as no
    // registration at all -- so thirteen bindings looked claimed and unwired.
    final RegExp binding = RegExp(
      r"""(?:DVNativeBridge\.)?(?:register|bind)\(\s*'([a-zA-Z]+\.[a-zA-Z.]+)'""",
    );
    final RegExp claimed = RegExp(
      r"""^  '([a-zA-Z]+\.[a-zA-Z.]+)',""",
      multiLine: true,
    );

    const String androidDir = 'lib/src/platform/android';

    /// The android directory, plus the shared registrars it hands the bridge
    /// to.
    ///
    /// `device.*` and `files.*` are registered by `device_runtime.dart` and
    /// `file_bindings.dart`, which sit a directory up because every platform
    /// with a filesystem or a procfs can use them. Reading only the android
    /// directory therefore found the claim and never the registration.
    ///
    /// Derived from the imports rather than listed, so a registrar added later
    /// is picked up without anyone remembering to add it here. Only `../`
    /// imports, which is what a shared sibling looks like from in here, and
    /// never the package barrel -- that is the bridge itself and re-exports
    /// every platform, so following it would attribute Linux's printing to
    /// Android.
    List<File> androidSources() {
      final List<File> files = <File>[
        for (final FileSystemEntity e in Directory(androidDir).listSync())
          if (e is File &&
              e.path.endsWith('.dart') &&
              // Not the capability list itself: its entries are the claim,
              // and matching them here would make the test compare the list
              // with itself and pass whatever it said.
              !e.path.endsWith('android_capabilities.dart'))
            e,
      ];

      final RegExp sibling = RegExp(r"""^import '\.\./([a-z_]+\.dart)';""",
          multiLine: true);
      final Set<String> shared = <String>{};
      for (final File file in files) {
        for (final RegExpMatch m in sibling.allMatches(file.readAsStringSync())) {
          shared.add(m.group(1)!);
        }
      }
      for (final String name in shared) {
        final File file = File('lib/src/platform/$name');
        if (file.existsSync()) files.add(file);
      }
      return files;
    }

    Set<String> registeredInSource() {
      final Set<String> found = <String>{};
      for (final File file in androidSources()) {
        for (final RegExpMatch m
            in binding.allMatches(file.readAsStringSync())) {
          found.add(m.group(1)!);
        }
      }
      return found;
    }

    test('the scan reads both sides at all', () {
      // Without this, a rename or a reformat could empty either set and the
      // two assertions below would agree about nothing.
      expect(registeredInSource(), hasLength(greaterThan(8)));
      expect(
        claimed
            .allMatches(
              File('$androidDir/android_capabilities.dart').readAsStringSync(),
            )
            .length,
        greaterThan(8),
      );
    });

    test('nothing is registered that the list does not claim', () {
      // This is the one that matters on a device: a handler the list omits
      // means DVNativeBridge answers a name the capability API says is
      // unsupported, so an application branches away from something that
      // works.
      expect(
        registeredInSource().difference(DVAndroidBindings.implemented),
        isEmpty,
      );
    });

    test('nothing is claimed that no file registers', () {
      // And the other way: a name in the list with no handler behind it makes
      // the capability check say yes and the call return null, which is the
      // failure this whole layer exists to prevent.
      expect(
        DVAndroidBindings.implemented.difference(registeredInSource()),
        isEmpty,
      );
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
