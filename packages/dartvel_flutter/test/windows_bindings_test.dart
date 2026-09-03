// Windows platform bindings.
//
// The implementation is Win32 through dart:ffi — no platform channels, per the
// native integration rule. This suite runs on any host and asserts the
// capability list and the refusal to register off-Windows; the bindings
// themselves are exercised by the `windows-bindings` CI job, which runs on a
// Windows runner and is the only place they can be.
import 'dart:io' show Platform;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capability list', () {
    test('it claims exactly what Win32 is bound for', () {
      expect(
        DVWindowsBindings.implemented,
        <String>{
          'clipboard.copy',
          'clipboard.paste',
          'screen.geometry',
          'window.setTitle',
          'window.maximize',
          'window.minimize',
          'window.restore',
          'window.setSize',
          // RegisterHotKey, ClipCursor and the window style, for a kiosk.
          'kiosk.enforce',
          'kiosk.release',
          // RegisterHotKey on a pump thread of its own, delivering WM_HOTKEY.
          'shortcuts.register',
          'shortcuts.unregister',
          // The shared device runtime, reading through this platform's probes.
          'device.capabilityManifest',
          'device.health',
          'device.watchdog.arm',
          'device.watchdog.heartbeat',
          'device.fleet.provision',
          'device.diagnostics.collect',
          // A Win32 menu bar on the process's window, WM_COMMAND by id.
          'menus.setApplicationMenu',
          // Shell_NotifyIcon on the process's window, its menu by id.
          'tray.show',
          'tray.hide',
          // What a desktop grants without asking, and the deep link the app was
          // launched with.
          'permissions.isGranted',
          'permissions.request',
          'deepLinks.initial',
          // The common dialogs and the folder browser, answered from their own
          // hooks under automation.
          'dialogs.openFile',
          'dialogs.saveFile',
          'dialogs.chooseDirectory',
          'dialogs.message',
          'media.pick',
          // Pictures onto pages: to a PDF through Microsoft Print to PDF, or
          // to the default printer.
          'printing.toFile',
          'printing.print',
        },
      );
    });

    test('notifications are deliberately absent', () {
      // A modern toast needs an AppUserModelID registered against a real Start
      // Menu shortcut, and the legacy Shell_NotifyIcon balloon is deprecated
      // and silently ignored under Focus Assist. Either would be a binding
      // that reports success and shows nothing — worse than the "not
      // registered" error, because it looks like it worked.
      expect(DVWindowsBindings.implemented,
          isNot(contains('notifications.sendLocal')));
    });

    test('it claims nothing the framework does not call', () {
      const callable = <String>{
        'clipboard.copy',
        'clipboard.paste',
        'screen.geometry',
        'window.setTitle',
        'window.maximize',
        'window.minimize',
        'window.restore',
        'window.setSize',
        'kiosk.enforce',
        'kiosk.release',
        'shortcuts.register',
        'shortcuts.unregister',
        'device.capabilityManifest',
        'device.health',
        'device.watchdog.arm',
        'device.watchdog.heartbeat',
        'device.fleet.provision',
        'device.diagnostics.collect',
        'menus.setApplicationMenu',
        'window.persistState',
        'window.restoreState',
        'notifications.sendLocal',
        'tray.show',
        'tray.hide',
        'printing.toFile',
        'printing.print',
        'permissions.isGranted',
        'permissions.request',
        'deepLinks.initial',
        'dialogs.openFile',
        'dialogs.saveFile',
        'dialogs.chooseDirectory',
        'dialogs.message',
        'media.pick',
      };
      expect(DVWindowsBindings.implemented.difference(callable), isEmpty);
    });
  });

  group('registration', () {
    test('off Windows it declines rather than throwing', () {
      // An application calls register() unconditionally at startup, so the
      // wrong platform has to be a quiet false and not an exception.
      if (Platform.isWindows) {
        expect(DVWindowsBindings.register(), isTrue);
        DVWindowsBindings.unregister();
        return;
      }
      expect(DVWindowsBindings.register(), isFalse);
      expect(DVWindowsBindings.isRegistered, isFalse);
    });
  });
}
