// The bindings a platform claims, checked against the bindings it has, on the
// device rather than in a widget test.
//
// This exists because of a specific failure that nothing caught for months.
// Every Android binding was reached through `GetApplicationContext()`, a
// declaration in package:jni's `dartjni.h` with no definition behind it in
// `dartjni.c`. The capability list said clipboard, haptics, sharing and the
// kiosk all worked. `flutter analyze` was clean, the unit suite was green, the
// APK built, and the application died on a real phone with "undefined symbol:
// GetApplicationContext". It took installing on an emulator to find out.
//
// The shape of that bug is what is tested here, not the one instance of it.
// Three separate things have to agree and none of them checks the others:
//
//   1. the capability set, which is what `DV.Platform` advertises,
//   2. what `register()` actually put in the bridge on this device, and
//   3. whether calling one reaches Android and comes back.
//
// A widget test can only ever see the first. The second needs the real
// `register()` to have run against a real JNI, and the third needs a real
// system service on the other end. So this runs on the emulator, and it is
// deliberately cheap to extend: a binding added to the capability set with no
// implementation behind it fails here without anyone writing a new test.
//
// Run with: flutter test integration_test/native_bindings_test.dart -d emulator-5554
@TestOn('!browser')
library;

import 'dart:io' as io;

import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Bindings that can be called unattended without leaving something on screen
/// or taking the device somewhere the next test cannot get back from.
///
/// `share.text` raises a chooser and waits for a human. `kiosk.enforce` pins
/// the task, and a failure between it and its release would strand the
/// emulator for every test that follows -- it has its own test, which knows
/// how to get back out. Everything else here either reads a value or writes
/// one somewhere private to the application.
///
/// Names, not a count. A binding that lands later is either safe to add to
/// this set deliberately or it is not, and guessing from the name is how a
/// test suite starts opening the camera.
const Map<String, Object?> _safeToInvoke = <String, Object?>{
  'clipboard.copy': 'dartvel-probe',
  'clipboard.paste': null,
  'haptics.vibrate': null,
  'haptics.lightVibrate': null,
  'haptics.impact': null,
  'deepLinks.initial': null,
  // `key` and `text`, and both have to be non-empty: the binding returns false
  // on an empty key before it reaches JNI at all, so a probe with the wrong
  // argument names would exercise nothing and still pass.
  'homeWidgets.publish': <String, Object?>{
    'key': 'next-shift',
    'text': 'probe',
  },
};

/// What this platform says it can do.
Set<String> _claimed() {
  if (io.Platform.isAndroid) return DVAndroidBindings.implemented;
  return const <String>{};
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerPlatformBindings);

  testWidgets('registration ran at all on this device',
      (WidgetTester tester) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('the claim/reality check is per platform; Android here');
      return;
    }

    // The first thing the undefined-symbol failure broke. `register()` threw
    // before it reached a single `DVNativeBridge.register` call, so the bridge
    // was empty and every binding returned null -- which is what an
    // unsupported platform returns, so nothing downstream could tell.
    expect(DVAndroidBindings.isRegistered, isTrue,
        reason: 'DVAndroidBindings.register() did not complete on the device. '
            'Every binding will return null, and a null from this bridge is '
            'indistinguishable from a platform that has no such capability.');

    expect(DVNativeBridge.registered, isNotEmpty);
  });

  testWidgets('every binding the platform claims is actually registered',
      (WidgetTester tester) async {
    final Set<String> claimed = _claimed();
    if (claimed.isEmpty) {
      markTestSkipped('no capability set for ${io.Platform.operatingSystem}');
      return;
    }

    final Set<String> missing =
        claimed.difference(DVNativeBridge.registered.toSet());

    expect(missing, isEmpty,
        reason: 'these are advertised by the capability set and have no '
            'handler on the device, so DV.Platform promises them and the call '
            'returns null: $missing');
  });

  testWidgets('and nothing is registered that the platform does not claim',
      (WidgetTester tester) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('the claim/reality check is per platform; Android here');
      return;
    }

    // The drift that hides rather than breaks. A binding wired up but left out
    // of the capability set works when called directly and is invisible to
    // anything that asks what the platform supports first -- so a feature
    // guarded by `isRegistered` stays switched off on a device that could run
    // it, and no test fails.
    final Set<String> undeclared =
        DVNativeBridge.registered.toSet().difference(_claimed());

    expect(undeclared, isEmpty,
        reason: 'registered on the device but absent from the capability set, '
            'so DV.Platform will not advertise a binding that works: '
            '$undeclared');
  });

  testWidgets('the safe bindings reach Android and come back',
      (WidgetTester tester) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('JNI is Android\'s');
      return;
    }

    // Registration proves a closure is in a map. This proves the closure runs
    // all the way into a system service and returns -- which is the half the
    // undefined-symbol failure broke, and the half a mock cannot stand in for.
    final Map<String, Object> failures = <String, Object>{};
    for (final MapEntry<String, Object?> probe in _safeToInvoke.entries) {
      if (!DVNativeBridge.isRegistered(probe.key)) continue;
      try {
        await DVNativeBridge.invoke<Object?>(probe.key, probe.value);
      } catch (error) {
        failures[probe.key] = error;
      }
    }

    expect(failures, isEmpty,
        reason: 'these bindings are registered and threw when called on a '
            'real device. A JNI lookup failure looks exactly like this and '
            'looks like nothing at all in a widget test: $failures');
  });

  testWidgets('a clipboard round trip carries the value through JNI',
      (WidgetTester tester) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('JNI is Android\'s');
      return;
    }
    if (!DVNativeBridge.isRegistered('clipboard.copy')) {
      fail('clipboard.copy is the oldest Android binding there is; if it is '
          'gone, the registration switch has stopped reaching Android');
    }

    // The one assertion here that a broken binding cannot pass by staying
    // quiet. Everything above is satisfied by a handler that returns null
    // without doing anything; this needs the value to survive a trip into
    // ClipboardManager and back out of it.
    //
    // Multi-byte on purpose. A JNI string conversion that truncates at the
    // first non-ASCII byte round-trips plain text perfectly.
    const String written = 'dartvel clipboard — ünïcode ✓';
    await DVNativeBridge.invoke<void>('clipboard.copy', written);

    final String? read =
        await DVNativeBridge.invoke<String>('clipboard.paste', null);

    expect(read, written,
        reason: 'the value did not survive the trip through ClipboardManager');
  });
}
