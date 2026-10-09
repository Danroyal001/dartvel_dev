// What each iOS binding asks the Swift shim, and what it makes of the answer.
//
// The shim itself needs an iPhone. Everything worth getting wrong on this side
// does not: which operation a binding sends, what it does with a refusal, and
// how an answer becomes the shape DV.Platform reads on every other target. A
// fake shim stands in for the Swift here, answering the way the Swift is
// written to.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvIosShimOperations;
import 'package:dartvel_flutter/src/kiosk/kiosk.dart' show DVKioskEnforced;
import 'package:dartvel_flutter/src/platform/ios/ios_capabilities.dart';
import 'package:dartvel_flutter/src/platform/ios/ios_shim_plan.dart';
import 'package:dartvel_flutter/src/platform/network.dart' show DVNetworkStatus;
import 'package:flutter_test/flutter_test.dart';

class _FakeShim {
  final List<(String, Map<String, Object?>)> calls = <(String, Map<String, Object?>)>[];
  final Map<String, Map<String, Object?>> answers = <String, Map<String, Object?>>{};

  Future<Map<String, Object?>> call(String op, Map<String, Object?> args) async {
    calls.add((op, args));
    expect(dvIosShimOperations, contains(op),
        reason: 'the Swift has no case for $op');
    return answers[op] ?? <String, Object?>{'error': 'no answer for $op'};
  }
}

