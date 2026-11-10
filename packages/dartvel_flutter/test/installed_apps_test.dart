// DV.Platform.apps: the apps installed on the device that can be launched,
// and opening one. A launcher is the obvious user, but a "share to", an
// "open with" or a parental-controls screen needs the same list.
//
// The JNI half needs a device. These cover the half that does not: what the
// application sees from whatever the binding hands back, and what it sends.
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    for (final String name in const ['apps.list', 'apps.open', 'apps.openSettings', 'apps.uninstall', 'apps.icon', 'apps.isDefaultLauncher', 'apps.requestDefaultLauncher']) {
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
}
