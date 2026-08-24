// iOS platform bindings.
//
// The implementation reaches the Objective-C runtime through dart:ffi — no
// platform channels, per the native integration rule. This suite runs anywhere
// and asserts the capability list; the bindings themselves need a device or
// simulator and are exercised by the runtime-verification workflow.
import 'dart:io' show Platform;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capability list', () {
    test('it claims the clipboard and nothing else', () {
      expect(DVIosBindings.implemented,
          <String>{'clipboard.copy', 'clipboard.paste'});
    });

    test('screen.geometry is absent, and macOS has it', () {
      // Not an oversight and not effort. UIScreen.nativeBounds returns a
      // CGRect, and a struct return through objc_msgSend needs
      // objc_msgSend_stret on some ABIs — the wrong entry point corrupts the
      // stack. macOS sidesteps it with CoreGraphics; iOS has no equivalent C
      // path, so there is nowhere safe to get it from.
      expect(DVIosBindings.implemented, isNot(contains('screen.geometry')));
      expect(DVMacosBindings.implemented, contains('screen.geometry'));
    });

    test('window controls are absent because iOS has no windows', () {
      for (final name in <String>[
        'window.setTitle',
        'window.maximize',
        'window.minimize',
        'window.restore',
      ]) {
        expect(DVIosBindings.implemented, isNot(contains(name)));
      }
    });
  });

  group('registration', () {
    test('off iOS it declines rather than throwing', () {
      if (Platform.isIOS) {
        expect(DVIosBindings.register(), isTrue);
        DVIosBindings.unregister();
        return;
      }
      expect(DVIosBindings.register(), isFalse);
      expect(DVIosBindings.isRegistered, isFalse);
    });
  });
}
