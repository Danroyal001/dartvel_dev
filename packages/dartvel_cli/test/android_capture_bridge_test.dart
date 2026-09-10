// The Activity plumbing behind the permission-gated Android bindings.
//
// A Context is not an Activity. `requestPermissions`,
// `onRequestPermissionsResult`, `startActivityForResult` and
// `onActivityResult` are all an Activity's, and the application Context that
// `DartvelContext` holds can reach none of them -- which is why the camera,
// the picker, contacts, location and the permission dialog were the group of
// bindings Android had nothing for.
//
// What is checked here is the part that fails silently on a device: a
// permission requested but never declared is refused by Android instantly,
// with no dialog and the same result code a person tapping Deny produces.
import 'package:dartvel_cli/src/build/android_capture_bridge.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="example"
        android:name="\${applicationName}">
        <activity android:name=".MainActivity"/>
    </application>
</manifest>
''';

void main() {
  group('what pubspec asks for', () {
    test('an application that asks for nothing declares nothing of its own',
        () {
      // The manifest of a torch application should not mention contacts.
      final String out = dvAndroidCaptureManifest(_manifest, const <String>[]);
      expect(out, isNot(contains('CONTACTS')));
      expect(out, isNot(contains('CAMERA')));
      // The plumbing is still there: media picking and the permission dialog
      // itself need no permission at all.
      expect(out, contains('DartvelBridgeActivity'));
    });

    test('VIBRATE is written whether or not anybody asked', () {
      // Haptics is not opt-in. DVAndroidBindings.register binds all three
      // haptics names on every Android build and the capability list claims
      // them, so the manifest has to support them or the claim is false.
      //
      // Found on an emulator, and only after a different bug was out of the
      // way: the call used to die casting VibratorManager to Vibrator, and
      // once it stopped doing that it reached Android and was refused --
      // "SecurityException: Neither user 10193 nor current process has
      // android.permission.VIBRATE". A normal permission, granted at install
      // with no dialog, which is why nothing about the app looked wrong.
      final String out = dvAndroidCaptureManifest(_manifest, const <String>[]);
      expect(out, contains('android.permission.VIBRATE'));
    });

    test('USE_BIOMETRIC too, for the same reason', () {
      // biometrics.canAuthenticate is bound on every Android build -- asking
      // whether a device has biometrics needs no dialog and no decision from
      // anybody -- and BiometricManager.canAuthenticate() throws
      // SecurityException without this line. USE_BIOMETRIC is normal, so it
      // is granted at install and nobody is asked.
      //
      // biometrics.authenticate, the prompt itself, is a different matter and
      // is not bound at all: it needs a Java shim, and it is the part a person
      // actually answers.
      final String out = dvAndroidCaptureManifest(_manifest, const <String>[]);
      expect(out, contains('android.permission.USE_BIOMETRIC'));
    });

    test('but never a dangerous permission nobody asked for', () {
      // The rule that keeps the always-bound list honest. Everything on it is
      // added without the project saying so, so it has to be a permission
      // Android grants at install with no dialog. BLUETOOTH_CONNECT and
      // CAMERA are the project's to request, and adding either on its behalf
      // would put a question in front of its users that its author never
      // wrote.
      final String out = dvAndroidCaptureManifest(_manifest, const <String>[]);
      for (final String dangerous in <String>[
        'BLUETOOTH_CONNECT',
        'CAMERA',
        'READ_CONTACTS',
        'ACCESS_FINE_LOCATION',
        'POST_NOTIFICATIONS',
      ]) {
        expect(out, isNot(contains(dangerous)), reason: dangerous);
      }
    });

    test('and is not written twice when the manifest already has it', () {
      // A hand-written manifest that already declares it is the common case
      // for a project migrating in, and a duplicate uses-permission is the
      // kind of thing the manifest merger complains about at build time.
      const String withVibrate = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.VIBRATE"/>
    <application android:label="x">
    </application>
</manifest>
''';
      final String out =
          dvAndroidCaptureManifest(withVibrate, const <String>[]);
      expect('android.permission.VIBRATE'.allMatches(out).length, 1);
    });

    test('a name Dartvel does not know is reported rather than dropped', () {
      // Dropping it silently leaves a manifest without exactly the line the
      // developer wrote the pubspec entry to get, and the runtime refusal
      // that follows says only "denied".
      expect(dvAndroidUnknownPermissions(<String>['camera', 'telepathy']),
          <String>['telepathy']);
    });

    test('the pubspec section is read as a list of names', () {
      const Map<String, Object?> section = <String, Object?>{
        'android': <String, Object?>{
          'permissions': <Object?>['camera', 'location', 'camera'],
        },
      };
      // Once each, in the order written.
      expect(dvAndroidRequestedPermissions(section),
          <String>['camera', 'location']);
      expect(dvAndroidRequestedPermissions(null), isEmpty);
      expect(dvAndroidRequestedPermissions(<String, Object?>{}), isEmpty);
    });
  });

  group('the manifest', () {
    test('permissions go outside <application>, where they count', () {
      final String out = dvAndroidCaptureManifest(_manifest, <String>['camera']);
      final int permission = out.indexOf('android.permission.CAMERA');
      final int application = out.indexOf('<application');
      expect(permission, greaterThan(0));
      // Inside <application> the manifest merger drops a uses-permission and
      // says so in a log nobody reads. The APK then installs, runs, and is
      // refused the camera at the moment somebody presses the button.
      expect(permission, lessThan(application));
    });

    test('an old permission is capped rather than asked for everywhere', () {
      final String out =
          dvAndroidCaptureManifest(_manifest, <String>['storage']);
      expect(out, contains('android.permission.READ_EXTERNAL_STORAGE'));
      // Uncapped, the Play console asks what a modern application wants with
      // external storage, and the answer is nothing: it stopped being
      // granted at API 33.
      expect(out, contains('android:maxSdkVersion="32"'));
    });

    test('building twice leaves one Activity, not two', () {
      // Two components with one name is a package Android refuses to
      // install, and the error names the component rather than the build
      // that wrote it twice.
      final String once = dvAndroidCaptureManifest(_manifest, <String>['camera']);
      final String twice = dvAndroidCaptureManifest(once, <String>['camera']);
      expect(twice, once);
      expect('DartvelBridgeActivity'.allMatches(twice).length, 1);
      expect('android.permission.CAMERA'.allMatches(twice).length, 1);
    });

    test('a build that stops asking stops declaring', () {
      final String asked = dvAndroidCaptureManifest(_manifest, <String>['contacts']);
      final String withdrawn = dvAndroidCaptureManifest(asked, const <String>[]);
      // A permission left in the manifest after the feature went is a store
      // listing that still says the application reads your contacts.
      expect(withdrawn, isNot(contains('READ_CONTACTS')));
      expect(withdrawn, contains('DartvelBridgeActivity'));
    });

    test('the camera can be seen at all on Android 11 and later', () {
      // Package visibility. From API 30 an application cannot see what it has
      // not asked about, and Intent.resolveActivity answers null for a camera
      // that is installed and working. Without the queries element,
      // camera.takePhoto reports that the phone has no camera application --
      // on a phone with two, in a way that looks like a device problem.
      final String out = dvAndroidCaptureManifest(_manifest, const <String>[]);
      expect(out, contains('<queries>'));
      expect(out, contains('android.media.action.IMAGE_CAPTURE'));
      final int queries = out.indexOf('<queries>');
      // A queries element inside <application> is dropped by the merger.
      expect(queries, lessThan(out.indexOf('<application')));
    });

    test('the capture provider is unexported and grants by URI', () {
      final String out = dvAndroidCaptureManifest(_manifest, const <String>[]);
      expect(out, contains('android:name="dev.dartvel.jni.DartvelCaptureFiles"'));
      // The camera application reaches the file through the grant on the
      // Intent. Exporting the provider would open the cache to every
      // application on the phone to save a flag.
      expect(out, contains('android:exported="false"'));
      expect(out, contains('android:grantUriPermissions="true"'));
    });

    test('a manifest it cannot place anything in is left alone', () {
      const String odd = '<manifest></manifest>';
      expect(dvAndroidCaptureManifest(odd, <String>['camera']), odd);
    });
  });

  group('the generated Java', () {
    test('resolves every permission name Dart can ask for', () {
      // The table is read twice, by two languages. A name Dart can pass and
      // Java cannot resolve is answered "no such permission" on the device
      // and nowhere else -- and a name Java resolves to something the
      // manifest generator never declared is refused with no dialog, which
      // reads as a refusal.
      final String java = dvAndroidCaptureBridgeSource();
      for (final String name in dvAndroidPermissionNames) {
        expect(java, contains('case "$name":'), reason: name);
        for (final String android in dvAndroidPermissionsFor(name, sdk: 21)!) {
          expect(java, contains('"$android"'), reason: '$name -> $android');
        }
        for (final String android in dvAndroidPermissionsFor(name, sdk: 36)!) {
          expect(java, contains('"$android"'), reason: '$name -> $android');
        }
      }
    });

    test('an unknown name is not resolved to nothing', () {
      // Returning an empty array for a typo would mean "nothing to ask for",
      // which the bridge reads as granted. `camrea` would then be held on
      // every device.
      expect(dvAndroidCaptureBridgeSource(), contains('        return null;'));
    });

    test('the API level decides which spelling is asked for', () {
      final String java = dvAndroidCaptureBridgeSource();
      // POST_NOTIFICATIONS did not exist before 33 and asking for it there
      // is answered denied for ever.
      expect(java, contains('if (sdk >= 33) '
          'out.add("android.permission.POST_NOTIFICATIONS");'));
      expect(java, contains('if (sdk <= 32) '
          'out.add("android.permission.READ_EXTERNAL_STORAGE");'));
    });

    test('approximate location is enough for location', () {
      expect(dvAndroidCaptureBridgeSource(),
          contains('logical.equals("location")'));
    });

    test('the classes are the ones the runtime looks up by name', () {
      final String bridge = dvAndroidCaptureBridgeSource();
      final String activity = dvAndroidBridgeActivitySource();
      final String files = dvAndroidCaptureFilesSource();
      for (final String source in <String>[bridge, activity, files]) {
        expect(source, contains('package dev.dartvel.jni;'));
      }
      expect(bridge,
          contains('class ${dvAndroidCaptureBridgeClass.split('/').last} '));
      expect(activity,
          contains('class ${dvAndroidBridgeActivityClass.split('/').last} '));
      expect(files,
          contains('class ${dvAndroidCaptureFilesClass.split('/').last} '));
      expect(dvAndroidCaptureBridgePath, endsWith('DartvelActivityBridge.java'));
      expect(dvAndroidBridgeActivityPath, endsWith('DartvelBridgeActivity.java'));
      expect(dvAndroidCaptureFilesPath, endsWith('DartvelCaptureFiles.java'));
    });

    test('the provider authority is the one the manifest declares', () {
      // Two spellings is a camera handed a URI no provider answers, which
      // comes back as RESULT_CANCELED and reads as the person pressing back.
      expect(dvAndroidCaptureFilesSource(),
          contains(dvAndroidCaptureAuthoritySuffix));
      expect(dvAndroidCaptureManifest(_manifest, const <String>[]),
          contains('\${applicationId}$dvAndroidCaptureAuthoritySuffix'));
    });

    test('a chosen file cannot be copied out of the directory it belongs in',
        () {
      // The file name comes from whichever application answered the picker.
      // A provider returning "../../databases/app.db" would otherwise have
      // the copy overwrite the application's own data.
      expect(dvAndroidBridgeActivitySource(), contains('private String sanitise'));
      expect(dvAndroidCaptureFilesSource(), contains('name.contains("..")'));
    });

    test('the camera is asked through a content URI, not a file one', () {
      // A file:// URI in EXTRA_OUTPUT has thrown FileUriExposedException
      // since API 24 -- on the device, when the shutter is pressed.
      final String activity = dvAndroidBridgeActivitySource();
      expect(activity, contains('DartvelCaptureFiles.uriFor'));
      expect(activity, contains('FLAG_GRANT_WRITE_URI_PERMISSION'));
      expect(activity, isNot(contains('Uri.fromFile')));
    });

    test('a cancelled picker is not an error', () {
      // Everywhere else in Dartvel a cancelled chooser is an empty list. A
      // camera that reported an error there would make "no thanks" look like
      // a broken device.
      expect(dvAndroidBridgeActivitySource(), contains('"cancelled"'));
    });
  });
}
