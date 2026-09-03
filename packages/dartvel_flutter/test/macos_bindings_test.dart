// macOS platform bindings.
//
// The implementation reaches the Objective-C runtime and CoreGraphics through
// dart:ffi — no platform channels, per the native integration rule. This suite
// runs anywhere and asserts the capability list and the refusal to register
// elsewhere; the bindings themselves are exercised by the `apple-bindings` CI
// job on a macOS runner, which is the only place they can be.
import 'dart:io' show Platform;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capability list', () {
    test('it claims exactly what is bound', () {
      expect(
        DVMacosBindings.implemented,
        <String>{
          'clipboard.copy',
          'clipboard.paste',
          'screen.geometry',
          // NSApplication presentation options, for a kiosk.
          'kiosk.enforce',
          'kiosk.release',
        },
      );
    });

    test('notifications are deliberately absent', () {
      // UNUserNotificationCenter needs a bundled, signed application with the
      // right entitlement, and NSUserNotification is removed. A binding that
      // worked in a signed bundle and silently did nothing elsewhere would
      // look like it worked in development, which is the worst outcome.
      expect(DVMacosBindings.implemented,
          isNot(contains('notifications.sendLocal')));
    });

    test('window controls are absent, and that is a thread-safety decision',
        () {
      // They need NSApp.keyWindow, and reading it through the Objective-C
      // runtime from Dart's isolate is not reliably on the main thread.
      // Getting that wrong crashes rather than misbehaves.
      for (final name in <String>[
        'window.setTitle',
        'window.maximize',
        'window.minimize',
        'window.restore',
      ]) {
        expect(DVMacosBindings.implemented, isNot(contains(name)));
      }
    });
  });

  group('registration', () {
    test('off macOS it declines rather than throwing', () {
      // An application calls register() unconditionally at startup.
      if (Platform.isMacOS) {
        expect(DVMacosBindings.register(), isTrue);
        DVMacosBindings.unregister();
        return;
      }
      expect(DVMacosBindings.register(), isFalse);
      expect(DVMacosBindings.isRegistered, isFalse);
    });
  });
}
