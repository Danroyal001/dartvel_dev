// A Horizon OS build and a Vision Pro build are headsets, not a phone and a
// tablet.
//
// Neither can tell at run time without a native binding: Horizon OS presents
// itself to Flutter as Android, and Vision Pro runs the iPad app, which
// presents itself as iOS on an iPad-sized window. `dartvel build horizon` and
// `dartvel build visionos` stamp DARTVEL_PLATFORM, and these are the answers
// DV.Platform gives from it. The same lesson as tvOS: a wide screen and a
// mobile OS read as a tablet, and an application branching on deviceType then
// takes the touch path on a device driven by hands and controllers.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('headsets', () {
    test('horizon and visionos are headsets at any width', () {
      for (final String platform in <String>['horizon', 'visionos']) {
        for (final String breakpoint in <String>['mobile', 'tablet', 'desktop']) {
          expect(dvDeviceTypeFor(platform: platform, breakpoint: breakpoint), 'headset',
              reason: '$platform at $breakpoint');
        }
        expect(dvIsHeadsetPlatform(platform), isTrue);
      }
    });

    test('nothing else is a headset', () {
      for (final String platform in <String>['android', 'ios', 'fireos', 'tvos', 'web', 'linux']) {
        expect(dvIsHeadsetPlatform(platform), isFalse, reason: platform);
      }
      expect(dvDeviceTypeFor(platform: 'android', breakpoint: 'tablet'), 'tablet');
      expect(dvDeviceTypeFor(platform: 'ios', breakpoint: 'mobile'), 'phone');
    });

    test('a Horizon app is still an Android app, and a Vision Pro one an iOS app', () {
      // The bindings behind DV.Platform are JNI on one and FFI over the iOS
      // frameworks on the other, and they are exactly the ones that run there.
      expect(dvIsAndroidFamily('horizon'), isTrue);
      expect(dvIsAndroidFamily('fireos'), isTrue);
      expect(dvIsAndroidFamily('android'), isTrue);
      expect(dvIsAndroidFamily('visionos'), isFalse);
      expect(dvIsIOSFamily('visionos'), isTrue);
      expect(dvIsIOSFamily('ios'), isTrue);
      expect(dvIsIOSFamily('tvos'), isFalse);
      expect(dvIsIOSFamily('horizon'), isFalse);
    });

    test('a headset is not a television', () {
      expect(dvDeviceTypeFor(platform: 'horizon', breakpoint: 'desktop', isTV: false), 'headset');
    });
  });
}
