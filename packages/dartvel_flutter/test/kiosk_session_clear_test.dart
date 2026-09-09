// What a kiosk reset actually clears in a real application.
//
// The runtime takes a `clear` callback and calls it with what the policy
// named. Neither production construction supplied one -- not the device kiosk
// the generated runtime installs, nor the kiosk window -- so the default ran,
// which clears nothing. Every part of the chain looked right: the key parsed,
// doctor validated it, the reset fired, the reason was correct, and the
// entries in clearOnReset reached a function whose body is empty.
//
// The failure is invisible from inside the application and obvious from in
// front of it. A customer signs in at a self-service screen, walks away, the
// kiosk times out, shows the attract route -- and the next person taps
// through to an account that is still signed in.
//
// Three of the five are the framework's own to clear and are covered here.
// signals and forms are the application's state and stay the application's
// callback; doctor says so rather than this pretending otherwise.
import 'package:dartvel_core/dartvel.dart'
    show DVKioskClearable, DVKioskPolicy, DVMemoryCacheAdapter;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVKioskPolicy _policy(List<String> clear) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': '/welcome',
        'session': <String, Object?>{'clearOnReset': clear},
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DVWindowSharedStore store;

  setUp(() {
    store = DVWindowSharedStore();
    DVWindowManager.useSharedStore(store);
    DV.Cache.configure(DVMemoryCacheAdapter());
    DV.Auth.configure(DVLocalAuthProvider());
  });

  tearDown(() async {
    await DVPlatform.uninstallKioskPolicy();
    await store.dispose();
  });

  // Every session value is written after the kiosk is installed. Entering
  // kiosk is itself a reset, so anything set beforehand is already gone and
  // the assertion would pass against a reset that does nothing at all.

  test('a reset empties the client cache the policy named', () async {
    final DVDeviceKiosk kiosk =
        (await DVPlatform.installKioskPolicy(_policy(<String>['clientCache'])))!;
    await DV.Cache.set('order-draft', 'two flat whites');
    expect(await DV.Cache.get<String>('order-draft'), 'two flat whites');

    await kiosk.resetSession();

    expect(await DV.Cache.get<String>('order-draft'), isNull);
  });

  test('a reset signs the last person out', () async {
    final DVDeviceKiosk kiosk =
        (await DVPlatform.installKioskPolicy(_policy(<String>['auth'])))!;
    await DV.Auth.signIn();
    expect(DV.Auth.currentUser, isNotNull);

    await kiosk.resetSession();

    expect(DV.Auth.currentUser, isNull);
  });

  test('a reset empties the shared store', () async {
    final DVDeviceKiosk kiosk = (await DVPlatform.installKioskPolicy(
        _policy(<String>['sharedStore'])))!;
    await store.set('cart.total', const DVJsonString('12.40'));
    expect(await store.get('cart.total'), isNotNull);

    await kiosk.resetSession();

    expect(await store.get('cart.total'), isNull);
  });

  test('and leaves the window layout alone', () async {
    // The reserved prefixes are the framework's own window and workspace
    // state, not anybody's session. Emptying them because a customer walked
    // away resets the tab order of a staff window on another display.
    final DVDeviceKiosk kiosk = (await DVPlatform.installKioskPolicy(
        _policy(<String>['sharedStore'])))!;
    await store.setReserved('workspace.tab.order', const DVJsonString('2'));

    await kiosk.resetSession();

    expect(await store.getReserved('workspace.tab.order'), isNotNull);
  });

  test('only what the policy lists is cleared', () async {
    // A kiosk that lists the cache and clears the session as well would sign
    // an operator out of an informational display that was never meant to
    // touch auth.
    final DVDeviceKiosk kiosk =
        (await DVPlatform.installKioskPolicy(_policy(<String>['clientCache'])))!;
    await DV.Auth.signIn();
    await DV.Cache.set('order-draft', 'two flat whites');

    await kiosk.resetSession();

    expect(await DV.Cache.get<String>('order-draft'), isNull);
    expect(DV.Auth.currentUser, isNotNull);
  });

  test('an application clear replaces the default rather than joining it',
      () async {
    // The application knows its own signals and forms. Where it supplies a
    // callback, that is the one that runs: a framework default running as
    // well would clear things the application had decided to keep.
    final List<Set<DVKioskClearable>> asked = <Set<DVKioskClearable>>[];
    await DV.Cache.set('order-draft', 'two flat whites');
    final DVDeviceKiosk kiosk = (await DVPlatform.installKioskPolicy(
      _policy(<String>['clientCache']),
      clear: (Set<DVKioskClearable> what) async => asked.add(what),
    ))!;
    // Entering kiosk resets the session too, and that reset is its own
    // subject in kiosk_reset_reason_test. What is under test here is which
    // callback runs.
    asked.clear();

    await kiosk.resetSession();

    expect(asked.single, <DVKioskClearable>{DVKioskClearable.clientCache});
    expect(await DV.Cache.get<String>('order-draft'), 'two flat whites');
  });
}
