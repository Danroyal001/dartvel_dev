// The window contract: open() always presents the route, and always says how.
//
// The load-bearing claim is that application code never branches on
// capability — so these tests run the same calls with windowing available and
// unavailable, and assert the caller gets a usable window either way.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const orders = DVRouteTarget('/orders');
const customers = DVRouteTarget('/customers');

void main() {
  setUp(DVWindowManager.reset);
  tearDown(() {
    DVWindowManager.reset();
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
  });

  DVWindowManager manager() => DV.Platform.Window;

  void grantWindows() {
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true,
      sameEngine: true,
      tearOut: true,
    );
    DVNativeBridge.register('window.open', (Object? args) => 'win-1');
    DVNativeBridge.register('window.close', (Object? args) => true);
  }

  group('capability', () {
    test('desktop claims nothing until the binding exists', () {
      // Flutter desktop windowing is experimental and behind a flag, so
      // claiming the capability first would be a promise the next call breaks.
      final without = DVWindowingCapability.detect(
        isDesktop: true, isWeb: false, isAndroid: false,
        isTablet: false, isIOS: false, hasNativeWindowBinding: false,
      );
      expect(without.multiWindow, isFalse);

      final with_ = DVWindowingCapability.detect(
        isDesktop: true, isWeb: false, isAndroid: false,
        isTablet: false, isIOS: false, hasNativeWindowBinding: true,
      );
      expect(with_.multiWindow, isTrue);
      expect(with_.sameEngine, isTrue);
    });

    test('web has windows but no drag tear-out', () {
      final web = DVWindowingCapability.detect(
        isDesktop: false, isWeb: true, isAndroid: false,
        isTablet: false, isIOS: false, hasNativeWindowBinding: false,
      );
      expect(web.multiWindow, isTrue);
      expect(web.tearOut, isFalse,
          reason: 'a drag ending on the desktop loses gesture attribution');
      expect(web.inPageViews, isTrue);
    });

    test('an iPad has scenes; an iPhone does not', () {
      DVWindowingCapability ios({required bool tablet}) =>
          DVWindowingCapability.detect(
            isDesktop: false, isWeb: false, isAndroid: false,
            isTablet: tablet, isIOS: true, hasNativeWindowBinding: false,
          );
      expect(ios(tablet: true).multiWindow, isTrue);
      expect(ios(tablet: false).multiWindow, isFalse);
    });

    test('kiosk and disabled configuration report no capability', () {
      for (final cap in <DVWindowingCapability>[
        DVWindowingCapability.detect(
          isDesktop: true, isWeb: false, isAndroid: false, isTablet: false,
          isIOS: false, hasNativeWindowBinding: true, kioskLocked: true,
        ),
        DVWindowingCapability.detect(
          isDesktop: true, isWeb: false, isAndroid: false, isTablet: false,
          isIOS: false, hasNativeWindowBinding: true, enabledByConfig: false,
        ),
      ]) {
        expect(cap.multiWindow, isFalse);
        expect(cap.tearOut, isFalse);
      }
    });
  });

  group('open never fails', () {
    test('with no capability the route is still presented', () async {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();

      final win = await manager().open(orders);

      expect(win.isVirtual, isTrue);
      expect(win.presentation, DVWindowPresentation.page);
      expect(win.degradation, DVWindowDegradation.capabilityUnsupported);
      expect(win.route, orders);
    });

    test('a kind that cannot be a window becomes the nearest thing', () async {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();

      for (final entry in <DVWindowKind, DVWindowPresentation>{
        DVWindowKind.regular: DVWindowPresentation.page,
        DVWindowKind.dialog: DVWindowPresentation.dialog,
        DVWindowKind.popup: DVWindowPresentation.overlay,
        DVWindowKind.tooltip: DVWindowPresentation.overlay,
        DVWindowKind.satellite: DVWindowPresentation.overlay,
      }.entries) {
        DVWindowManager.reset();
        DVWindowManager.capabilityOverride = const DVWindowingCapability();
        final win = await manager()
            .open(orders, options: DVWindowOptions(kind: entry.key));
        expect(win.presentation, entry.value, reason: entry.key.name);
      }
    });

    test('a real window is created when the platform can', () async {
      grantWindows();

      final win = await manager().open(orders);

      expect(win.isVirtual, isFalse);
      expect(win.presentation, DVWindowPresentation.window);
      expect(win.degradation, DVWindowDegradation.none);
      expect(win.nativeId, 'win-1');
    });

    test('a refusing platform degrades rather than throwing', () async {
      DVWindowManager.capabilityOverride =
          const DVWindowingCapability(multiWindow: true);
      // A throw is the binding breaking, not the OS declining: the OS's no
      // arrives as a null answer, tested below. It used to be filed under
      // platformRefused, which dressed a broken binding up as a full desktop.
      DVNativeBridge.register('window.open', (Object? args) {
        throw StateError('ffi symbol missing');
      });

      final win = await manager().open(orders);

      expect(win.degradation, DVWindowDegradation.bindingRefused);
      expect(win.presentation, DVWindowPresentation.page);
    });

    test('a binding returning nothing is a refusal, not a window', () async {
      DVWindowManager.capabilityOverride =
          const DVWindowingCapability(multiWindow: true);
      DVNativeBridge.register('window.open', (Object? args) => null);

      final win = await manager().open(orders);

      expect(win.degradation, DVWindowDegradation.platformRefused);
      expect(win.isVirtual, isTrue);
    });
  });

  group('diagnostics', () {
    test('every degradation carries a distinct stable code', () {
      final codes = <String>{};
      for (final d in DVWindowDegradation.values) {
        if (d == DVWindowDegradation.none) {
          expect(d.code, isNull);
          continue;
        }
        expect(d.code, matches(RegExp(r'^DV-WINDOW-\d{3}$')), reason: d.name);
        expect(codes.add(d.code!), isTrue, reason: '${d.name} reuses a code');
        expect(d.reason, isNotEmpty);
      }
    });

    test('levels are calibrated to whether a developer can act', () {
      // A phone has no windows and the fallback is intended, so warning on
      // every call would train people to ignore the channel.
      expect(DVWindowDegradation.capabilityUnsupported.level, 'debug');
      expect(DVWindowDegradation.gestureRequired.level, 'warning');
      expect(DVWindowDegradation.platformRefused.level, 'warning');
      expect(DVWindowDegradation.kioskLocked.level, 'info');
      expect(DVWindowDegradation.disabledByConfig.level, 'info');
    });
  });

  group('reporting cannot break the call', () {
    test('open succeeds with no observability configured', () async {
      // Found by these tests: DV.log throws when no analytics provider is
      // registered, so the report of a degradation was failing the very call
      // whose contract is that it never fails. A contract that holds only
      // where telemetry happens to be wired is not a contract.
      DVWindowManager.capabilityOverride = const DVWindowingCapability();

      final win = await manager().open(orders);

      expect(win.degradation, DVWindowDegradation.capabilityUnsupported,
          reason: 'the degradation stays readable even when unreportable');
      expect(win.presentation, DVWindowPresentation.page);
    });

    test('a virtual setSize does not throw either', () async {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();
      final win = await manager().open(orders);

      await expectLater(win.setSize(const Size(800, 600)), completes);
    });
  });

  group('the collection', () {
    test('lists virtual windows alongside real ones', () async {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();

      await manager().open(orders);
      await manager().open(customers);

      expect(manager().all.value.map((w) => w.route.path),
          <String>['/orders', '/customers']);
    });

    test('opening a route already shown focuses it rather than duplicating',
        () async {
      grantWindows();

      final first = await manager().open(orders);
      final second = await manager().open(orders);

      expect(identical(first, second), isTrue);
      expect(manager().all.value.length, 1);
    });

    test('duplicate: true is how a second window on one route is asked for',
        () async {
      grantWindows();

      await manager().open(orders);
      await manager()
          .open(orders, options: const DVWindowOptions(duplicate: true));

      expect(manager().all.value.length, 2);
    });

    test('close removes the window, virtual or not', () async {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();
      final win = await manager().open(orders);

      await win.close();

      expect(manager().all.value, isEmpty);
      expect(win.lifecycle.value, DVWindowLifecycle.closed);
    });
  });

  group('lifecycle', () {
    test('is observed, and reaches ready once opened', () async {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();
      final win = await manager().open(orders);

      expect(win.lifecycle, isA<ValueListenable<DVWindowLifecycle>>());
      expect(win.lifecycle.value, DVWindowLifecycle.ready);
    });
  });
}