void main() {
  late _FakeShim shim;
  late Map<String, Future<Object?> Function(Object?)> plan;
  late Directory temp;

  setUp(() {
    shim = _FakeShim();
    temp = Directory.systemTemp.createTempSync('dv-ios-plan');
    plan = dvIosShimHandlers(shim.call);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('the plan covers exactly the shim half of the capability list', () {
    expect(plan.keys.toSet(), dvIosShimBindings);
    expect(dvIosImplementedBindings.containsAll(dvIosShimBindings), isTrue);
  });

  test('every binding Android has, iOS has, except bluetooth.pair', () {
    // CoreBluetooth has no pairing call: iOS pairs on the first encrypted
    // read, inside its own dialog. Everything else Android binds is here.
    const Set<String> android = <String>{
      'clipboard.copy', 'clipboard.paste', 'haptics.vibrate',
      'haptics.lightVibrate', 'haptics.impact', 'share.text', 'kiosk.enforce',
      'kiosk.release', 'deepLinks.initial', 'permissions.isGranted',
      'permissions.request', 'camera.takePhoto', 'media.pick',
      'contacts.getContacts', 'location.current', 'screen.geometry',
      'nfc.isAvailable', 'bluetooth.isEnabled', 'bluetooth.adapters',
      'bluetooth.devices', 'bluetooth.scanDevices', 'bluetooth.pair',
      'homeWidgets.publish', 'sensors.accelerometer', 'sensors.gyroscope',
      'biometrics.canAuthenticate', 'notifications.sendLocal',
      'device.capabilityManifest', 'device.health', 'device.watchdog.arm',
      'device.watchdog.heartbeat', 'device.fleet.provision',
      'device.diagnostics.collect', 'files.readBytes', 'files.writeBytes',
      'files.delete',
    };
    expect(android.difference(dvIosImplementedBindings), <String>{'bluetooth.pair'});
  });

  group('share.text', () {
    test('answers true once the sheet is up', () async {
      shim.answers['share.text'] = <String, Object?>{'presented': true};
      expect(await plan['share.text']!(<String, Object?>{'text': 'hi'}), isTrue);
      expect(shim.calls.single.$2, <String, Object?>{'text': 'hi'});
    });

    test('a shim error is thrown, not reported as false', () async {
      shim.answers['share.text'] = <String, Object?>{'error': 'no window'};
      expect(() => plan['share.text']!(<String, Object?>{'text': 'x'}),
          throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('no window'))));
    });
  });

  group('screen.geometry', () {
    test('uses the keys every other target reports', () async {
      shim.answers['screen.geometry'] = <String, Object?>{'width': 1179, 'height': 2556, 'scale': 3.0};
      expect(await plan['screen.geometry']!(null),
          <String, Object?>{'width': 1179, 'height': 2556, 'devicePixelRatio': 3.0});
    });

    test('a zero screen is null, not a 0x0 layout', () async {
      shim.answers['screen.geometry'] = <String, Object?>{'width': 0, 'height': 0, 'scale': 3.0};
      expect(await plan['screen.geometry']!(null), isNull);
    });
  });

  group('permissions', () {
    test('a typo throws rather than being granted', () async {
      expect(() => plan['permissions.request']!(<String, Object?>{'permission': 'camrea'}),
          throwsStateError);
      expect(shim.calls, isEmpty);
    });

    test('a name with nothing to ask is granted without the shim', () async {
      expect(await plan['permissions.isGranted']!(<String, Object?>{'permission': 'clipboard'}), isTrue);
      expect(shim.calls, isEmpty);
    });

    test('allFiles is refused, because iOS has no such grant', () async {
      expect(await plan['permissions.request']!(<String, Object?>{'permission': 'allFiles'}), isFalse);
    });

    test('the shim is told which Info.plist keys to check', () async {
      shim.answers['permissions.request'] = <String, Object?>{'granted': true, 'declared': true};
      expect(await plan['permissions.request']!(<String, Object?>{'permission': 'camera'}), isTrue);
      expect(shim.calls.single.$2, <String, Object?>{
        'permission': 'camera',
        'keys': <String>['NSCameraUsageDescription'],
      });
    });

    test('an undeclared key is a build mistake, said as one', () async {
      // iOS terminates an application that asks without the key, so the
      // shim never asks; reporting that as false would read as "the person
      // said no" when no dialog was ever shown.
      shim.answers['permissions.status'] = <String, Object?>{'granted': false, 'declared': false};
      expect(
          () => plan['permissions.isGranted']!(<String, Object?>{'permission': 'location'}),
          throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
              allOf(contains('dartvel.ios.permissions'), contains('NSLocationWhenInUseUsageDescription')))));
    });
  });

  group('camera and picker', () {
    test('the photograph comes back as its bytes, and the copy is removed', () async {
      final File photo = File('${temp.path}/p.jpg')..writeAsBytesSync(<int>[1, 2, 3]);
      shim.answers['camera.takePhoto'] = <String, Object?>{
        'items': <Object?>[<String, Object?>{'path': photo.path, 'name': 'p.jpg', 'mimeType': 'image/jpeg'}],
      };
      expect(await plan['camera.takePhoto']!(null), <int>[1, 2, 3]);
      expect(photo.existsSync(), isFalse);
    });

    test('cancelling the camera is no bytes, not an error', () async {
      shim.answers['camera.takePhoto'] = <String, Object?>{'items': <Object?>[]};
      expect(await plan['camera.takePhoto']!(null), isEmpty);
    });

    test('picked items carry the kind word the desktop pickers use', () async {
      shim.answers['media.pick'] = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'path': '/tmp/a.heic', 'name': 'a.heic', 'mimeType': 'image/heic'},
          <String, Object?>{'path': '/tmp/b.mov', 'name': 'b.mov', 'mimeType': ''},
          <String, Object?>{'path': '/tmp/c.pdf', 'name': 'c.pdf', 'mimeType': 'application/pdf'},
        ],
      };
      final Object? items = await plan['media.pick']!(<String, Object?>{'type': 'any', 'multiple': true});
      expect((items! as List<Object?>).map((Object? i) => (i! as Map<String, Object?>)['type']),
          <String>['image', 'video', 'file']);
      expect(shim.calls.single.$2, <String, Object?>{'type': 'any', 'multiple': true});
    });
  });

  group('contacts and location', () {
    test('every contact value is a string', () async {
      shim.answers['contacts.list'] = <String, Object?>{
        'contacts': <Object?>[<String, Object?>{'id': 7, 'name': 'Ada', 'phone': null}],
      };
      expect(await plan['contacts.getContacts']!(null), <Object?>[
        <String, String>{'id': '7', 'name': 'Ada', 'phone': ''},
      ]);
    });

    test('a fix with no coordinates throws, because zero is a place', () async {
      shim.answers['location.current'] = <String, Object?>{'accuracy': 5};
      expect(() => plan['location.current']!(null), throwsStateError);
    });

    test('a fix is latitude and longitude as doubles', () async {
      shim.answers['location.current'] = <String, Object?>{'latitude': 6, 'longitude': 3.35, 'accuracy': 5.0};
      final Object? at = await plan['location.current']!(null);
      expect((at! as Map<String, Object?>)['latitude'], 6.0);
      expect((at as Map<String, Object?>)['longitude'], 3.35);
    });
  });

  group('sensors', () {
    test('the accelerometer is in m/s², as Android reports it', () async {
      // Core Motion reports in g. Passing it through would make a phone at
      // rest read 1 on iOS and 9.8 on Android, from the same call.
      shim.answers['sensors.sample'] = <String, Object?>{'x': 0.0, 'y': 0.0, 'z': -1.0};
      final Object? sample = await plan['sensors.accelerometer']!(null);
      expect((sample! as Map<String, double>)['z'], closeTo(-9.80665, 1e-9));
      expect(shim.calls.single.$2, <String, Object?>{'sensor': 'accelerometer'});
    });

    test('the gyroscope is already rad/s and passes through', () async {
      shim.answers['sensors.sample'] = <String, Object?>{'x': 0.5, 'y': 0.0, 'z': 0.0};
      final Object? sample = await plan['sensors.gyroscope']!(null);
      expect((sample! as Map<String, double>)['x'], 0.5);
    });

    test('a sample missing an axis is null, not a padded zero', () async {
      shim.answers['sensors.sample'] = <String, Object?>{'x': 0.5, 'y': 0.0};
      expect(await plan['sensors.gyroscope']!(null), isNull);
    });
  });

  group('bluetooth', () {
    test('enabled means powered on, nothing less', () async {
      shim.answers['bluetooth.state'] = <String, Object?>{'state': 'poweredOff'};
      expect(await plan['bluetooth.isEnabled']!(null), isFalse);
      shim.answers['bluetooth.state'] = <String, Object?>{'state': 'poweredOn'};
      expect(await plan['bluetooth.isEnabled']!(null), isTrue);
    });

    test('one adapter, with no address, because iOS exposes none', () async {
      shim.answers['bluetooth.state'] = <String, Object?>{'state': 'poweredOn'};
      expect(await plan['bluetooth.adapters']!(null), <Object?>[
        <String, Object?>{'path': 'ios/bluetooth', 'address': '', 'powered': true, 'discovering': false},
      ]);
    });

    test('a scan answers names, falling back to the identifier', () async {
      shim.answers['bluetooth.scan'] = <String, Object?>{
        'devices': <Object?>[
          <String, Object?>{'id': 'A-1', 'name': 'Printer'},
          <String, Object?>{'id': 'B-2'},
        ],
      };
      expect(await plan['bluetooth.scanDevices']!(null), <String>['Printer', 'B-2']);
    });
  });

  group('the rest', () {
    test('biometrics: canAuthenticate and authenticate are booleans', () async {
      shim.answers['biometrics.can'] = <String, Object?>{'available': true};
      expect(await plan['biometrics.canAuthenticate']!(null), isTrue);
      shim.answers['biometrics.authenticate'] = <String, Object?>{'authenticated': false};
      expect(await plan['biometrics.authenticate']!(null), isFalse);
      // LAContext refuses an empty reason, so one is always sent.
      expect((shim.calls.last.$2['reason']! as String).isNotEmpty, isTrue);
    });

    test('a notification the person switched off is false, so it throws upstream', () async {
      shim.answers['notifications.send'] = <String, Object?>{'delivered': false};
      expect(await plan['notifications.sendLocal']!(<String, Object?>{'title': 't', 'body': 'b'}), isFalse);
    });

    test('kiosk.enforce reports what Guided Access held, or why not', () async {
      shim.answers['kiosk.guidedAccess'] = <String, Object?>{'enabled': false};
      final Object? refused = await plan['kiosk.enforce']!(<String, Object?>{'combos': <String>['Meta+H']});
      final DVKioskEnforced held = DVKioskEnforced.fromMap(refused! as Map<Object?, Object?>);
      expect(held.blocked, isEmpty);
      expect(held.unenforced.keys, <String>['Meta+H']);
      expect(held.unenforced['Meta+H'], contains('supervised'));

      shim.answers['kiosk.guidedAccess'] = <String, Object?>{'enabled': true};
      final DVKioskEnforced on = DVKioskEnforced.fromMap(
          (await plan['kiosk.enforce']!(<String, Object?>{'combos': <String>['Meta+H']}))! as Map<Object?, Object?>);
      expect(on.blocked, <String>['Meta+H']);
      expect(on.fullscreen && on.confined && on.notificationsSuppressed, isTrue);
    });
  });

  group('network', () {
    test('satisfied and expensive is metered, not online', () {
      expect(dvIosNetworkStatus(<String, Object?>{'status': 'satisfied', 'expensive': true}), DVNetworkStatus.metered);
      expect(dvIosNetworkStatus(<String, Object?>{'status': 'satisfied', 'constrained': true}), DVNetworkStatus.metered);
      expect(dvIosNetworkStatus(<String, Object?>{'status': 'satisfied'}), DVNetworkStatus.online);
      expect(dvIosNetworkStatus(<String, Object?>{'status': 'unsatisfied'}), DVNetworkStatus.offline);
      expect(dvIosNetworkStatus(<String, Object?>{'status': 'requiresConnection'}), DVNetworkStatus.offline);
      expect(dvIosNetworkStatus(<String, Object?>{}), DVNetworkStatus.unknown);
    });
  });

  group('where the device runtime and files live', () {
    test('under Application Support, in two separate directories', () {
      expect(dvIosStateDirectory('/var/mobile/Containers/Data/Application/X'),
          '/var/mobile/Containers/Data/Application/X/Library/Application Support/dartvel-device');
      expect(dvIosFilesRoot('/var/mobile/Containers/Data/Application/X/'),
          '/var/mobile/Containers/Data/Application/X/Library/Application Support/dartvel-files');
    });

    test('no home is no directory, not one at the root of the device', () {
      expect(dvIosStateDirectory(null), isNull);
      expect(dvIosFilesRoot(''), isNull);
      expect(dvIosFilesRoot('/'), isNull);
    });
  });
}
