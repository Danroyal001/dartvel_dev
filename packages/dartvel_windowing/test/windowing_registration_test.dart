// Registering the binding is what makes DV.Platform.Window.open present a real
// window: DVWindowingCapability.detect gates multiWindow on the binding
// existing, deliberately, so that claiming the capability and being unable to
// honour it is not representable.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const projector = DVRouteTarget('/projector');
const operator_ = DVRouteTarget('/operator');

void main() {
  setUp(() {
    DVWindowManager.reset();
    DVWindowHost.debugResetBindings();
  });
  tearDown(() {
    DVWindowManager.reset();
    DVWindowHost.debugResetBindings();
  });

  test('registering flips the desktop capability', () {
    expect(
      DVWindowingCapability.detect(
        isDesktop: true, isWeb: false, isAndroid: false,
        isTablet: false, isIOS: false,
        hasNativeWindowBinding: DVNativeBridge.isRegistered('window.open'),
      ).multiWindow,
      isFalse,
    );

    DVWindowHost.debugRegisterBindings();

    expect(
      DVWindowingCapability.detect(
        isDesktop: true, isWeb: false, isAndroid: false,
        isTablet: false, isIOS: false,
        hasNativeWindowBinding: DVNativeBridge.isRegistered('window.open'),
      ).multiWindow,
      isTrue,
    );
  });

  test('opening a route yields a window rather than a degraded page', () async {
    DVWindowHost.debugRegisterBindings();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true, sameEngine: true, tearOut: true,
    );

    final window = await DV.Platform.Window.open(projector);

    expect(window.presentation, DVWindowPresentation.window);
    expect(window.degradation, DVWindowDegradation.none);
    expect(window.isVirtual, isFalse);
  });

  test('carries the requested size and title through to the surface', () async {
    DVWindowHost.debugRegisterBindings();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true, sameEngine: true, tearOut: true,
    );

    final window = await DV.Platform.Window.open(
      projector,
      options: const DVWindowOptions(
        size: Size(1920, 1080),
        title: 'Projector Output',
      ),
    );

    // The factory needs these and DVWindow does not carry them, so the binding
    // that received them has to keep them reachable by the id it returned.
    final request = DVWindowHost.debugRequestFor(window.nativeId);
    expect(request, isNotNull);
    expect(request!.size, const Size(1920, 1080));
    expect(request.title, 'Projector Output');
  });

  test('gives each window its own id', () async {
    DVWindowHost.debugRegisterBindings();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true, sameEngine: true, tearOut: true,
    );

    final a = await DV.Platform.Window.open(operator_);
    final b = await DV.Platform.Window.open(projector);

    expect(a.nativeId, isNotNull);
    expect(b.nativeId, isNotNull);
    expect(a.nativeId, isNot(b.nativeId));
  });

  test('closing a window releases what was held for it', () async {
    DVWindowHost.debugRegisterBindings();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true, sameEngine: true, tearOut: true,
    );
    final window = await DV.Platform.Window.open(projector);
    final id = window.nativeId;

    await window.close();

    expect(DVWindowHost.debugRequestFor(id), isNull,
        reason: 'a long service opens and closes many windows');
  });
}
