// `dartvel.android.launcher: true` makes the app eligible as the phone's home
// screen. Android offers an app in "Home app" only when its launcher activity
// also answers MAIN/HOME/DEFAULT, and from Android 11 an app sees other
// installed apps only after declaring which ones it queries. Neither could be
// said in pubspec.yaml, and the native folders are build output, so a launcher
// could not be built with Dartvel at all.
import 'package:dartvel_cli/src/build/android_home_launcher.dart';
import 'package:test/test.dart';

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="dev_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''';

void main() {
  test('a launcher app answers HOME and DEFAULT on its launcher activity', () {
    final String out = dvAndroidHomeLauncherManifest(_manifest, enabled: true);
    final int activity = out.indexOf('<activity');
    final int close = out.indexOf('</activity>');
    final String inside = out.substring(activity, close);
    expect(inside, contains('android.intent.category.HOME'));
    expect(inside, contains('android.intent.category.DEFAULT'));
    // The original LAUNCHER filter stays, so the app is still in the drawer.
    expect(inside, contains('android.intent.category.LAUNCHER'));
  });

  test('a launcher app declares that it queries other launchable apps', () {
    final String out = dvAndroidHomeLauncherManifest(_manifest, enabled: true);
    final int queries = out.indexOf('<queries>');
    expect(queries, greaterThan(0));
    expect(queries, lessThan(out.indexOf('<application')), reason: '<queries> belongs to <manifest>, before <application>');
    expect(out.substring(queries, out.indexOf('</queries>')), contains('android.intent.category.LAUNCHER'));
  });

  test('running it twice changes nothing, and turning it off removes it', () {
    final String once = dvAndroidHomeLauncherManifest(_manifest, enabled: true);
    expect(dvAndroidHomeLauncherManifest(once, enabled: true), once);
    expect(dvAndroidHomeLauncherManifest(once, enabled: false), _manifest);
  });

  test('an ordinary app is untouched', () {
    expect(dvAndroidHomeLauncherManifest(_manifest, enabled: false), _manifest);
  });

  test('the setting is read from dartvel.android.launcher', () {
    expect(dvAndroidHomeLauncherEnabled(<Object?, Object?>{'android': <Object?, Object?>{'launcher': true}}), isTrue);
    expect(dvAndroidHomeLauncherEnabled(<Object?, Object?>{'android': <Object?, Object?>{}}), isFalse);
    expect(dvAndroidHomeLauncherEnabled(<Object?, Object?>{}), isFalse);
  });
}
