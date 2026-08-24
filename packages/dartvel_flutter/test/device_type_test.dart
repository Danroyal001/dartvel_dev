// `deviceType` answered from screen width alone, so the same desktop
// application reported a different device depending on how wide its window
// happened to be.
//
// Caught by running the same app on two platforms and looking at both: Linux
// at 1280px reported `desktop`, Windows at 1024px reported `tablet`. Same
// framework, same app, same class of machine — the only difference was the
// window. Anything branching on deviceType took the tablet path on Windows.
//
// Width is the right input for *layout*, which is what `breakpoint` is for and
// which is unchanged. It is the wrong input for "what kind of device is this".
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deviceType', () {
    test('a desktop OS is a desktop at any window size', () {
      // The bug, stated directly: 1024 is below the 1200 desktop breakpoint.
      for (final platform in <String>['linux', 'macos', 'windows']) {
        expect(
          dvDeviceTypeFor(platform: platform, breakpoint: 'tablet'),
          'desktop',
          reason: '$platform is a desktop OS however narrow the window is',
        );
        expect(
          dvDeviceTypeFor(platform: platform, breakpoint: 'mobile'),
          'desktop',
          reason: '$platform stays a desktop even in a very small window',
        );
      }
    });

    test('a phone-sized window on a phone is still a phone', () {
      expect(dvDeviceTypeFor(platform: 'android', breakpoint: 'mobile'),
          'phone');
      expect(dvDeviceTypeFor(platform: 'ios', breakpoint: 'mobile'), 'phone');
    });

    test('a large mobile screen is a tablet', () {
      // Where width genuinely is the signal: mobile OSes run on both.
      expect(dvDeviceTypeFor(platform: 'android', breakpoint: 'tablet'),
          'tablet');
      expect(dvDeviceTypeFor(platform: 'ios', breakpoint: 'desktop'), 'tablet',
          reason: 'an iPad in a wide layout is a tablet, not a desktop');
    });

    test('the explicit kinds win over both', () {
      // A television is a television at any width, and reporting it as a
      // desktop would send an app down the pointer-and-window path on a
      // device driven by a remote control.
      expect(
        dvDeviceTypeFor(platform: 'linux', breakpoint: 'desktop', isTV: true),
        'tv',
      );
      expect(
        dvDeviceTypeFor(platform: 'android', breakpoint: 'mobile', isWatch: true),
        'watch',
      );
      expect(
        dvDeviceTypeFor(platform: 'web', breakpoint: 'desktop', isWeb: true),
        'web',
      );
    });
  });
}
