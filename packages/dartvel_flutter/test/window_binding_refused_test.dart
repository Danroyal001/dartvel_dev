// DV-WINDOW-006: the one `error` in the window registry.
//
// The specification separates the platform saying no (DV-WINDOW-004, an OS
// window limit, a denied task) from the binding being missing or refusing
// (DV-WINDOW-006): the first is a capability limit the fallback was built
// for, the second is a platform integration defect that must not be dressed
// up as graceful degradation. Both were reported as 004, so a broken binding
// looked like a full desktop.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const DVRouteTarget orders = DVRouteTarget('/orders');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DVWindowManager.reset();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(multiWindow: true);
  });
  tearDown(() {
    DVNativeBridge.unregister('window.open');
    DVWindowManager.reset();
  });

  test('a binding that is claimed but not registered is a defect, not a refusal', () async {
    final DVWindow win = await DV.Platform.Window.open(orders);

    expect(win.degradation, DVWindowDegradation.bindingRefused);
    expect(win.degradation.code, 'DV-WINDOW-006');
    expect(win.degradation.level, 'error');
    // Still degrades: the route is presented.
    expect(win.presentation, DVWindowPresentation.page);
  });

  test('a binding that throws is the binding refusing', () async {
    DVNativeBridge.register('window.open', (Object? _) => throw StateError('ffi symbol missing'));

    final DVWindow win = await DV.Platform.Window.open(orders);

    expect(win.degradation, DVWindowDegradation.bindingRefused);
  });

  test('a binding that answers nothing is the platform refusing', () async {
    DVNativeBridge.register('window.open', (Object? _) => null);

    final DVWindow win = await DV.Platform.Window.open(orders);

    expect(win.degradation, DVWindowDegradation.platformRefused);
    expect(win.degradation.code, 'DV-WINDOW-004');
    expect(win.degradation.level, 'warning');
  });

  test('the bridge says whether a binding is registered', () {
    expect(DVNativeBridge.isRegistered('window.open'), isFalse);
    DVNativeBridge.register('window.open', (Object? _) => 'w');
    expect(DVNativeBridge.isRegistered('window.open'), isTrue);
  });
}
