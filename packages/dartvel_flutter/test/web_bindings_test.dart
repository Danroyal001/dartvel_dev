// Web platform bindings, as a claim rather than as behaviour.
//
// This suite runs on the VM, where the stub resolves, so nothing here can
// call a web API. What it can check is the claim: which of the declared
// binding names the browser covers, and — for every name it does not — a
// written reason the browser cannot.
//
// That pairing is the point. `DVNativeBridge.invoke` answers null for a name
// nothing registered, so "the browser has no such API" and "nobody got round
// to it" reach an application as the same silence. Forcing every declared
// name into one of the two sets means the second case cannot survive: a name
// added to `dvNativeBindingNames` fails this suite until somebody decides
// what the web does with it.
//
// The real behaviour lives in web_bindings_browser_test.dart, which runs in a
// browser and calls the implementations.
import 'package:dartvel_flutter/src/platform/binding_names.dart';
import 'package:dartvel_flutter/src/platform/web/web_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('every declared name has a web answer', () {
    test('a name is either covered or carries a reason it cannot be', () {
      final Set<String> undecided = dvNativeBindingNames
          .difference(dvWebImplementedBindings)
          .difference(dvWebUnavailableBindings.keys.toSet());

      expect(undecided, isEmpty,
          reason: 'these binding names say nothing about the web. Either the '
              'browser can do it — add it to dvWebImplementedBindings and '
              'bind it — or it cannot, and dvWebUnavailableBindings needs the '
              'reason. Leaving it out is how "unimplemented" and "the browser '
              'refuses" became the same null: $undecided');
    });

    test('nothing is claimed and disclaimed at once', () {
      final Set<String> both = dvWebImplementedBindings
          .intersection(dvWebUnavailableBindings.keys.toSet());
      expect(both, isEmpty,
          reason: 'a name in both sets means the reason is stale and reads as '
              'a limitation that no longer exists: $both');
    });

    test('both sets talk about names that exist', () {
      // A reason written against a misspelled name protects nothing, and a
      // capability claimed under one reaches no caller.
      expect(dvWebImplementedBindings.difference(dvNativeBindingNames), isEmpty);
      expect(
        dvWebUnavailableBindings.keys.toSet().difference(dvNativeBindingNames),
        isEmpty,
      );
    });

    test('a reason says what the obstacle is', () {
      // Not prose review — a length floor and a ban on the two words that get
      // typed when nobody wants to write the sentence. "Not supported" is the
      // null this whole file exists to replace.
      for (final MapEntry<String, String> entry
          in dvWebUnavailableBindings.entries) {
        expect(entry.value.length, greaterThan(40),
            reason: '${entry.key}: "${entry.value}" does not say why');
        expect(entry.value.toLowerCase(), isNot(contains('todo')),
            reason: entry.key);
        expect(entry.value.trim(), entry.value, reason: entry.key);
      }
    });
  });

  group('what the browser covers', () {
    test('the capabilities a browser has no API for stay out', () {
      // Each of these has a call site in the framework and nothing in a
      // browser to serve it. Registering a no-op would turn "this platform
      // cannot" into "this silently did nothing", which is the harder bug.
      for (final String unavailable in <String>[
        'tray.show',
        'tray.hide',
        'window.maximize',
        'window.minimize',
        'window.restore',
        'window.setSize',
        'homeWidgets.publish',
        'device.watchdog.arm',
        'shortcuts.register',
        'menus.setApplicationMenu',
      ]) {
        expect(dvWebImplementedBindings, isNot(contains(unavailable)),
            reason: '$unavailable has no browser equivalent, so it must keep '
                'throwing rather than appear to work');
        expect(dvWebUnavailableBindings, contains(unavailable));
      }
    });

    test('a binding needing an optional API is not called unconditional', () {
      // The unconditional set is what a browser test may demand is registered
      // on any engine. Web NFC, Web Bluetooth and the Contact Picker are
      // Chromium-only; listing one here would make the browser suite fail on
      // Firefox for a reason that is not a fault.
      for (final String gated in <String>[
        'nfc.readTag',
        'nfc.writeTag',
        'contacts.getContacts',
        'bluetooth.scanDevices',
        'sensors.accelerometer',
        'camera.takePhoto',
        'location.current',
      ]) {
        expect(dvWebUnconditionalBindings, isNot(contains(gated)),
            reason: '$gated needs an API not every browser has, so whether it '
                'is registered has to be decided at runtime');
      }
      expect(
        dvWebUnconditionalBindings.difference(dvWebImplementedBindings),
        isEmpty,
      );
    });
  });

  group('a refusal is not an absence', () {
    test('a denial carries the binding and the browser reason', () {
      // The two failures an application has to tell apart. An unregistered
      // name throws DVNativeBridge's own "not registered"; a person clicking
      // Deny throws this, which names the binding and what the browser said.
      const DVWebPermissionDenied denied = DVWebPermissionDenied(
        'location.current',
        'User denied Geolocation',
      );

      expect(denied.binding, 'location.current');
      expect('$denied', contains('location.current'));
      expect('$denied', contains('User denied Geolocation'));
      expect(denied, isA<Exception>());
    });
  });

  group('off the web', () {
    test('register reports false rather than pretending', () {
      // This suite runs on the VM, where the stub is what resolves. It has to
      // expose the same surface or code that compiles on web fails elsewhere.
      expect(DVWebBindings.register(), isFalse);
      expect(DVWebBindings.isRegistered, isFalse);
    });

    test('the stub reports nothing registered, name by name', () {
      // The capability list is a fact about browsers and is the same on both
      // branches; what is *registered* is a fact about where the code is
      // running, and off the web that is nothing.
      for (final String name in dvWebImplementedBindings) {
        expect(DVWebBindings.registeredNames, isNot(contains(name)));
      }
    });
  });
}
