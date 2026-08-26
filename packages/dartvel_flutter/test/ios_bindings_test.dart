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
    test('it claims the clipboard and haptics', () {
      expect(DVIosBindings.implemented, <String>{
        'clipboard.copy',
        'clipboard.paste',
        'haptics.impact',
        'haptics.lightVibrate',
        'haptics.vibrate',
      });
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

  // Haptics were left out because UIImpactFeedbackGenerator has to be built
  // and called on the main thread, and Flutter's root isolate runs on the UI
  // thread. That rules out the Objective-C route, not haptics: AudioToolbox
  // exposes AudioServicesPlaySystemSound, a plain C function that is safe to
  // call from any thread, and system sound IDs in the 1519-1521 range are the
  // haptic taps rather than sounds.
  //
  // Which ID goes with which strength is the part worth testing. A wrong one
  // does not throw -- it plays an audible alert on a device that is meant to
  // tap silently, or taps at the wrong strength, and looks like it worked.
  group('haptic sound identifiers', () {
    test('each strength maps to a distinct haptic identifier', () {
      final ids = <int>{
        dvIosHapticSoundId('haptics.lightVibrate'),
        dvIosHapticSoundId('haptics.impact'),
        dvIosHapticSoundId('haptics.vibrate'),
      };

      expect(ids.length, 3, reason: 'two strengths share an identifier');
    });

    test('the light tap is peek and the impact is pop', () {
      expect(dvIosHapticSoundId('haptics.lightVibrate'), 1519);
      expect(dvIosHapticSoundId('haptics.impact'), 1520);
    });

    test('a full vibrate is the vibrate identifier, not a haptic tap', () {
      // 4095 is kSystemSoundID_Vibrate. The 1519-1521 taps are silent on a
      // device with a Taptic Engine and do nothing at all on one without,
      // so the full vibrate has to be the real thing.
      expect(dvIosHapticSoundId('haptics.vibrate'), 4095);
    });

    test('an unknown name does not silently become a sound', () {
      // Falling back to 0, or to any id below 1000, would play a system alert
      // sound out loud.
      expect(() => dvIosHapticSoundId('haptics.nonexistent'),
          throwsArgumentError);
    });
  });

  group('registration is all or nothing', () {
    // The capability list is what callers consult. A registration that
    // installed the clipboard and then found AudioToolbox missing would leave
    // `implemented` claiming three haptics that throw when called -- the
    // drift this file's own comment warns about.
    test('every name it claims is a name it registers', () {
      if (!Platform.isIOS) return;

      expect(DVIosBindings.register(), isTrue);
      for (final String name in DVIosBindings.implemented) {
        expect(DVNativeBridge.isRegistered(name), isTrue,
            reason: '$name is claimed but not registered');
      }
      DVIosBindings.unregister();
      for (final String name in DVIosBindings.implemented) {
        expect(DVNativeBridge.isRegistered(name), isFalse);
      }
    });
  });
}
