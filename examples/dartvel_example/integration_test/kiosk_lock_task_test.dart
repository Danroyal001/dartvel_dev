// Kiosk enforcement, on the device it is meant to run on.
//
// This is the test that was impossible until the Activity became reachable.
// Lock task mode belongs to an Activity, and the application Context that
// package:jni hands back is not one — so kiosk on Android was recorded as
// blocked and asserted nowhere. A widget test cannot tell a kiosk that holds
// from one that returns a map saying it did.
//
// What is checked here is what the platform did, not what Dartvel said. The
// enforcement result carries `lockTask`, and Android's own ActivityManager is
// the second opinion: the emulator step reads `dumpsys activity` afterwards,
// so a Dart-side bool that lied would still be caught.
//
// Run with: flutter test integration_test/kiosk_lock_task_test.dart -d emulator-5554
@TestOn('!browser')
library;

import 'dart:io' as io;

import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // The bindings the running platform has. On an emulator this registers
    // the Android ones, which is what makes kiosk.enforce answerable -- and
    // which no generated application did until the switch that dispatches
    // on the platform gained an android case.
    registerPlatformBindings();
  });

  testWidgets('the platform holds the kiosk, and says which parts',
      (WidgetTester tester) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('lock task mode is Android\'s');
      return;
    }

    final DVKioskEnforced held = await DVKiosk.enforce(_policy());
    addTearDown(DVKiosk.release);

    // The binding answered rather than the "no kiosk binding on this
    // platform" fallback, which is what an unregistered Android binding
    // would have produced and what this test existed to catch.
    expect(held.unenforced.values,
        isNot(contains('no kiosk binding on this platform')));

    // Lock task either took or said why. Both are results; silence is not.
    expect(held.notificationsSuppressed, isTrue,
        reason: 'lock task closes the notification shade; if it is not held, '
            'this is false and the reason is in the enforcement result');
  });

  testWidgets('releasing it lets go', (WidgetTester tester) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('lock task mode is Android\'s');
      return;
    }

    await DVKiosk.enforce(_policy());
    await DVKiosk.release();

    // Enforcing again after a release has to work. A kiosk that could be
    // entered once per process would be one that never comes back from a
    // maintenance window.
    final DVKioskEnforced again = await DVKiosk.enforce(_policy());
    addTearDown(DVKiosk.release);

    expect(again.notificationsSuppressed, isTrue);
  });
}

/// A device-scope kiosk, from the declaration reader rather than by hand.
///
/// The policy has twenty required fields and a test that listed them would
/// be asserting its own copy of the defaults rather than the ones an
/// application gets.
DVKioskPolicy _policy() => DVKioskPolicy.parse(const <String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'fullscreen': true,
      },
    });
