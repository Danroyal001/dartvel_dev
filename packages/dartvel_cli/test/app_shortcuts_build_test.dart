import 'dart:io';

import 'package:dartvel_cli/src/build/app_shortcuts.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// `dartvel.appShortcuts` written where each platform reads it.
void main() {
  const List<DVAppShortcut> shortcuts = <DVAppShortcut>[
    DVAppShortcut(id: 'new-order', title: 'New order', route: '/orders/new', subtitle: "Start one, it's quick"),
    DVAppShortcut(id: 'search', title: 'Search', route: '/search', icon: 'icons/search.png'),
  ];

  group('web manifest', () {
    test('each shortcut is a manifest shortcut, url relative to the manifest', () {
      final List<Map<String, Object?>> out = dvPwaShortcuts(shortcuts, iconSizes: <String, int>{'icons/search.png': 96});
      expect(out[0], <String, Object?>{
        'name': 'New order',
        'short_name': 'New order',
        'description': "Start one, it's quick",
        'url': 'orders/new',
      });
      expect(out[1]['icons'], <Object?>[<String, Object?>{'src': 'icons/search.png', 'sizes': '96x96'}]);
    });

    test('the home route is the manifest directory', () {
      expect(dvPwaShortcuts(const <DVAppShortcut>[DVAppShortcut(id: 'home', title: 'Home', route: '/')]).single['url'], '.');
    });
  });

  group('Android', () {
    const String manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="demo">
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

    test('the meta-data goes inside the launcher activity, once', () {
      final String once = dvAndroidShortcutsManifest(manifest, enabled: true);
      final String twice = dvAndroidShortcutsManifest(once, enabled: true);
      expect(twice, once);
      final int activityClose = once.indexOf('</activity>');
      final int meta = once.indexOf('android.app.shortcuts');
      expect(meta, greaterThan(once.indexOf('<activity')));
      expect(meta, lessThan(activityClose));
      expect(once, contains('android:resource="@xml/dartvel_shortcuts"'));
    });

    test('turning it off gives the manifest back exactly', () {
      expect(dvAndroidShortcutsManifest(dvAndroidShortcutsManifest(manifest, enabled: true), enabled: false), manifest);
    });

    test('the launcher activity is resolved to its full class', () {
      expect(dvAndroidLauncherActivity(manifest, package: 'com.example.demo'), 'com.example.demo.MainActivity');
    });

    test('shortcuts.xml: an explicit VIEW intent carrying the launch link', () {
      final String xml = dvAndroidShortcutsXml(shortcuts, package: 'com.example.demo', activity: 'com.example.demo.MainActivity');
      expect(xml, contains('android:shortcutId="new-order"'));
      expect(xml, contains('android:shortcutShortLabel="@string/dartvel_shortcut_new_order_short"'));
      expect(xml, contains('android:action="android.intent.action.VIEW"'));
      expect(xml, contains('android:targetClass="com.example.demo.MainActivity"'));
      expect(xml, contains('android:data="dartvel:///orders/new"'));
    });

    test('labels are string resources aapt2 accepts', () {
      final String strings = dvAndroidShortcutStrings(shortcuts);
      expect(strings, contains('<string name="dartvel_shortcut_new_order_short">New order</string>'));
      expect(strings, contains(r"<string name=" '"dartvel_shortcut_new_order_long">Start one, it\\\'s quick</string>'));
    });

    test('writes the files and removes them when the declaration goes', () {
      final Directory root = Directory.systemTemp.createTempSync('dv-shortcuts-');
      addTearDown(() => root.deleteSync(recursive: true));
      final File file = File('${root.path}/android/app/src/main/AndroidManifest.xml')
        ..createSync(recursive: true)
        ..writeAsStringSync(manifest);
      final DVAppShortcutsWrite wrote = dvWriteAndroidAppShortcuts(root.path, shortcuts, package: 'com.example.demo');
      expect(wrote.problems, isEmpty);
      expect(File('${root.path}/android/app/src/main/res/xml/dartvel_shortcuts.xml').existsSync(), isTrue);
      expect(File('${root.path}/android/app/src/main/res/values/dartvel_shortcuts.xml').existsSync(), isTrue);
      dvWriteAndroidAppShortcuts(root.path, const <DVAppShortcut>[], package: 'com.example.demo');
      expect(file.readAsStringSync(), manifest);
      expect(File('${root.path}/android/app/src/main/res/xml/dartvel_shortcuts.xml').existsSync(), isFalse);
    });
  });

  group('iOS', () {
    const String plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>demo</string>
</dict>
</plist>
''';
    const String delegate = '''
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
''';

    test('UIApplicationShortcutItems, type is the launch link', () {
      final String out = dvIosShortcutItemsPlist(plist, shortcuts);
      expect(out, contains('<key>UIApplicationShortcutItems</key>'));
      expect(out, contains('<string>dartvel:///orders/new</string>'));
      expect(out, contains('<key>UIApplicationShortcutItemSubtitle</key>'));
      expect(out.indexOf('UIApplicationShortcutItems'), lessThan(out.lastIndexOf('</dict>')));
      expect(dvIosShortcutItemsPlist(out, shortcuts), out);
      expect(dvIosShortcutItemsPlist(out, const <DVAppShortcut>[]), plist);
    });

    test('the delegate stores the action where the launch link is read', () {
      final String out = dvIosQuickActionsDelegate(delegate, enabled: true, launchUrlKey: dvIosLaunchUrlKey);
      expect(out, contains('performActionFor shortcutItem: UIApplicationShortcutItem'));
      expect(out, contains('forKey: "$dvIosLaunchUrlKey"'));
      expect(out.trimRight(), endsWith('}'));
      expect(dvIosQuickActionsDelegate(out, enabled: true, launchUrlKey: dvIosLaunchUrlKey), out);
      expect(dvIosQuickActionsDelegate(out, enabled: false, launchUrlKey: dvIosLaunchUrlKey), delegate);
    });

    test('a delegate it cannot read is left alone', () {
      const String odd = 'import UIKit\n';
      expect(dvIosQuickActionsDelegate(odd, enabled: true, launchUrlKey: dvIosLaunchUrlKey), odd);
    });
  });

  group('Linux desktop entry', () {
    const String entry = '[Desktop Entry]\nType=Application\nName=Demo\nExec=/opt/demo/demo %U\n';

    test('Actions= and a group per shortcut, Exec with the route', () {
      final String out = dvDesktopShortcutActions(entry, shortcuts, exec: '/opt/demo/demo');
      expect(out, contains('Actions=new-order;search;'));
      expect(out, contains('[Desktop Action new-order]\nName=New order\nExec=/opt/demo/demo /orders/new'));
      expect(out.indexOf('Actions='), lessThan(out.indexOf('[Desktop Action')));
    });

    test('rewriting replaces rather than repeats, and none removes them', () {
      final String once = dvDesktopShortcutActions(entry, shortcuts, exec: '/opt/demo/demo');
      expect(dvDesktopShortcutActions(once, shortcuts, exec: '/opt/demo/demo'), once);
      expect(dvDesktopShortcutActions(once, const <DVAppShortcut>[], exec: '/opt/demo/demo'), entry);
    });
  });

  test('a route no page has is reported', () {
    expect(dvAppShortcutUnknownRoutes(shortcuts, <String>['/orders/:id', '/']), <String>['search: /search']);
  });
}
