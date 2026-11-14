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

  test('it may see the apps behind each dock role and the screens that choose the home app', () {
    final String out = dvAndroidHomeLauncherManifest(_manifest, enabled: true);
    for (final String wanted in const [
      'android.intent.action.DIAL',
      'android.intent.action.SENDTO',
      'android:scheme="smsto"',
      'android:scheme="https"',
      'android.media.action.STILL_IMAGE_CAMERA',
      'android:scheme="mailto"',
      'android:scheme="geo"',
      'android.settings.HOME_SETTINGS',
      'android.app.role.action.REQUEST_ROLE',
    ]) {
      expect(out, contains(wanted), reason: wanted);
    }
    expect(dvAndroidHomeLauncherManifest(out, enabled: true), out);
  });

  test('it can see the other home apps, or it cannot tell whether it is the home app', () {
    // isDefaultLauncher asks which app answers MAIN/HOME. With the others
    // hidden (Android 11+), the only home app it could see was itself, so it
    // always said yes and the 'make it my home app' offer never showed.
    final String out = dvAndroidHomeLauncherManifest(_manifest, enabled: true);
    final String queries = out.substring(out.indexOf('<queries>'), out.indexOf('</queries>'));
    expect(queries, contains('android.intent.category.HOME'));
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

    test('Android 12 and later: the launch theme in values-v31 shows the wallpaper too', () {
      // From API 31 the launch theme lives in values-v31/styles.xml; leaving
      // it out kept a full splash on Android 12 phones.
      const String v31 = '''<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">@color/dartvel_splash_background</item>
    </style>
</resources>
''';
      final String out = dvAndroidHomeLauncherStyles(v31, enabled: true);
      expect(out, contains('android:windowShowWallpaper">true'));
      expect(out, isNot(contains('@drawable/launch_background')));
      expect(out, contains('windowSplashScreenBackground'), reason: 'the splash colour stays for the system splash');
      expect(dvAndroidHomeLauncherStylesFolders, containsAll(<String>['values', 'values-night', 'values-v31', 'values-night-v31']));
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


    test('Home pressed while the home app is in front reaches the app: the new intent is stamped', () {
      // Android hands that press to the home app as a new intent and nothing
      // else; without the stamp the app cannot tell it from any resume, and a
      // launcher's drawer stays open when Home is pressed.
      final String out = dvAndroidHomeLauncherActivity(activity, enabled: true)!;
      expect(out, contains('override fun onNewIntent(intent: android.content.Intent)'));
      expect(out, contains('intent.hasCategory(android.content.Intent.CATEGORY_HOME)'));
      expect(out, contains('"dev.dartvel.homePressedAt"'), reason: 'the extra DVApps.homePresses reads');
      expect(out, contains('setIntent(intent)'), reason: 'getIntent() is what the binding reads');
    });


    test('the Recents button is heard while the home app is in front: the system\'s "recentapps" broadcast is stamped', () {
      // Phones whose own launcher hosts Recents (HiOS among them) can show
      // nothing when another app is the home app; the press still arrives as
      // ACTION_CLOSE_SYSTEM_DIALOGS with reason "recentapps".
      final String out = dvAndroidHomeLauncherActivity(activity, enabled: true)!;
      expect(out, contains('android.content.Intent.ACTION_CLOSE_SYSTEM_DIALOGS'));
      expect(out, contains('"recentapps"'));
      expect(out, contains('"dev.dartvel.recentsPressedAt"'));
      expect(out, contains('override fun onCreate('), reason: 'heard for as long as the app runs, in front or not');
      expect(out, contains('unregisterReceiver('), reason: 'and unregistered, or the activity leaks');
      expect(out, contains('RECEIVER_NOT_EXPORTED'), reason: 'Android 13+ wants the flag; a system broadcast still arrives');
    });
    test('Home and Recents are told to the app as they happen, not left for a resume that never comes', () {
      // Android 10+ gives a home app already in front the new intent and no
      // pause or resume (seen on an Android 12 emulator with the app as the
      // default home), so a stamp read on resume never closed the drawer.
      final String out = dvAndroidHomeLauncherActivity(activity, enabled: true)!;
      expect(out, contains('"dev.dartvel/system_keys"'), reason: 'the channel DVApps listens on');
      expect(out, contains('io.flutter.plugin.common.StringCodec.INSTANCE'));
      expect(out, contains('dartvelSystemKey("home", pressedAt)'));
      expect(out, contains('dartvelSystemKey("recents", pressedAt)'));
    });
    test('an activity written by Dartvel 0.13.51 is brought up to date', () {
      final String? out = dvAndroidHomeLauncherActivity('package com.example.home\n\nimport io.flutter.embedding.android.FlutterActivity\n\n${dvAndroidHomeLauncherActivity01351ForTest}\n', enabled: true);
      expect(out, isNotNull);
      expect(out, contains('"dev.dartvel/system_keys"'));
    });
    test('an activity written by an earlier Dartvel is brought up to date, not reported as edited', () {
      const String earlier = '''package com.example.home

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // dartvel.android.launcher: the phone's wallpaper shows through the app.
    override fun getBackgroundMode(): io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode =
        io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode.transparent

    // The home app is never closed by Back: Back on its first page does nothing,
    // as on every launcher, and the next press of home is not a cold start.
    override fun popSystemNavigator(): Boolean = true
}
''';
      final String? out = dvAndroidHomeLauncherActivity(earlier, enabled: true);
      expect(out, isNotNull);
      expect(out, contains('override fun onNewIntent('));
      expect(dvAndroidHomeLauncherActivity(out!, enabled: false), activity, reason: 'turning it off still restores Flutter\'s line');
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

  group('the opt-in Recents service (dartvel.android.recentsService: true)', () {
    // A home app can never be the phone's Recents. An accessibility service
    // the person turns on once can see the system's Recents open (or the
    // Recents key) and bring the home app's own Recents instead.
    test('read from dartvel.android.recentsService, and only with the launcher on', () {
      expect(dvAndroidRecentsServiceEnabled(<Object?, Object?>{'android': <Object?, Object?>{'launcher': true, 'recentsService': true}}), isTrue);
      expect(dvAndroidRecentsServiceEnabled(<Object?, Object?>{'android': <Object?, Object?>{'recentsService': true}}), isFalse);
      expect(dvAndroidRecentsServiceEnabled(<Object?, Object?>{'android': <Object?, Object?>{'launcher': true}}), isFalse);
    });

    test('the manifest declares the service, bound only by the system, and turning it off removes it', () {
      final String launcher = dvAndroidHomeLauncherManifest(_manifest, enabled: true);
      final String out = dvAndroidRecentsServiceManifest(launcher, enabled: true);
      expect(out, contains('android:name=".DartvelRecentsService"'));
      expect(out, contains('android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"'));
      expect(out, contains('android.accessibilityservice.AccessibilityService'));
      expect(out, contains('@xml/dartvel_recents_service'));
      expect(out.indexOf('DartvelRecentsService'), lessThan(out.indexOf('</application>')));
      expect(dvAndroidRecentsServiceManifest(out, enabled: true), out);
      expect(dvAndroidRecentsServiceManifest(out, enabled: false), launcher);
    });

    test('the service watches window changes, clicks and keys, and says what it is for', () {
      expect(dvAndroidRecentsServiceConfig, contains('typeWindowStateChanged'));
      expect(dvAndroidRecentsServiceConfig, contains('typeViewClicked'));
      expect(dvAndroidRecentsServiceConfig, contains('android:canRequestFilterKeyEvents="true"'));
      expect(dvAndroidRecentsServiceConfig, contains('@string/dartvel_recents_service_description'));
    });

    test('the service source is in the app\'s package and reports to the MainActivity', () {
      final String source = dvAndroidRecentsServiceSource('com.example.home');
      expect(source, startsWith('package com.example.home\n'));
      expect(source, contains('class DartvelRecentsService : android.accessibilityservice.AccessibilityService()'));
      expect(source, contains('MainActivity.dartvelCurrent'));
      expect(source, contains('KEYCODE_APP_SWITCH'));
      expect(source, contains('config_recentsComponentName'), reason: 'the phone names its own Recents; nothing is guessed per brand');
      expect(source, contains('"dev.dartvel.recentsFrom"'));
      // The system's Recents stays drawn over a home app that is brought
      // forward under it (Android 12 emulator: the home app got the intent
      // and the Recents cards stayed on screen). Home closes it first.
      expect(source, contains('performGlobalAction(GLOBAL_ACTION_HOME)'));
      expect(source.indexOf('performGlobalAction(GLOBAL_ACTION_HOME)'), lessThan(source.indexOf('startActivity(')), reason: 'Home first, then the app\'s Recents');
    });

    test('the MainActivity hears the service and the other Recents signals', () {
      final String out = dvAndroidHomeLauncherActivity('package com.example.home\n\nimport io.flutter.embedding.android.FlutterActivity\n\nclass MainActivity : FlutterActivity()\n', enabled: true)!;
      expect(out, contains('var dartvelCurrent: MainActivity?'));
      expect(out, contains('"dev.dartvel.recentsFrom"'));
      for (final String signal in <String>['"back"', '"pause"', '"stop"', '"userLeaveHint"', '"focus"', '"closeSystemDialogs"']) {
        expect(out, contains(signal), reason: signal);
      }
    });
  });
}
