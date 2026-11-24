// What a home-screen app needs beyond listing and opening apps, as every
// standard Android launcher has it: an app's own shortcuts (LauncherApps),
// installs and uninstalls as they happen, the notification shade, locking
// the screen, the wallpaper picker, the system's settings pages, and
// notification counts for badges.
//
// The Android half runs in the MainActivity and services the build writes
// (android_home_launcher.dart in dartvel_cli, tested there) and in JNI. These
// cover what the application sees from what that half answers.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/services.dart' show ByteData, StringCodec;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<String?> asked = <String?>[];
  Map<String, String?> answers = <String, String?>{};

  void answer(Map<String, String?> replies) {
    answers = replies;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('dev.dartvel/home_app', (ByteData? message) async {
      final String? question = const StringCodec().decodeMessage(message);
      asked.add(question);
      final String key = answers.keys.firstWhere((String each) => question == each || (each.endsWith('*') && (question ?? '').startsWith(each.substring(0, each.length - 1))), orElse: () => '');
      return key.isEmpty ? null : const StringCodec().encodeMessage(answers[key]);
    });
  }

  Future<void> systemKey(String message) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage(message), (ByteData? _) {});
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    asked.clear();
    // A home app: the binding the launcher MainActivity comes with.
    DVNativeBridge.register('apps.homePressedAt', (Object? _) => 0);
  });

  tearDown(() {
    for (final String name in const <String>['apps.homePressedAt', 'apps.pickWallpaper', 'apps.openSystemSettings']) {
      DVNativeBridge.unregister(name);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('dev.dartvel/home_app', null);
  });

  group('an app\'s own shortcuts', () {
    test('are read from the activity, with their names and icons', () async {
      final Uint8List png = Uint8List.fromList(const <int>[137, 80, 78, 71]);
      answer(<String, String?>{
        'shortcuts.list:com.whatsapp': jsonEncode(<Object?>[
          <String, Object?>{'id': 'new_chat', 'label': 'New chat', 'icon': base64Encode(png)},
          <String, Object?>{'id': 'camera', 'label': 'Camera'},
        ]),
      });
      final List<DVInstalledAppShortcut> shortcuts = await const DVApps().shortcuts('com.whatsapp');
      expect(asked, <String?>['shortcuts.list:com.whatsapp']);
      expect(shortcuts.map((DVInstalledAppShortcut each) => '${each.packageName}/${each.id}=${each.label}'), <String>['com.whatsapp/new_chat=New chat', 'com.whatsapp/camera=Camera']);
      expect(shortcuts.first.icon, png);
      expect(shortcuts.last.icon, isNull, reason: 'no icon sent is no icon, not an empty image');
    });

    test('a shortcut with no id or name is left out rather than shown blank', () async {
      answer(<String, String?>{
        'shortcuts.list:*': jsonEncode(<Object?>[
          <String, Object?>{'id': '', 'label': 'Nothing'},
          <String, Object?>{'id': 'x', 'label': ' '},
          <String, Object?>{'id': 'ok', 'label': 'Fine'},
        ]),
      });
      expect((await const DVApps().shortcuts('com.example')).map((DVInstalledAppShortcut each) => each.id), <String>['ok']);
    });

    test('Android lets only the home app read them: anything else says so', () async {
      answer(<String, String?>{'shortcuts.list:*': 'denied'});
      await expectLater(const DVApps().shortcuts('com.whatsapp'), throwsA(isA<StateError>().having((StateError error) => error.message, 'message', contains('home app'))));
    });

    test('where nothing answers (not Android, an older build) they are unsupported, not an empty list', () async {
      await expectLater(const DVApps().shortcuts('com.whatsapp'), throwsA(isA<UnsupportedError>()));
      DVNativeBridge.unregister('apps.homePressedAt');
      await expectLater(const DVApps().shortcuts('com.whatsapp'), throwsA(isA<UnsupportedError>()));
    });

    test('opening one asks for that app and id; a refusal is an error', () async {
      answer(<String, String?>{'shortcuts.open:com.whatsapp:new_chat': 'true', 'shortcuts.open:com.whatsapp:gone': 'false'});
      const DVInstalledAppShortcut chat = DVInstalledAppShortcut(packageName: 'com.whatsapp', id: 'new_chat', label: 'New chat');
      await const DVApps().openShortcut(chat);
      expect(asked.last, 'shortcuts.open:com.whatsapp:new_chat');
      await expectLater(const DVApps().openShortcut(const DVInstalledAppShortcut(packageName: 'com.whatsapp', id: 'gone', label: 'Gone')), throwsA(isA<StateError>()));
    });
  });

  group('installs and uninstalls as they happen', () {
    test('each package broadcast is one change, with its kind and package', () async {
      final List<String> heard = <String>[];
      final subscription = const DVApps().packageChanges.listen((DVPackageChange change) => heard.add('${change.kind.name} ${change.packageName}'));
      addTearDown(subscription.cancel);
      await systemKey('package:100:added:com.termux');
      await systemKey('package:101:removed:org.example.old');
      await systemKey('package:102:replaced:com.whatsapp');
      await systemKey('package:103:changed:com.android.chrome');
      await systemKey('home:104');
      await systemKey('package:105:unknown:com.example');
      expect(heard, <String>['added com.termux', 'removed org.example.old', 'replaced com.whatsapp', 'changed com.android.chrome']);
    });

    test('where the app is not a home app, the stream is empty', () async {
      DVNativeBridge.unregister('apps.homePressedAt');
      expect(await const DVApps().packageChanges.isEmpty, isTrue);
    });
  });

  group('the system around the home screen', () {
    test('pulls down the notification shade, and says when the phone would not', () async {
      answer(<String, String?>{'notifications.expand': 'true'});
      expect(await const DVApps().expandNotifications(), isTrue);
      answer(<String, String?>{'notifications.expand': 'false'});
      expect(await const DVApps().expandNotifications(), isFalse);
      answer(<String, String?>{});
      expect(await const DVApps().expandNotifications(), isFalse, reason: 'nothing answering is a shade that did not open');
    });

    test('locks the screen through the opt-in accessibility service, false while it is off', () async {
      answer(<String, String?>{'screen.lock': 'true'});
      expect(await const DVApps().lockScreen(), isTrue);
      answer(<String, String?>{'screen.lock': 'false'});
      expect(await const DVApps().lockScreen(), isFalse);
      expect(asked, <String?>['screen.lock', 'screen.lock']);
    });

    test('opens the wallpaper picker', () async {
      int opened = 0;
      DVNativeBridge.register('apps.pickWallpaper', (Object? _) {
        opened++;
        return true;
      });
      await const DVApps().pickWallpaper();
      expect(opened, 1);
      DVNativeBridge.register('apps.pickWallpaper', (Object? _) => false);
      await expectLater(const DVApps().pickWallpaper(), throwsA(isA<StateError>()));
      DVNativeBridge.unregister('apps.pickWallpaper');
      await expectLater(const DVApps().pickWallpaper(), throwsA(isA<UnsupportedError>()));
    });

    test('opens a page of the system settings by name', () async {
      final List<Object?> pages = <Object?>[];
      DVNativeBridge.register('apps.openSystemSettings', (Object? arguments) {
        pages.add((arguments! as Map<Object?, Object?>)['page']);
        return true;
      });
      await const DVApps().openSystemSettings(DVSystemSettingsPage.wifi);
      await const DVApps().openSystemSettings();
      expect(pages, <Object?>['wifi', 'main']);
      DVNativeBridge.register('apps.openSystemSettings', (Object? _) => false);
      await expectLater(const DVApps().openSystemSettings(DVSystemSettingsPage.bluetooth), throwsA(isA<StateError>()));
    });

    test('every settings page has words a search can find it by', () {
      for (final DVSystemSettingsPage page in DVSystemSettingsPage.values) {
        expect(page.title, isNotEmpty, reason: page.name);
        expect(page.keywords, isNotEmpty, reason: page.name);
      }
      expect(DVSystemSettingsPage.wifi.keywords, contains('wifi'));
    });
  });

  group('notification counts, for badges', () {
    test('start with what is showing, then follow each change', () async {
      answer(<String, String?>{'badges.current': jsonEncode(<String, int>{'com.whatsapp': 3})});
      final List<Map<String, int>> heard = <Map<String, int>>[];
      final subscription = const DVApps().notificationCounts.listen(heard.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await systemKey('badges:200:${jsonEncode(<String, int>{'com.whatsapp': 4, 'com.google.android.gm': 1})}');
      await systemKey('badges:201:{}');
      expect(heard, <Map<String, int>>[
        <String, int>{'com.whatsapp': 3},
        <String, int>{'com.whatsapp': 4, 'com.google.android.gm': 1},
        <String, int>{},
      ]);
    });

    test('a broken answer is no counts, not a crash', () async {
      answer(<String, String?>{'badges.current': 'not json'});
      expect(await const DVApps().notificationCounts.first, <String, int>{});
    });

    test('notification access: on or off is asked of the activity, and its settings page opened', () async {
      expect(await const DVApps().isNotificationAccessOn, isFalse, reason: 'nothing answering is off');
      await expectLater(const DVApps().openNotificationAccessSettings(), throwsA(isA<UnsupportedError>()));
      answer(<String, String?>{'badges.isOn': 'true', 'badges.settings': 'true'});
      expect(await const DVApps().isNotificationAccessOn, isTrue);
      await const DVApps().openNotificationAccessSettings();
      expect(asked.where((String? question) => question!.startsWith('badges.')), <String?>['badges.isOn', 'badges.settings']);
    });
  });
}
