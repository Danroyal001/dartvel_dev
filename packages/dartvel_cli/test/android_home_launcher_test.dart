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

  test('a TV lists it too: the TV launcher category, no touchscreen required, a banner', () {
    final String out = dvAndroidHomeLauncherManifest(_manifest, enabled: true);
    expect(out, contains('android.intent.category.LEANBACK_LAUNCHER'));
    expect(out, contains('<uses-feature android:name="android.software.leanback" android:required="false"/>'));
    expect(out, contains('<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>'));
    expect(out, contains('android:banner="@mipmap/ic_launcher"'));
    expect(dvAndroidHomeLauncherManifest(out, enabled: true), out);
    final String off = dvAndroidHomeLauncherManifest(out, enabled: false);
    expect(off, isNot(contains('LEANBACK')));
    expect(off, isNot(contains('uses-feature')));
    expect(off, isNot(contains('android:banner')));
  });

  group('the wallpaper behind a home app', () {
    const String styles = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
''';
    const String activity = '''package com.example.home

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
''';

    test('both window themes show the wallpaper and draw no background of their own', () {
      final String out = dvAndroidHomeLauncherStyles(styles, enabled: true);
      expect('android:windowShowWallpaper">true'.allMatches(out).length, 2);
      expect(out, isNot(contains('@drawable/launch_background')), reason: 'a black splash between the press of home and the first frame is the blank screen');
      expect(out, isNot(contains('?android:colorBackground')));
      expect('@android:color/transparent'.allMatches(out).length, 2, reason: 'one windowBackground per style; a second would be a duplicate resource');
    });

    test('writing twice is writing once, and turning it off restores Flutter\'s backgrounds', () {
      final String once = dvAndroidHomeLauncherStyles(styles, enabled: true);
      expect(dvAndroidHomeLauncherStyles(once, enabled: true), once);
      final String off = dvAndroidHomeLauncherStyles(once, enabled: false);
      expect(off, contains('@drawable/launch_background'));
      expect(off, contains('?android:colorBackground'));
      expect(off, isNot(contains('windowShowWallpaper')));
    });

    test('the Flutter surface is transparent, so the wallpaper is not painted over', () {
      final String? out = dvAndroidHomeLauncherActivity(activity, enabled: true);
      expect(out, contains('override fun getBackgroundMode()'));
      expect(out, contains('BackgroundMode.transparent'));
      // Back on the home page must not close the home app: the next press of
      // home would start it cold.
      expect(out, contains('override fun popSystemNavigator(): Boolean = true'));
      expect(dvAndroidHomeLauncherActivity(out!, enabled: true), out);
      expect(dvAndroidHomeLauncherActivity(out, enabled: false), activity);
    });

    test('a MainActivity someone changed is left alone and reported, not rewritten', () {
      const String edited = '''package com.example.home

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() { super.onResume() }
}
''';
      expect(dvAndroidHomeLauncherActivity(edited, enabled: true), isNull);
      expect(dvAndroidHomeLauncherActivity(edited, enabled: false), edited, reason: 'off, there is nothing of ours to remove');
    });
  });
}
