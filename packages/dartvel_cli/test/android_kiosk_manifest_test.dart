// The Android half of a declared kiosk.
//
// The specification's production path is an artifact that "starts in kiosk at
// boot", with "no window of unlocked UI at startup", and it names what that
// is on each platform: eLinux images, Windows assigned access, and Android
// lock-task launchers.
//
// A lock-task launcher is two things in the manifest and nothing in the Dart.
// The application has to be a HOME activity, or pressing home leaves it; and
// it has to carry a device-admin receiver, or `dpm set-device-owner` has
// nothing to point at and lock task shows the "pin this screen?" dialog to
// somebody who is not there. Neither can be added at run time.
import 'dart:io';

import 'package:dartvel_cli/src/build/android_kiosk_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="dartvel_example"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''';

void main() {
  test('a device-scope kiosk becomes the home screen', () {
    // Without this the home button leaves the application, which is the one
    // thing a kiosk exists to prevent.
    final String out = dvAndroidKioskManifest(_manifest,
        const DVAndroidKiosk(enabled: true, scope: 'device'));

    expect(out, contains('android.intent.category.HOME'));
    expect(out, contains('android.intent.category.DEFAULT'));
  });

  test('and carries a device-admin receiver to be made the owner', () {
    // dpm set-device-owner needs a component to point at. Without one, lock
    // task shows the "pin this screen?" dialog -- to nobody, on a device in
    // a lobby.
    final String out = dvAndroidKioskManifest(_manifest,
        const DVAndroidKiosk(enabled: true, scope: 'device'));

    expect(out, contains('DartvelDeviceAdminReceiver'));
    expect(out, contains('android.app.action.DEVICE_ADMIN_ENABLED'));
    expect(out, contains('android.permission.BIND_DEVICE_ADMIN'));
  });

  test('a display-scope kiosk is not the home screen', () {
    // One window owns one display; the device is still the user's. Making
    // the application the launcher would take the whole device from them.
    final String out = dvAndroidKioskManifest(_manifest,
        const DVAndroidKiosk(enabled: true, scope: 'display'));

    expect(out, isNot(contains('android.intent.category.HOME')));
  });

  test('a project with no kiosk is left exactly as it was', () {
    expect(
      dvAndroidKioskManifest(_manifest, const DVAndroidKiosk(enabled: false)),
      _manifest,
    );
  });

  test('building twice does not add the block twice', () {
    // The failure this shape exists for: a manifest with two receivers is a
    // manifest the packager refuses, and the build that wrote it succeeded.
    const DVAndroidKiosk kiosk = DVAndroidKiosk(enabled: true, scope: 'device');
    final String once = dvAndroidKioskManifest(_manifest, kiosk);
    final String twice = dvAndroidKioskManifest(once, kiosk);

    expect(twice, once);
    expect('DartvelDeviceAdminReceiver'.allMatches(twice).length,
        'DartvelDeviceAdminReceiver'.allMatches(once).length);
  });

  test('turning the kiosk off takes the block back out', () {
    const DVAndroidKiosk on = DVAndroidKiosk(enabled: true, scope: 'device');
    final String withIt = dvAndroidKioskManifest(_manifest, on);

    expect(
      dvAndroidKioskManifest(withIt, const DVAndroidKiosk(enabled: false)),
      _manifest,
    );
  });

  test('the receiver source is what the manifest names', () {
    // Two spellings of the class is a build that compiles and an app the
    // system cannot make the owner of anything.
    expect(dvAndroidDeviceAdminSource('com.example.app'),
        contains('class DartvelDeviceAdminReceiver'));
    expect(dvAndroidDeviceAdminSource('com.example.app'),
        contains('package com.example.app;'));
  });

  test('the policy the receiver declares is a policy, not an empty file', () {
    // An empty device-admin XML is accepted by aapt and rejected by the
    // device: set-device-owner fails with a message about the admin
    // component, hours after the build.
    expect(dvAndroidDeviceAdminPolicy(), contains('<device-admin'));
    expect(dvAndroidDeviceAdminPolicy(), contains('uses-policies'));
  });

  group('read from the project', () {
    Directory workspace(String kiosk, {String gradle = 'android/app/build.gradle'}) {
      final Directory root =
          Directory.systemTemp.createTempSync('dartvel_android_kiosk_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync("""
name: shopfront
$kiosk
""");
      File(p.join(root.path, gradle))
        ..createSync(recursive: true)
        ..writeAsStringSync('android { defaultConfig { applicationId "com.example.shopfront" } }');
      return root;
    }

    test('a declared device kiosk is read off the pubspec', () {
      final DVAndroidKiosk kiosk = DVAndroidKiosk.of(workspace("""
dartvel:
  kiosk:
    enabled: true
    scope: device
""").path);

      expect(kiosk.enabled, isTrue);
      expect(kiosk.ownsTheDevice, isTrue);
    });

    test('a project with no kiosk section owns nothing', () {
      expect(DVAndroidKiosk.of(workspace('').path).ownsTheDevice, isFalse);
    });

    test('scope defaults to device, which is what the word means alone', () {
      // `kiosk: {enabled: true}` with no scope is the whole device in the
      // specification's own default, and reading it as display would leave
      // the home button working on a device nobody is watching.
      expect(
        DVAndroidKiosk.of(workspace("""
dartvel:
  kiosk:
    enabled: true
""").path)
            .ownsTheDevice,
        isTrue,
      );
    });
  });
}
