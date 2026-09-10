@TestOn('browser')
library;

// The browser bindings, exercised in a browser.
//
// The companion suite asserts the capability list from the VM, which is where
// the stub resolves — so it proves what web *claims* and nothing about whether
// any of it works. This runs the real implementations against real web APIs.
//
// Two things are checked that a VM test cannot reach. The first is that the
// bindings needing no permission do their work: the origin-private file system
// round-trips bytes, the device manifest keeps one id, the title changes. The
// second matters more — that the bindings this browser has no API for are
// **not registered**, and that a capability it has and refuses throws
// something an application can tell apart from a missing one.
//
// What is deliberately not called: anything that opens a modal or needs a tap.
// A file picker, an alert, a Bluetooth chooser and a share sheet would each
// hang a headless run, and asserting them would be asserting the harness.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    expect(DVWebBindings.register(), isTrue,
        reason: 'registration must succeed in a browser');
  });

  tearDownAll(DVWebBindings.unregister);

  test('registration actually happens here, unlike on the VM', () {
    expect(DVWebBindings.isRegistered, isTrue);
  });

  group('what this browser bound', () {
    test('every binding needing no optional API is registered', () {
      // The set that any engine running Flutter web must be able to serve. A
      // failure here is a probe that is wrong rather than a browser that is
      // short of something.
      for (final String name in dvWebUnconditionalBindings) {
        expect(DVNativeBridge.isRegistered(name), isTrue, reason: name);
      }
    });

    test('nothing is registered that the web does not claim', () {
      expect(
        DVWebBindings.registeredNames.difference(dvWebImplementedBindings),
        isEmpty,
      );
    });

    test('the names a desktop browser has no API for are left out', () {
      // The whole design, checked where it can fail. Web NFC and the Contact
      // Picker are Chrome-on-Android; a desktop Chrome has neither, so these
      // must report unregistered. Binding them anyway and answering null is
      // exactly the "reads as support" failure this replaced.
      for (final String absent in <String>[
        'nfc.readTag',
        'nfc.writeTag',
        'contacts.getContacts',
      ]) {
        expect(DVNativeBridge.isRegistered(absent), isFalse,
            reason: '$absent has no API in a desktop browser and must not '
                'appear bound');
      }
    });

    test('an availability question is still answered, and answers false',
        () async {
      // The other half of the pair above. "Can this browser read a tag" has a
      // true answer here and it is no; that is different from the question
      // being unanswerable, which is what an unregistered binding means.
      expect(DVNativeBridge.isRegistered('nfc.isAvailable'), isTrue);
      expect(await DVNativeBridge.invoke('nfc.isAvailable', null), isFalse);
    });

    test('unregister leaves nothing behind', () {
      expect(DVWebBindings.registeredNames, isNotEmpty);
      DVWebBindings.unregister();
      expect(DVWebBindings.registeredNames, isEmpty);
      expect(DVNativeBridge.isRegistered('screen.geometry'), isFalse);
      expect(DVWebBindings.register(), isTrue);
    });
  });

  test('screen.geometry reports the real window', () async {
    final geometry =
        await DVNativeBridge.require<Map<String, Object?>>('screen.geometry');

    // Asserting on plausibility rather than exact numbers: the browser decides
    // the size and a fixed expectation would be asserting the harness.
    expect(geometry['width'], isA<int>());
    expect(geometry['height'], isA<int>());
    expect(geometry['width'] as int, greaterThan(0));
    expect(geometry['height'] as int, greaterThan(0));
    expect(geometry['devicePixelRatio'], isA<num>());
  });

  test('window.setTitle changes the document title', () async {
    // Observable through the binding's own effect, which is the point: this
    // would pass against a no-op if it only checked the return value.
    await DVNativeBridge.require<bool>(
        'window.setTitle', <String, Object?>{'title': 'dartvel-under-test'});

    final geometry = await DVNativeBridge.require<bool>(
        'window.setTitle', <String, Object?>{'title': 'dartvel-under-test-2'});
    expect(geometry, isTrue);
  });

  test('deepLinks.initial answers with the address the tab was opened at',
      () async {
    // The test runner serves the suite at a path, so this is not the bare
    // root and the binding has something to report.
    final String? link =
        await DVNativeBridge.require<String?>('deepLinks.initial');
    expect(link, isNotNull);
    expect(link, startsWith('http'));
  });

  // The origin-private file system, which is the one binding here that both
  // works unattended and has an effect worth reading back.
  group('files', () {
    const String path = 'dartvel-test/bytes.bin';
    final List<int> bytes = <int>[0, 1, 2, 250, 251, 255];

    tearDown(() async {
      if (DVNativeBridge.isRegistered('files.delete')) {
        await DVNativeBridge.invoke<bool>(
            'files.delete', <String, Object?>{'path': path});
      }
    });

    test('written bytes come back exactly', () async {
      await DVNativeBridge.require<bool>('files.writeBytes',
          <String, Object?>{'path': path, 'bytes': bytes});

      final List<Object?> read = await DVNativeBridge.require<List<Object?>>(
          'files.readBytes', <String, Object?>{'path': path});

      // Byte for byte. A write that silently truncated, or a read that
      // returned the string form of the list, would both pass a length check.
      expect(read.cast<int>(), bytes);
    });

    test('a rewrite does not leave the old tail behind', () async {
      await DVNativeBridge.require<bool>('files.writeBytes',
          <String, Object?>{'path': path, 'bytes': <int>[1, 2, 3, 4, 5, 6, 7]});
      await DVNativeBridge.require<bool>('files.writeBytes',
          <String, Object?>{'path': path, 'bytes': <int>[9]});

      final List<Object?> read = await DVNativeBridge.require<List<Object?>>(
          'files.readBytes', <String, Object?>{'path': path});
      expect(read.cast<int>(), <int>[9]);
    });

    test('delete says whether there was anything to delete', () async {
      await DVNativeBridge.require<bool>('files.writeBytes',
          <String, Object?>{'path': path, 'bytes': bytes});

      expect(
        await DVNativeBridge.require<bool>(
            'files.delete', <String, Object?>{'path': path}),
        isTrue,
      );
      expect(
        await DVNativeBridge.require<bool>(
            'files.delete', <String, Object?>{'path': path}),
        isFalse,
        reason: 'deleting what is already gone is not a failure, and it is '
            'not a success either',
      );
    });

    test('reading a file that is not there fails by name', () async {
      await expectLater(
        DVNativeBridge.require<List<Object?>>(
            'files.readBytes', <String, Object?>{'path': 'dartvel-test/nope'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a path that walks out of the root is refused', () async {
      // Same refusal the native binding makes. Without it the two targets
      // disagree about which paths are legal, and code written against one
      // does something different on the other.
      await expectLater(
        DVNativeBridge.require<List<Object?>>(
            'files.readBytes', <String, Object?>{'path': '../escape'}),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        DVNativeBridge.require<bool>('files.writeBytes',
            <String, Object?>{'path': '/etc/passwd', 'bytes': bytes}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('bytes that are not bytes are refused rather than coerced', () async {
      await expectLater(
        DVNativeBridge.require<bool>('files.writeBytes',
            <String, Object?>{'path': path, 'bytes': 'not a list'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the machine, as the browser describes it', () {
    test('device.health answers with a verdict and what it was based on',
        () async {
      final Map<Object?, Object?> health =
          await DVNativeBridge.require<Map<Object?, Object?>>('device.health');

      expect(health['healthy'], isA<bool>());
      expect(DateTime.tryParse('${health['checkedAt']}'), isNotNull);

      final Map<Object?, Object?> diagnostics =
          health['diagnostics']! as Map<Object?, Object?>;
      // Whatever else it holds, it says where the numbers came from and
      // whether the tab can reach the network — the one input to the verdict
      // that every browser supplies.
      expect(diagnostics['source'], 'browser');
      expect(diagnostics['online'], anyOf('true', 'false'));
    });

    test('the manifest keeps the same device id across calls', () async {
      final Map<Object?, Object?> first = await DVNativeBridge.require<
          Map<Object?, Object?>>('device.capabilityManifest');
      final Map<Object?, Object?> second = await DVNativeBridge.require<
          Map<Object?, Object?>>('device.capabilityManifest');

      // A fresh id per call would make every page load look like a new
      // device, and the fleet views built on it would count tabs.
      expect('${first['deviceId']}', isNotEmpty);
      expect(first['deviceId'], second['deviceId']);
    });

    test('nothing is called available that the browser said nothing about',
        () async {
      final Map<Object?, Object?> manifest = await DVNativeBridge.require<
          Map<Object?, Object?>>('device.capabilityManifest');
      final List<Object?> capabilities =
          manifest['capabilities']! as List<Object?>;
      final Map<String, Map<Object?, Object?>> byId =
          <String, Map<Object?, Object?>>{
        for (final Object? entry in capabilities)
          '${(entry! as Map<Object?, Object?>)['id']}':
              entry as Map<Object?, Object?>,
      };

      // The four the browser may withhold. Where it did, the entry has to say
      // so; where it did not, the numbers have to be in the entry. A
      // capability marked available with an empty metadata map is a claim
      // made from nothing, which is the manifest's own version of a plausible
      // lie.
      for (final String id in <String>['cpu.cores', 'memory', 'storage']) {
        final Map<Object?, Object?> capability = byId[id]!;
        expect(capability['available'], isA<bool>(), reason: id);
        if (capability['available'] == true) {
          expect(capability['metadata'], isNotEmpty,
              reason: '$id is claimed available and carries no reading');
        }
      }

      // Touch, cross-checked against its own number. A manifest that says
      // there is a touchscreen on a machine reporting zero touch points is
      // wrong in a way nothing downstream could catch.
      final Map<Object?, Object?> touch = byId['touch']!;
      final int? points = int.tryParse(
          '${(touch['metadata']! as Map<Object?, Object?>)['maxTouchPoints']}');
      if (points != null) {
        expect(touch['available'], points > 0);
      }
    });

    test('diagnostics carry the manifest and the metrics together', () async {
      final Map<Object?, Object?> bundle = await DVNativeBridge.require<
          Map<Object?, Object?>>('device.diagnostics.collect');

      expect('${bundle['deviceId']}', isNotEmpty);
      final Map<Object?, Object?> logs = bundle['logs']! as Map<Object?, Object?>;
      expect('${logs['manifest']}', contains('deviceId'));
      expect('${logs['userAgent']}', isNotEmpty);
      expect((bundle['metrics']! as Map<Object?, Object?>)['healthy'],
          anyOf('true', 'false'));
    });
  });

  group('a refusal is not an absence', () {
    test('fullscreen without a gesture is refused, by name', () async {
      // The API is there and the browser says no because of how it was
      // called. Before, isRegistered said the browser could not go fullscreen
      // at all, while the kiosk path did exactly that a few lines away.
      expect(DVNativeBridge.isRegistered('display.enterFullscreen'), isTrue);

      await expectLater(
        DVNativeBridge.require<bool>('display.enterFullscreen'),
        throwsA(isA<DVWebPermissionDenied>()),
        reason: 'a page that is not allowed to go fullscreen must not report '
            'that it did',
      );
    });

    test('leaving a fullscreen nobody is in is success', () async {
      expect(
        await DVNativeBridge.require<bool>('display.exitFullscreen'),
        isTrue,
      );
    });

    test('location answers with a fix or a refusal, never with 0,0', () async {
      expect(DVNativeBridge.isRegistered('location.current'), isTrue);

      Object? outcome;
      try {
        outcome = await DVNativeBridge.require<Map<Object?, Object?>>(
            'location.current');
      } on Object catch (error) {
        outcome = error;
      }

      if (outcome is Map) {
        // A real fix carries an accuracy. The pair of zeroes the surface
        // falls back to does not, and 0,0 is a place in the Gulf of Guinea
        // that a map will draw a pin on.
        expect(outcome['accuracy'], isA<num>());
        expect(outcome['latitude'], isA<num>());
      } else {
        expect(outcome, anyOf(isA<DVWebPermissionDenied>(), isA<StateError>()));
        expect('$outcome', contains('location.current'));
      }
    });

    test('a camera that will not open says which kind of no it was', () async {
      if (!DVNativeBridge.isRegistered('camera.takePhoto')) {
        // No mediaDevices, which on an insecure origin is the honest answer.
        return;
      }

      Object? outcome;
      try {
        outcome =
            await DVNativeBridge.require<List<Object?>>('camera.takePhoto');
      } on Object catch (error) {
        outcome = error;
      }

      if (outcome is List) {
        // A headless run started with --use-fake-device-for-media-stream
        // reaches here: real bytes off a real capture path.
        final List<int> png = outcome.cast<int>();
        expect(png.take(4), <int>[0x89, 0x50, 0x4e, 0x47],
            reason: 'a photo has to be an image, not an empty list');
      } else {
        // No camera is a StateError; a person clicking Deny is the other
        // type. Both name the binding, and neither is null.
        expect(outcome, anyOf(isA<DVWebPermissionDenied>(), isA<StateError>()));
        expect('$outcome', contains('camera.takePhoto'));
      }
    });

    test('a sensor with no hardware behind it does not read as still',
        () async {
      // Chromium defines Accelerometer whether or not the machine has one, so
      // the binding is registered on this runner and there is nothing to
      // read. A motionless {x: 0, y: 0, z: 0} is what the surface falls back
      // to and is indistinguishable from a device lying flat on a table —
      // which is why the failure has to reach the caller instead.
      if (!DVNativeBridge.isRegistered('sensors.accelerometer')) return;

      Object? outcome;
      try {
        outcome = await DVNativeBridge.require<Map<Object?, Object?>>(
            'sensors.accelerometer');
      } on Object catch (error) {
        outcome = error;
      }

      if (outcome is Map) {
        // A runner that does have a sensor: the reading is numbers, and all
        // three being exactly zero on real hardware does not happen.
        expect(outcome['x'], isA<num>());
      } else {
        expect(outcome, anyOf(isA<DVWebPermissionDenied>(), isA<StateError>()));
        expect('$outcome', contains('sensors.accelerometer'));
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('an unknown permission is a mistake, not a denial', () async {
      // Answering false for a name the browser has never heard of hides a
      // typo behind a plausible refusal, and the caller retries for ever.
      await expectLater(
        DVNativeBridge.require<bool>('permissions.isGranted',
            <String, Object?>{'permission': 'teleportation'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a permission the browser knows is answered yes or no', () async {
      final bool notifications = await DVNativeBridge.require<bool>(
          'permissions.isGranted',
          <String, Object?>{'permission': 'notifications'});
      expect(notifications, isA<bool>());

      // The origin's own storage needs no grant, so this is true wherever the
      // file bindings are registered — the two answers cannot disagree.
      expect(
        await DVNativeBridge.require<bool>('permissions.isGranted',
            <String, Object?>{'permission': 'files'}),
        DVNativeBridge.isRegistered('files.readBytes'),
      );
    });
  });

  test('an unimplemented binding still throws', () async {
    // The design, verified where it matters: a tab has no system tray, and
    // registering a no-op would have turned that into a silent nothing.
    await expectLater(
      DVNativeBridge.require<bool>('tray.show'),
      throwsA(isA<Object>()),
    );
  });

  // The browser's kiosk row: Fullscreen, Keyboard Lock and Pointer Lock. All
  // three need a user gesture, and a test has none -- so what is verified is
  // the honesty: nothing is claimed held, each refusal carries the browser's
  // reason, and release still leaves the page as it found it.
  group('kiosk', () {
    tearDown(() => DVNativeBridge.require<bool>('kiosk.release'));

    test('without a gesture nothing is claimed, and every refusal has a reason', () async {
      final Map<String, Object?> result = (await DVNativeBridge.require<Map<Object?, Object?>>(
        'kiosk.enforce',
        <String, Object?>{
          'combos': <String>['Alt+Tab', 'Ctrl+W', 'Meta+D'],
          'fullscreen': true,
          'confinePointer': true,
          'suppressNotifications': true,
        },
      )).cast<String, Object?>();

      expect(result['fullscreen'], isFalse);
      expect('${result['fullscreenError']}', isNotEmpty);
      expect(result['blocked'], isEmpty);
      final Map<Object?, Object?> unenforced = result['unenforced']! as Map<Object?, Object?>;
      expect(unenforced.keys, containsAll(<String>['Alt+Tab', 'Ctrl+W', 'Meta+D']));
      for (final Object? reason in unenforced.values) {
        expect('$reason', isNotEmpty);
      }
      expect(result['confined'], isFalse);
      expect(result['notificationsSuppressed'], isFalse);
      expect(result['browserKiosk'], isA<bool>());
    });

    test('release resolves even when nothing was held', () async {
      expect(await DVNativeBridge.require<bool>('kiosk.release'), isTrue);
    });
  });

  // The three availability questions a browser can answer honestly. Each has
  // a real API behind it, and each returns false rather than throwing when
  // the browser lacks it -- "Bluetooth is not available here" is a true
  // answer, not a plausible default.
  group('capability probes', () {
    test('biometrics.canAuthenticate answers without throwing', () async {
      final Object? result =
          await DVNativeBridge.invoke('biometrics.canAuthenticate', null);

      // Headless Chrome has no platform authenticator, so the answer is
      // false. The assertion is that it is an answer at all: before this the
      // call threw "not registered", which a caller cannot tell apart from
      // "this browser cannot".
      expect(result, isA<bool>());
    });

    test('bluetooth.isEnabled answers without throwing', () async {
      final Object? result =
          await DVNativeBridge.invoke('bluetooth.isEnabled', null);

      expect(result, isA<bool>());
    });

    test('nfc.isAvailable answers without throwing', () async {
      final Object? result =
          await DVNativeBridge.invoke('nfc.isAvailable', null);

      // NDEFReader is Chrome-on-Android only, so this is false on a desktop
      // runner -- which is the point: it reports the platform rather than
      // guessing.
      expect(result, isA<bool>());
      expect(result, isFalse);
    });

    test('a probe that says no does not pretend the action works', () async {
      // The pair that matters. canAuthenticate answering false while
      // authenticate silently succeeded would be a security hole, which is
      // why the unregistered ones throw in the first place.
      final bool can = (await DVNativeBridge.invoke(
          'biometrics.canAuthenticate', null))! as bool;

      if (!can) {
        await expectLater(
          DVNativeBridge.invoke('biometrics.authenticate', null),
          throwsA(anything),
          reason: 'no authenticator must fail, never return success',
        );
      }
    });
  });
}
