// A tvOS build reported itself as an iOS tablet.
//
// Found by running the app on a tvOS simulator and reading the screenshot: it
// rendered correctly at 4K and said `Platform: ios`, `Device: tablet`. The
// simulator presents itself to Flutter as iOS — there is no TargetPlatform.tvOS
// — so nothing downstream could tell, and `isAppleTV` never fired.
//
// It matters beyond a label. An application branching on `isTV` or `deviceType`
// takes the touch-and-tablet path on a device driven by a remote control: no
// focus traversal, tap targets sized for fingers, and gestures nothing can
// produce.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tvOS is a television, not a tablet', () {
    test('the tvos platform resolves to a tv device', () {
      expect(dvDeviceTypeFor(platform: 'tvos', breakpoint: 'desktop'), 'tv');
      // A 4K television is wide, so the breakpoint alone would have said
      // desktop — which is how it ended up as a tablet in the first place.
      expect(dvDeviceTypeFor(platform: 'tvos', breakpoint: 'tablet'), 'tv');
    });

    test('appletv, the spelling the platform getters already used, also works',
        () {
      // isAppleTV compared currentPlatform against 'appletv' while nothing ever
      // produced that string. Both spellings resolve now, so the getter is not
      // left testing for a value that never occurs.
      expect(dvDeviceTypeFor(platform: 'appletv', breakpoint: 'desktop'), 'tv');
    });

    test('plain iOS is unaffected', () {
      // The fix must not make every iPad a television.
      expect(dvDeviceTypeFor(platform: 'ios', breakpoint: 'tablet'), 'tablet');
      expect(dvDeviceTypeFor(platform: 'ios', breakpoint: 'mobile'), 'phone');
    });

    test('the other televisions still resolve', () {
      for (final platform in <String>['tizen', 'webos', 'androidtv']) {
        expect(dvDeviceTypeFor(platform: platform, breakpoint: 'desktop'), 'tv',
            reason: '$platform is a television');
      }
    });
  });
}
