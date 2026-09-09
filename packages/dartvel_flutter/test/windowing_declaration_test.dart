// What the project declared under `dartvel.windowing`, honoured.
//
// `windowing.web.inPageViews`, `windowing.web.openInNewWindow` and
// `windowing.android.freeform` are all in the specification and all read by
// nothing. The capability hard-coded what each platform can do, so a project
// that wrote `openInNewWindow: false` still got `multiWindow: true` on web,
// still offered the control, and still opened a browser window when somebody
// pressed it.
//
// The one rule the declaration obeys: it narrows what a platform offers and
// never widens it. A project cannot grant itself a second window on a phone
// by writing it down, and a capability that lied in that direction would be
// worse than one that ignored the setting -- a caller would offer a control
// and the call behind it would degrade.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVWindowingCapability web({
  bool? inPageViews,
  bool? openInNewWindow,
}) =>
    DVWindowingCapability.detect(
      isDesktop: false,
      isWeb: true,
      isAndroid: false,
      isTablet: false,
      isIOS: false,
      hasNativeWindowBinding: false,
      webInPageViews: inPageViews,
      webOpenInNewWindow: openInNewWindow,
    );

DVWindowingCapability android({bool? freeform}) =>
    DVWindowingCapability.detect(
      isDesktop: false,
      isWeb: false,
      isAndroid: true,
      isTablet: false,
      isIOS: false,
      hasNativeWindowBinding: false,
      androidFreeform: freeform,
    );

void main() {
  group('the web declaration', () {
    test('declaring nothing leaves the platform as it was', () {
      expect(web().inPageViews, isTrue);
      expect(web().multiWindow, isTrue);
    });

    test('inPageViews: false withdraws in-page views', () {
      expect(web(inPageViews: false).inPageViews, isFalse);
      // Only that one. A project that does not want embedded views still
      // wants its windows.
      expect(web(inPageViews: false).multiWindow, isTrue);
    });

    test('openInNewWindow: false withdraws the second window', () {
      expect(web(openInNewWindow: false).multiWindow, isFalse);
      expect(web(openInNewWindow: false).inPageViews, isTrue);
    });

    test('declaring true is the same as declaring nothing', () {
      expect(web(inPageViews: true).inPageViews, isTrue);
      expect(web(openInNewWindow: true).multiWindow, isTrue);
    });
  });

  group('the android declaration', () {
    test('auto -- declaring nothing -- leaves Android as it was', () {
      expect(android().multiWindow, isTrue);
    });

    test('freeform: false stacks routes instead of opening a window', () {
      expect(android(freeform: false).multiWindow, isFalse);
    });

    test('freeform: true is the same as auto here', () {
      expect(android(freeform: true).multiWindow, isTrue);
    });
  });

  // The invariant. A declaration is permission to do less, never a grant.
  group('a declaration never widens', () {
    test('a phone does not gain a second window by asking for one', () {
      final DVWindowingCapability phone = DVWindowingCapability.detect(
        isDesktop: false,
        isWeb: false,
        isAndroid: false,
        isTablet: false,
        isIOS: true,
        hasNativeWindowBinding: false,
        webOpenInNewWindow: true,
        androidFreeform: true,
      );
      expect(phone.multiWindow, isFalse);
    });

    test('a desktop with no binding does not gain one either', () {
      final DVWindowingCapability desktop = DVWindowingCapability.detect(
        isDesktop: true,
        isWeb: false,
        isAndroid: false,
        isTablet: false,
        isIOS: false,
        hasNativeWindowBinding: false,
        webOpenInNewWindow: true,
      );
      expect(desktop.multiWindow, isFalse);
    });

    // The declaration is not a way around the two things that switch
    // windowing off wholesale.
    test('a kiosk lock still wins', () {
      expect(
        DVWindowingCapability.detect(
          isDesktop: false,
          isWeb: true,
          isAndroid: false,
          isTablet: false,
          isIOS: false,
          hasNativeWindowBinding: false,
          kioskLocked: true,
          webInPageViews: true,
          webOpenInNewWindow: true,
        ).multiWindow,
        isFalse,
      );
    });
  });
}
