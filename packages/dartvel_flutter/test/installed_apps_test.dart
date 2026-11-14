// DV.Platform.apps: the apps installed on the device that can be launched,
// and opening one. A launcher is the obvious user, but a "share to", an
// "open with" or a parental-controls screen needs the same list.
//
// The JNI half needs a device. These cover the half that does not: what the
// application sees from whatever the binding hands back, and what it sends.
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, StringCodec;
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    for (final String name in const ['apps.list', 'apps.open', 'apps.openSettings', 'apps.uninstall', 'apps.icon', 'apps.isDefaultLauncher', 'apps.requestDefaultLauncher', 'apps.defaultFor', 'apps.homePressedAt', 'apps.recentsPressedAt']) {
      DVNativeBridge.unregister(name);
    }
  });

  test('lists the launchable apps by name, ignoring case', () async {
    final Uint8List icon = Uint8List.fromList(const [137, 80, 78, 71]);
    DVNativeBridge.register('apps.list', (Object? _) => <Object?>[
          <String, Object?>{'package': 'com.termux', 'label': 'termux', 'icon': icon},
          <String, Object?>{'package': 'com.android.chrome', 'label': 'Chrome'},
          <String, Object?>{'package': 'com.github.android', 'label': 'GitHub'},
        ]);
    final List<DVInstalledApp> apps = await const DVApps().list();
    expect(apps.map((DVInstalledApp app) => app.label), ['Chrome', 'GitHub', 'termux']);
    expect(apps.last.packageName, 'com.termux');
    expect(apps.last.icon, icon);
    expect(apps.first.icon, isNull, reason: 'an app the binding sent no icon for has none, not an empty image');
  });

  test('an app with no label is shown by its package name rather than blank', () async {
    DVNativeBridge.register('apps.list', (Object? _) => <Object?>[
          <String, Object?>{'package': 'org.example.nameless', 'label': ''},
        ]);
    expect((await const DVApps().list()).single.label, 'org.example.nameless');
  });

  test('asks the binding not to draw icons when the caller does not want them', () async {
    Object? sent;
    DVNativeBridge.register('apps.list', (Object? arguments) {
      sent = arguments;
      return <Object?>[];
    });
    await const DVApps().list(icons: false);
    expect(sent, {'icons': false});
  });

  test('opens, shows the settings of, and uninstalls an app by its package', () async {
    final List<String> calls = [];
    for (final String name in const ['apps.open', 'apps.openSettings', 'apps.uninstall']) {
      DVNativeBridge.register(name, (Object? arguments) {
        calls.add('$name ${(arguments! as Map)['package']}');
        return true;
      });
    }
    const DVApps apps = DVApps();
    await apps.open('com.termux');
    await apps.openSettings('com.termux');
    await apps.uninstall('com.termux');
    expect(calls, ['apps.open com.termux', 'apps.openSettings com.termux', 'apps.uninstall com.termux']);
  });

  test('an app that cannot be opened is an error, not a silent no-op', () async {
    DVNativeBridge.register('apps.open', (Object? _) => false);
    await expectLater(const DVApps().open('com.gone'), throwsA(isA<StateError>()));
  });

  test('reports itself unsupported where no binding is registered', () async {
    expect(const DVApps().isSupported, isFalse);
    await expectLater(const DVApps().list(), throwsA(isA<UnsupportedError>()));
    DVNativeBridge.register('apps.list', (Object? _) => <Object?>[]);
    expect(const DVApps().isSupported, isTrue);
  });

  test('is DV.Platform.apps', () {
    expect(DV.Platform.apps, isA<DVApps>());
  });

  test('one app\'s icon on its own, so a launcher can show names first', () async {
    final Uint8List png = Uint8List.fromList(const [137, 80, 78, 71]);
    Object? sent;
    DVNativeBridge.register('apps.icon', (Object? arguments) {
      sent = arguments;
      return png;
    });
    expect(await const DVApps().icon('com.termux'), png);
    expect(sent, {'package': 'com.termux'});
  });

  test('an icon that cannot be drawn is null, not an empty image', () async {
    DVNativeBridge.register('apps.icon', (Object? _) => Uint8List(0));
    expect(await const DVApps().icon('com.broken'), isNull);
    DVNativeBridge.register('apps.icon', (Object? _) => null);
    expect(await const DVApps().icon('com.gone'), isNull);
  });

  test('says whether this app is the phone\'s home app', () async {
    DVNativeBridge.register('apps.isDefaultLauncher', (Object? _) => true);
    expect(await const DVApps().isDefaultLauncher(), isTrue);
    DVNativeBridge.register('apps.isDefaultLauncher', (Object? _) => false);
    expect(await const DVApps().isDefaultLauncher(), isFalse);
  });

  test('asks the system to make this app the home app', () async {
    int asked = 0;
    DVNativeBridge.register('apps.requestDefaultLauncher', (Object? _) {
      asked++;
      return true;
    });
    await const DVApps().requestDefaultLauncher();
    expect(asked, 1);
  });

  test('a device with no screen to ask on says so', () async {
    DVNativeBridge.register('apps.requestDefaultLauncher', (Object? _) => false);
    await expectLater(const DVApps().requestDefaultLauncher(), throwsA(isA<StateError>()));
  });

  test('where there is no home app to be, the calls are unsupported, not false', () async {
    await expectLater(const DVApps().isDefaultLauncher(), throwsA(isA<UnsupportedError>()));
    await expectLater(const DVApps().requestDefaultLauncher(), throwsA(isA<UnsupportedError>()));
    await expectLater(const DVApps().icon('com.termux'), throwsA(isA<UnsupportedError>()));
  });

  test('the app the phone opens for a role, as the person set it', () async {
    final List<Object?> asked = [];
    DVNativeBridge.register('apps.defaultFor', (Object? arguments) {
      asked.add((arguments! as Map)['role']);
      return const {'phone': 'com.google.android.dialer', 'browser': 'org.mozilla.firefox'}[(arguments as Map)['role']];
    });
    const DVApps apps = DVApps();
    expect(await apps.defaultFor(DVAppRole.browser), 'org.mozilla.firefox');
    expect(await apps.defaultFor(DVAppRole.phone), 'com.google.android.dialer');
    expect(await apps.defaultFor(DVAppRole.camera), isNull, reason: 'no app for a role is null, not an empty name');
    expect(asked, ['browser', 'phone', 'camera']);
  });

  test('every role the dock needs exists', () {
    expect(DVAppRole.values.map((DVAppRole role) => role.name), containsAll(<String>['phone', 'messages', 'browser', 'camera', 'email', 'maps']));
  });

  test('defaultFor is unsupported where no binding is registered', () async {
    await expectLater(const DVApps().defaultFor(DVAppRole.browser), throwsA(isA<UnsupportedError>()));
  });

  group('Home pressed on a home app', () {
    // Home from another app: a new intent, then a resume. The stamp read on
    // resume catches a press the channel did not deliver.
    testWidgets('each press of Home that lands on the app is one event; resuming from elsewhere is none', (WidgetTester tester) async {
      int stamp = 0;
      DVNativeBridge.register('apps.homePressedAt', (Object? _) => stamp);
      final List<int> presses = <int>[];
      final subscription = const DVApps().homePresses.listen((_) => presses.add(1));
      addTearDown(subscription.cancel);
      await tester.pump();

      Future<void> pauseAndResume() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump();
      }

      await pauseAndResume();
      expect(presses, isEmpty, reason: 'back from the notification shade or another app, no Home press');

      stamp = 1000;
      await pauseAndResume();
      expect(presses.length, 1);

      await pauseAndResume();
      expect(presses.length, 1, reason: 'the same stamp is the same press');

      stamp = 2000;
      await pauseAndResume();
      expect(presses.length, 2);
    });

    testWidgets('a stamp already there when listening starts is not a press', (WidgetTester tester) async {
      DVNativeBridge.register('apps.homePressedAt', (Object? _) => 500);
      final List<int> presses = <int>[];
      final subscription = const DVApps().homePresses.listen((_) => presses.add(1));
      addTearDown(subscription.cancel);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(presses, isEmpty);
    });

    test('where no home app can be, the stream is empty rather than an error', () async {
      expect(await const DVApps().homePresses.isEmpty, isTrue);
    });
  });

  group('the system keys a home app hears as they happen', () {
    // Android 10 and later hand Home to a home app that is already in front
    // as a new intent and nothing else: no pause, no resume (checked on an
    // Android 12 emulator with the app as the default home). So the build's
    // MainActivity tells the app at once, over the dev.dartvel/system_keys
    // channel, with the same stamp it puts on the intent.
    Future<void> systemKey(WidgetTester tester, String message) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage('dev.dartvel/system_keys', const StringCodec().encodeMessage(message), (ByteData? _) {});
      await tester.pump();
    }

    testWidgets('Home pressed while the app is in front, with no pause or resume, is one event', (WidgetTester tester) async {
      int stamp = 0;
      DVNativeBridge.register('apps.homePressedAt', (Object? _) => stamp);
      final List<int> presses = <int>[];
      final subscription = const DVApps().homePresses.listen((_) => presses.add(1));
      addTearDown(subscription.cancel);
      await tester.pump();

      stamp = 1000;
      await systemKey(tester, 'home:1000');
      expect(presses.length, 1, reason: 'the drawer closes while the launcher stays in front');

      // Home from another app: the new intent, then a resume. One press, not two.
      stamp = 2000;
      await systemKey(tester, 'home:2000');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(presses.length, 2);
    });

    testWidgets('Recents heard while the app stays in front is one event, without polling the binding', (WidgetTester tester) async {
      int looks = 0;
      DVNativeBridge.register('apps.recentsPressedAt', (Object? _) {
        looks++;
        return 0;
      });
      final List<int> presses = <int>[];
      final subscription = const DVApps().recentsPresses.listen((_) => presses.add(1));
      await tester.pump(const Duration(seconds: 1));

      await systemKey(tester, 'recents:100');
      await tester.pump(const Duration(seconds: 2));
      expect(presses.length, 1);
      await systemKey(tester, 'recents:100');
      await tester.pump(const Duration(seconds: 2));
      expect(presses.length, 1, reason: 'the same stamp is the same press');

      await tester.pump(const Duration(seconds: 10));
      expect(looks, lessThanOrEqualTo(1), reason: 'a home app is in front all day: no JNI call four times a second');
      subscription.cancel();
      await tester.pump(const Duration(seconds: 1));
    });

    test('where no home app can be, the Recents stream is empty', () async {
      expect(await const DVApps().recentsPresses.isEmpty, isTrue);
    });

    testWidgets('Recents that opened the system\'s Recents over the app is none', (WidgetTester tester) async {
      DVNativeBridge.register('apps.recentsPressedAt', (Object? _) => 0);
      final List<int> presses = <int>[];
      final subscription = const DVApps().recentsPresses.listen((_) => presses.add(1));
      await tester.pump(const Duration(seconds: 1));
      await systemKey(tester, 'recents:100');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(presses, isEmpty);
      subscription.cancel();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the Recents service bringing the app forward is a Recents press at once', (WidgetTester tester) async {
      DVNativeBridge.register('apps.recentsPressedAt', (Object? _) => 0);
      final List<int> presses = <int>[];
      final subscription = const DVApps().recentsPresses.listen((_) => presses.add(1));
      await tester.pump(const Duration(seconds: 1));
      // The app was behind the system's Recents when the service replaced it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await systemKey(tester, 'recentsReplaced:700:window');
      expect(presses.length, 1);
      await systemKey(tester, 'recentsReplaced:700:window');
      expect(presses.length, 1, reason: 'the same stamp is the same press');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      subscription.cancel();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the Recents service press counts even when the resume read the same stamp first', (WidgetTester tester) async {
      // Android 12 emulator: the activity stamps the intent, is paused and
      // resumed, and the resume's read of the stamp can land before the
      // channel message. The press must still be one event.
      int stamp = 0;
      DVNativeBridge.register('apps.recentsPressedAt', (Object? _) => stamp);
      final List<int> presses = <int>[];
      final subscription = const DVApps().recentsPresses.listen((_) => presses.add(1));
      await tester.pump(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      stamp = 900;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      await systemKey(tester, 'recentsReplaced:900:button');
      expect(presses.length, 1);
      subscription.cancel();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('every signal reaches homeAppSignals with its name, time and detail', (WidgetTester tester) async {
      DVNativeBridge.register('apps.homePressedAt', (Object? _) => 0);
      final List<DVHomeAppSignal> heard = <DVHomeAppSignal>[];
      final subscription = const DVApps().homeAppSignals.listen(heard.add);
      addTearDown(subscription.cancel);
      await systemKey(tester, 'closeSystemDialogs:1200:recentapps');
      await systemKey(tester, 'window:1500:com.android.launcher3/com.android.quickstep.RecentsActivity');
      await systemKey(tester, 'pause:1600');
      expect(heard.map((DVHomeAppSignal signal) => '${signal.name}@${signal.at}[${signal.detail}]'), <String>[
        'closeSystemDialogs@1200[recentapps]',
        'window@1500[com.android.launcher3/com.android.quickstep.RecentsActivity]',
        'pause@1600[]',
      ]);
    });

    testWidgets('the Recents service: on or off is asked of the activity; nothing answering is off', (WidgetTester tester) async {
      DVNativeBridge.register('apps.homePressedAt', (Object? _) => 0);
      // Platform channels answer on the real event loop.
      expect(await tester.runAsync(() => const DVApps().isRecentsServiceOn), isFalse);
      Object? refused;
      await tester.runAsync(() => const DVApps().openRecentsServiceSettings().catchError((Object error) {
            refused = error;
          }));
      expect(refused, isA<UnsupportedError>());
      final List<String?> asked = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMessageHandler('dev.dartvel/home_app', (ByteData? message) async {
        asked.add(const StringCodec().decodeMessage(message));
        return const StringCodec().encodeMessage('true');
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMessageHandler('dev.dartvel/home_app', null));
      expect(await tester.runAsync(() => const DVApps().isRecentsServiceOn), isTrue);
      await tester.runAsync(() => const DVApps().openRecentsServiceSettings());
      expect(asked, <String?>['recentsService.isOn', 'recentsService.settings']);
    });
  });
}
