// What a display-scope kiosk reset is allowed to clear.
//
// The specification's table is the whole point of the scope distinction: in
// device scope a reset empties the shared store, and in display scope it may
// touch only the keys under `kiosk.<name>.*`. The customer display timing out
// must not empty the store the cashier's window is working out of.
//
// Neither happened, because the kiosk window's runtime was built with no
// clear callback at all, so the entries in clearOnReset reached a function
// with an empty body and the reset cleared nothing on either side of the
// line.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _display(String id, String name,
        {bool primary = false, double left = 0}) =>
    <String, Object?>{
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

DVKioskPolicy _customerDisplay() => DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'display',
        'home': '/customer-display',
        'session': <String, Object?>{
          'clearOnReset': <String>['sharedStore'],
        },
        'exit': <String, Object?>{'method': 'adminAuth'},
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DVWindowSharedStore store;

  setUp(() {
    DVWindowManager.reset();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true,
      sameEngine: true,
      tearOut: true,
      displayKiosk: true,
    );
    store = DVWindowSharedStore();
    DVWindowManager.useSharedStore(store);
    DVNativeBridge.register(
      'window.displays',
      (Object? _) => <Map<String, Object?>>[
        _display('1', 'Staff', primary: true),
        _display('2', 'Customer', left: 1920),
      ],
    );
    DVNativeBridge.register('window.open', (Object? _) => 'win-1');
    DVNativeBridge.register('window.close', (Object? _) => true);
  });

  tearDown(() async {
    DVWindowManager.reset();
    for (final String name in <String>[
      'window.displays',
      'window.open',
      'window.close',
    ]) {
      DVNativeBridge.unregister(name);
    }
    await store.dispose();
  });

  Future<DVWindow> openKiosk({String? name}) => DV.Platform.Window.open(
        const DVRouteTarget('/customer-display'),
        options: DVWindowOptions(
          kind: DVWindowKind.kiosk,
          display: DVDisplayHint.byName('Customer'),
          kiosk: DVWindowKiosk(policy: _customerDisplay(), name: name),
        ),
      );

  test('a named kiosk window clears its own keys and nobody else\'s',
      () async {
    final DVWindow customer = await openKiosk(name: 'customer');
    // Written after the window opens: entering kiosk is itself a reset, so a
    // value set beforehand is already gone and the assertion would hold
    // against a reset that does nothing.
    await store.set('kiosk.customer.cart', const DVJsonString('12.40'));
    await store.set('till.drawer', const DVJsonString('open'));

    await customer.kiosk!.resetSession();

    expect(await store.get('kiosk.customer.cart'), isNull);
    expect(await store.get('till.drawer'), isNotNull,
        reason: 'the staff window is still working out of that key');
  });

  test('another kiosk window\'s keys are not this one\'s to clear', () async {
    final DVWindow customer = await openKiosk(name: 'customer');
    await store.set('kiosk.wayfinding.step', const DVJsonString('3'));

    await customer.kiosk!.resetSession();

    expect(await store.get('kiosk.wayfinding.step'), isNotNull);
  });

  test('an unnamed kiosk window clears nothing from the store', () async {
    // With no name there is no prefix, and the only alternative to clearing
    // nothing is clearing everything -- which is the one thing display scope
    // exists to prevent.
    final DVWindow customer = await openKiosk();
    await store.set('kiosk.customer.cart', const DVJsonString('12.40'));

    await customer.kiosk!.resetSession();

    expect(await store.get('kiosk.customer.cart'), isNotNull);
  });
}
