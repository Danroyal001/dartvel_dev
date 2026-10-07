// What a tray-resident application needs besides the icon: keeping running
// when its window is closed, bringing the window back from the tray, and
// starting when the user logs in.
//
// The Dart side decides; the bindings ask it. Closing the main window hides
// it under `exitPolicy: explicit` and closes it otherwise -- the binding
// calls `DVWindowManager.closeHidesWindow` from the native close hook -- so
// the decision is tested here, once, rather than three times in FFI.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_launch_at_login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> calls = <String>[];
  setUp(() {
    calls.clear();
    DVWindowManager.reset();
    for (final String name in <String>['window.show', 'window.hide']) {
      DVNativeBridge.register(name, (Object? _) {
        calls.add(name);
        return true;
      });
    }
  });
  tearDown(() {
    DVNativeBridge.unregister('window.show');
    DVNativeBridge.unregister('window.hide');
    DVWindowManager.reset();
  });

  group('the main window, from the tray', () {
    test('hide and show reach the bindings', () async {
      await DV.Platform.window.hide();
      await DV.Platform.window.show();
      expect(calls, <String>['window.hide', 'window.show']);
    });

    test('a platform with no binding says so instead of doing nothing', () async {
      DVNativeBridge.unregister('window.show');
      await expectLater(DV.Platform.window.show(), throwsA(isA<StateError>()));
    });
  });

  group('closing the main window', () {
    test('closes it by default, as a desktop application does', () {
      expect(DVWindowManager.closeHidesWindow, isFalse);
    });

    test('hides it under exitPolicy explicit, which is the tray-resident policy', () {
      DVWindowManager.exitPolicy = .explicit;
      expect(DVWindowManager.closeHidesWindow, isTrue);
    });

    test('closes it again under mainWindow and lastWindow', () {
      for (final DVWindowExitPolicy policy in <DVWindowExitPolicy>[.mainWindow, .lastWindow]) {
        DVWindowManager.exitPolicy = policy;
        expect(DVWindowManager.closeHidesWindow, isFalse, reason: policy.name);
      }
    });
  });

  group('launch at login, through the bridge', () {
    final List<Object?> sent = <Object?>[];
    bool enabled = false;
    setUp(() {
      sent.clear();
      enabled = false;
      DVNativeBridge.register('launchAtLogin.isEnabled', (Object? _) => enabled);
      DVNativeBridge.register('launchAtLogin.setEnabled', (Object? arguments) {
        sent.add(arguments);
        enabled = (arguments! as Map)['enabled'] == true;
        return true;
      });
    });
    tearDown(() {
      DVNativeBridge.unregister('launchAtLogin.isEnabled');
      DVNativeBridge.unregister('launchAtLogin.setEnabled');
    });

    test('reads and sets the state', () async {
      expect(await DV.Platform.launchAtLogin.isEnabled(), isFalse);
      await DV.Platform.launchAtLogin.setEnabled(true);
      expect(sent.single, <String, Object?>{'enabled': true});
      expect(await DV.Platform.launchAtLogin.isEnabled(), isTrue);
    });

    test('isSupported follows the binding', () {
      expect(DV.Platform.launchAtLogin.isSupported, isTrue);
      DVNativeBridge.unregister('launchAtLogin.isEnabled');
      expect(DV.Platform.launchAtLogin.isSupported, isFalse);
    });

    test('a binding that refuses is an error, not a setting that did not stick', () async {
      DVNativeBridge.register('launchAtLogin.setEnabled', (Object? _) => false);
      await expectLater(DV.Platform.launchAtLogin.setEnabled(true), throwsA(isA<StateError>()));
    });
  });

  group('launch at login on Linux: an XDG autostart entry', () {
    late Directory config;
    setUp(() => config = Directory.systemTemp.createTempSync('dv_autostart'));
    tearDown(() => config.deleteSync(recursive: true));

    DVLinuxLaunchAtLogin entry() => DVLinuxLaunchAtLogin(
          configHome: config.path,
          executable: '/opt/My App/my_app',
          name: 'My App',
        );

    test('is off until it is turned on', () {
      expect(entry().isEnabled, isFalse);
    });

    test('turning it on writes a desktop entry the session starts', () {
      entry().setEnabled(true);
      final File file = File('${config.path}/autostart/my_app.desktop');
      expect(file.existsSync(), isTrue);
      final String text = file.readAsStringSync();
      expect(text, startsWith('[Desktop Entry]\n'));
      expect(text, contains('Type=Application\n'));
      expect(text, contains('Name=My App\n'));
      // Quoted: the path has a space, and an unquoted Exec runs "/opt/My".
      expect(text, contains('Exec="/opt/My App/my_app"\n'));
      expect(text, contains('X-GNOME-Autostart-enabled=true\n'));
      expect(entry().isEnabled, isTrue);
    });

    test('turning it off removes the entry', () {
      entry().setEnabled(true);
      entry().setEnabled(false);
      expect(File('${config.path}/autostart/my_app.desktop').existsSync(), isFalse);
      expect(entry().isEnabled, isFalse);
    });

    test('an entry the user disabled in their session settings reads as off', () {
      entry().setEnabled(true);
      final File file = File('${config.path}/autostart/my_app.desktop');
      file.writeAsStringSync('${file.readAsStringSync()}Hidden=true\n');
      expect(entry().isEnabled, isFalse);
    });
  });
}
