// Kiosk windows: a regular window that owns a display and carries a policy
// it cannot be argued out of.
//
// One application serves a customer-facing display and a staff terminal at
// once: the staff window is ordinary, the customer window is kiosk. What
// the tests hold to, from the spec's rules: it owns its display, and a
// window asking for that display is placed elsewhere (DV-WINDOW-011); it
// is pinned, so a close is refused (DV-WINDOW-012) until kiosk.exit
// satisfies the declared method; its policy is a declared one; with its
// display gone it presents in place, fullscreen (DV-WINDOW-010); and it
// counts as a principal window, like a regular one.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> display(String id, String name, {bool primary = false, double left = 0}) => <String, Object?>{
      'id': id,
      'name': name,
      'devicePixelRatio': 1.0,
      'width': 1920.0,
      'height': 1080.0,
      'refreshRate': 60.0,
      'isPrimary': primary,
      'left': left,
      'top': 0.0,
    };

DVKioskPolicy customerDisplay() => DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'display',
        'home': '/customer-display',
        'routes': <String, Object?>{'allow': <String>['/customer-display/**']},
        'session': <String, Object?>{'idleTimeout': '60s', 'onIdle': 'reset'},
        'exit': <String, Object?>{'method': 'adminAuth'},
      },
    });

void main() {
  late List<Map<String, Object?>> displays;
  late List<Map<Object?, Object?>> opened;

  setUp(() {
    DVWindowManager.reset();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true, sameEngine: true, tearOut: true, displayKiosk: true,
    );
    displays = <Map<String, Object?>>[display('1', 'Staff', primary: true), display('2', 'Customer', left: 1920)];
    opened = <Map<Object?, Object?>>[];
    int n = 0;
    DVNativeBridge.register('window.displays', (Object? _) => displays);
    DVNativeBridge.register('window.open', (Object? a) {
      opened.add(a! as Map<Object?, Object?>);
      return 'win-${++n}';
    });
    DVNativeBridge.register('window.close', (Object? a) => true);
  });
  tearDown(() {
    DVWindowManager.reset();
    for (final String n in <String>['window.displays', 'window.open', 'window.close']) {
      DVNativeBridge.unregister(n);
    }
  });

  Future<DVWindow> openKiosk() => DV.Platform.Window.open(
        const DVRouteTarget('/customer-display'),
        options: DVWindowOptions(
          kind: DVWindowKind.kiosk,
          display: DVDisplayHint.byName('Customer'),
          kiosk: DVWindowKiosk(policy: customerDisplay()),
        ),
      );

  test('a kiosk window opens on its display, with its policy running', () async {
    final DVWindow customer = await openKiosk();
    expect(customer.kind, DVWindowKind.kiosk);
    expect(customer.nativeId, isNotNull);
    expect(opened.single['displayId'], '2');
    expect(opened.single['kind'], 'kiosk');
    expect(customer.kiosk, isNotNull);
    expect(customer.kiosk!.state.value, DVKioskState.active);
    expect(customer.kiosk!.enforcement.supported, isTrue);
    expect(customer.kiosk!.policy.home, '/customer-display');
    expect(customer.kind.countsAsPrincipal, isTrue, reason: 'regular or kiosk, the spec says');
  });

  test('it owns its display: another window asking for it is placed elsewhere', () async {
    await openKiosk();
    final DVWindow staff = await DV.Platform.Window.open(
      const DVRouteTarget('/staff'),
      options: DVWindowOptions(display: DVDisplayHint.byName('Customer')),
    );
    expect(opened.last['displayId'], isNot('2'));
    expect(staff.codes, contains('DV-WINDOW-011'));
    expect(DV.Platform.Window.kioskOwnerOf('2')?.route.path, '/customer-display');
  });

  test('it is pinned: close is refused until kiosk.exit satisfies the policy', () async {
    final DVWindow customer = await openKiosk();
    await customer.close();
    expect(DV.Platform.Window.all.value, contains(customer), reason: 'a user close is refused');
    expect(customer.codes, contains('DV-WINDOW-012'));

    final bool left = await customer.kiosk!.exit(const DVKioskExitRequest.adminAuth('staff-token'));
    expect(left, isTrue);
    expect(DV.Platform.Window.all.value, isNot(contains(customer)), reason: 'exit is how it closes');
    expect(DV.Platform.Window.kioskOwnerOf('2'), isNull);
  });

  test('the wrong exit method does not open it', () async {
    final DVWindow customer = await openKiosk();
    expect(await customer.kiosk!.exit(const DVKioskExitRequest.pin('1234')), isFalse);
    expect(DV.Platform.Window.all.value, contains(customer));
  });

  test('with its display gone it presents in place, fullscreen, and says so', () async {
    displays = <Map<String, Object?>>[display('1', 'Staff', primary: true)];
    final DVWindow customer = await openKiosk();
    expect(customer.codes, contains('DV-WINDOW-010'));
    expect(customer.degradation, DVWindowDegradation.displayUnavailable);
    expect(customer.kiosk, isNotNull, reason: 'the policy still holds where it is shown');
  });

  test('its session is its own: a reset goes through its runtime', () async {
    final DVWindow customer = await openKiosk();
    final List<DVKioskState> seen = <DVKioskState>[];
    customer.kiosk!.state.addListener(() => seen.add(customer.kiosk!.state.value));
    await customer.kiosk!.resetSession();
    expect(seen, <DVKioskState>[DVKioskState.resetting, DVKioskState.active]);
    expect(customer.kiosk!.lastReset?.reason, DVKioskResetReason.explicit);
  });

  test('without displayKiosk in the capability, a kiosk window is in place', () async {
    DVWindowManager.capabilityOverride = const DVWindowingCapability(multiWindow: true, sameEngine: true, tearOut: true);
    final DVWindow customer = await openKiosk();
    expect(customer.codes, contains('DV-WINDOW-010'));
    expect(customer.kiosk, isNotNull);
  });
}
