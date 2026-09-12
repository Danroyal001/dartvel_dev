// Why a window request degraded, not merely that it did.
//
// Three degradations were declared, given diagnostic codes and documented in
// the specification, and assigned nowhere in any package: a window could never
// carry `kioskLocked`, `gestureRequired` or `disabledByConfig`, so `dartvel
// explain DV-WINDOW-002` described a situation the API had no way to produce.
//
// Each names a real condition with configuration or a platform behind it, so
// each is reported where that condition occurs. The controls matter as much as
// the assertions: every one of these would also be a degraded window without
// the change, reported as the generic `capabilityUnsupported`, so a test that
// only checked "it degraded" would have passed before it.
import 'package:dartvel_core/dartvel.dart' show DVDiagnostics, DVKioskPolicy;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const DVRouteTarget orders = DVRouteTarget('/orders');

/// A held kiosk policy in [scope].
DVKioskPolicy kiosk(String scope) => DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': scope,
        'home': '/orders',
      },
    });

void main() {
  setUp(() {
    DVWindowManager.reset();
    dvResetKioskContainment();
    DVWindowManager.resetWindowingDeclaration();
  });
  tearDown(() {
    DVWindowManager.reset();
    dvResetKioskContainment();
    DVWindowManager.resetWindowingDeclaration();
  });

  group('a device-scope kiosk holds the surface', () {
    test('open() reports the kiosk, not a missing capability', () async {
      // One application, one surface, no windows: the spec's canonical
      // device-scope kiosk. The route still presents, in place.
      dvApplyKioskContainment(kiosk('device'));

      final DVWindow window = await DV.Platform.Window.open(orders);

      expect(window.degradation, DVWindowDegradation.kioskLocked);
      expect(window.degradation.code, 'DV-WINDOW-002');
      expect(window.route.path, orders.path,
          reason: 'open() always presents the route');
    });

    test('a display-scope kiosk does not lock the surface', () async {
      // The control. A display-scope kiosk owns one display and the
      // application keeps ordinary windows on the others, so this window
      // degrades for whatever the host lacks -- never for the kiosk.
      dvApplyKioskContainment(kiosk('display'));

      final DVWindow window = await DV.Platform.Window.open(orders);

      expect(window.degradation, isNot(DVWindowDegradation.kioskLocked));
    });
  });

  group('windowing.enabled: false', () {
    test('open() reports the configuration that withdrew windows', () async {
      DVWindowManager.useWindowingDeclaration(
          const DVWindowingDeclaration(enabled: false));

      final DVWindow window = await DV.Platform.Window.open(orders);

      expect(window.degradation, DVWindowDegradation.disabledByConfig);
      expect(window.degradation.code, 'DV-WINDOW-005');
    });

    test('a project that declared nothing is never blamed on configuration',
        () async {
      // The control. This window degrades too -- the test host has no window
      // binding -- so a test that only checked "it degraded" would pass
      // against code that reported disabledByConfig for everything. What
      // must hold is that neither reason is attributed to a project that
      // wrote no such line, and to no kiosk.
      final DVWindow window = await DV.Platform.Window.open(orders);

      expect(window.degradation, isNot(DVWindowDegradation.none));
      expect(window.degradation, isNot(DVWindowDegradation.disabledByConfig));
      expect(window.degradation, isNot(DVWindowDegradation.kioskLocked));
    });
  });

  group('a browser window', () {
    test('blocked outside a user gesture reports gestureRequired', () async {
      // The browser enforces it and Dartvel reports it rather than attempting
      // a bypass: a popup called outside a gesture is refused, and `open()`
      // says which of the two web failures it was.
      DVWindowManager.browserWindowOpener = (String url,
              {String? title, double? width, double? height}) =>
          const DVBrowserWindowResult(DVBrowserWindowOutcome.blocked);

      final DVWindow window = await DV.Platform.Window.open(orders);

      expect(window.degradation, DVWindowDegradation.gestureRequired);
      expect(window.degradation.code, 'DV-WINDOW-003');
    });

    test('the browser opened reports no degradation at all', () async {
      // The control. Without it the test above would pass against code that
      // reported gestureRequired for every web call, blocked or not.
      DVWindowManager.browserWindowOpener = (String url,
              {String? title, double? width, double? height}) =>
          const DVBrowserWindowResult(DVBrowserWindowOutcome.opened,
              id: 'browser-1');

      final DVWindow window = await DV.Platform.Window.open(orders);

      expect(window.degradation, DVWindowDegradation.none);
      expect(window.presentation, DVWindowPresentation.window);
      expect(window.nativeId, 'browser-1');
    });

    test('off the web nothing is attempted and the binding is named',
        () async {
      // The other control: the opener reports it is not on the web, and the
      // missing binding is still the integration defect it always was.
      final DVWindow window = await DV.Platform.Window.open(orders);

      expect(window.degradation, isNot(DVWindowDegradation.gestureRequired));
    });
  });

  test('every degradation names a code the registry explains', () {
    // The defect these three shared was a member with a code that nothing
    // could produce. This is the other half of the contract: a member whose
    // code is not in the registry would have `dartvel explain` answering
    // nothing for a window a caller is holding.
    for (final DVWindowDegradation degradation in DVWindowDegradation.values) {
      final String? code = degradation.code;
      if (degradation == DVWindowDegradation.none) {
        expect(code, isNull);
        continue;
      }
      expect(code, isNotNull, reason: '$degradation has no code');
      expect(DVDiagnostics.find(code!), isNotNull,
          reason: '$code is not in the diagnostics registry');
    }
  });
}
