/// What each iOS binding asks the Swift shim, and what it makes of the answer.
///
/// Plain Dart with no FFI in it, for the same two reasons as
/// `android_capture.dart`: it can be tested on a machine with no iPhone, and
/// the decisions worth testing are here rather than in the calls. Whether the
/// share sheet came up is a Swift question. Whether "no photo" means the
/// person cancelled or the build left out a usage description is this file's,
/// and getting it wrong produces an application that looks like it works.
///
/// The transport is a function: `ios_shim_ffi.dart` passes the real one, the
/// tests pass a fake that answers the way the Swift is written to.
library dartvel_flutter.platform.ios.shim_plan;

import 'dart:async';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvIosPermissions, DVIosPermission;

import '../android/android_capture.dart' show dvAndroidMediaKind;
import '../network.dart' show DVNetworkStatus;
import 'ios_capabilities.dart' show dvIosShimBindings;

/// Sends [op] with [args] to the shim and answers its decoded JSON.
typedef DVIosShimCall = Future<Map<String, Object?>> Function(
    String op, Map<String, Object?> args);

/// Standard gravity. Core Motion reports acceleration in g; Android and the
/// DV.Platform contract report m/s².
const double dvIosStandardGravity = 9.80665;

/// How long `bluetooth.scanDevices` listens. iOS has no list of known
/// devices to answer from, so a scan is the only way to say what is near.
const int dvIosBluetoothScanSeconds = 4;

/// The sentence LocalAuthentication shows when the application gives none.
/// `evaluatePolicy` refuses an empty reason outright.
const String dvIosDefaultBiometricReason = 'Confirm it is you';

/// The binding handlers the shim backs, keyed by binding name.
Map<String, Future<Object?> Function(Object?)> dvIosShimHandlers(DVIosShimCall call) {
  Future<Map<String, Object?>> ask(String op, [Map<String, Object?> args = const <String, Object?>{}]) async {
    final Map<String, Object?> answer = await call(op, args);
    final Object? error = answer['error'];
    if (error != null) throw StateError('iOS could not answer $op: $error');
    return answer;
  }

  Map<String, Object?> argsOf(Object? arguments) => arguments is Map
      ? arguments.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v))
      : <String, Object?>{};

  Future<bool> permission(String op, Object? arguments) async {
    final String name = '${argsOf(arguments)['permission'] ?? ''}';
    final DVIosPermission? entry = dvIosPermissions[name];
    if (entry == null) {
      throw StateError('"$name" is not a permission Dartvel knows. The names are '
          '${dvIosPermissions.keys.toList()..sort()}.');
    }
    if (!entry.supported) return false;
    // Nothing to ask for, and nothing iOS keeps a status of.
    if (entry.usageKeys.isEmpty && name != 'notifications') return true;
    final Map<String, Object?> answer =
        await ask(op, <String, Object?>{'permission': name, 'keys': entry.usageKeys});
    if (answer['declared'] == false) {
      throw StateError('Info.plist does not declare ${entry.usageKeys.join(', ')}, '
          'which iOS requires before it will ask for "$name" -- it terminates '
          'an application that asks without it, so no dialog was shown. Add '
          '"$name" to dartvel.ios.permissions in pubspec.yaml and run dartvel '
          'build ios again.');
    }
    return answer['granted'] == true;
  }

  List<Map<String, Object?>> items(Map<String, Object?> answer) => <Map<String, Object?>>[
        for (final Object? entry in (answer['items'] as List<Object?>?) ?? const <Object?>[])
          if (entry is Map)
            <String, Object?>{
              ...entry.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)),
              'type': dvAndroidMediaKind(entry['mimeType'] as String?, '${entry['name'] ?? ''}'),
            },
      ];

  Future<Map<String, double>?> sample(String sensor) async {
    final Map<String, Object?> answer = await ask('sensors.sample', <String, Object?>{'sensor': sensor});
    final Object? x = answer['x'], y = answer['y'], z = answer['z'];
    if (x is! num || y is! num || z is! num) return null;
    final double unit = sensor == 'accelerometer' ? dvIosStandardGravity : 1;
    return <String, double>{'x': x * unit, 'y': y * unit, 'z': z * unit};
  }

  Future<bool> powered() async =>
      (await ask('bluetooth.state'))['state'] == 'poweredOn';

  final Map<String, Future<Object?> Function(Object?)> handlers = <String, Future<Object?> Function(Object?)>{
    'share.text': (Object? a) async =>
        (await ask('share.text', <String, Object?>{'text': '${argsOf(a)['text'] ?? ''}'}))['presented'] == true,
    'screen.geometry': (Object? _) async {
      final Map<String, Object?> answer = await ask('screen.geometry');
      final Object? width = answer['width'], height = answer['height'], scale = answer['scale'];
      if (width is! num || height is! num || width <= 0 || height <= 0) return null;
      return <String, Object?>{
        'width': width.round(),
        'height': height.round(),
        if (scale is num && scale > 0) 'devicePixelRatio': scale.toDouble(),
      };
    },
    'permissions.isGranted': (Object? a) => permission('permissions.status', a),
    'permissions.request': (Object? a) => permission('permissions.request', a),
    'camera.takePhoto': (Object? _) async {
      final List<Map<String, Object?>> taken = items(await ask('camera.takePhoto'));
      if (taken.isEmpty) return <int>[];
      final File photo = File('${taken.first['path']}');
      final List<int> bytes = await photo.readAsBytes();
      // A private copy the shim wrote into tmp; the bytes are the answer.
      try {
        await photo.delete();
      } on FileSystemException {
        // tmp is the system's to clear.
      }
      return bytes;
    },
    'media.pick': (Object? a) async {
      final Map<String, Object?> args = argsOf(a);
      return items(await ask('media.pick', <String, Object?>{
        'type': '${args['type'] ?? 'any'}',
        'multiple': args['multiple'] == true,
      }));
    },
    'contacts.getContacts': (Object? a) async {
      final Object? limit = argsOf(a)['limit'];
      final Map<String, Object?> answer =
          await ask('contacts.list', <String, Object?>{'limit': limit is int ? limit : 0});
      return <Map<String, String>>[
        for (final Object? person in (answer['contacts'] as List<Object?>?) ?? const <Object?>[])
          if (person is Map)
            <String, String>{
              for (final MapEntry<Object?, Object?> field in person.entries) '${field.key}': '${field.value ?? ''}',
            },
      ];
    },
    'location.current': (Object? a) async {
      final Map<String, Object?> args = argsOf(a);
      final Map<String, Object?> answer = await ask('location.current', <String, Object?>{
        'maxAgeSeconds': args['maxAgeSeconds'] is int ? args['maxAgeSeconds'] : 120,
        'timeoutSeconds': args['timeoutSeconds'] is int ? args['timeoutSeconds'] : 20,
      });
      final Object? latitude = answer['latitude'], longitude = answer['longitude'];
      if (latitude is! num || longitude is! num) {
        throw StateError('the iOS location answer had no coordinates ($answer). '
            'Nothing here is a position, and zero is a place.');
      }
      return <String, Object?>{...answer, 'latitude': latitude.toDouble(), 'longitude': longitude.toDouble()};
    },
    'nfc.isAvailable': (Object? _) async => (await ask('nfc.available'))['available'] == true,
    'bluetooth.isEnabled': (Object? _) => powered(),
    'bluetooth.adapters': (Object? _) async => <Map<String, Object?>>[
          <String, Object?>{'path': 'ios/bluetooth', 'address': '', 'powered': await powered(), 'discovering': false},
        ],
    'bluetooth.scanDevices': (Object? _) async {
      final Map<String, Object?> answer =
          await ask('bluetooth.scan', <String, Object?>{'seconds': dvIosBluetoothScanSeconds});
      return <String>[
        for (final Object? device in (answer['devices'] as List<Object?>?) ?? const <Object?>[])
          if (device is Map) '${device['name'] ?? device['id']}',
      ];
    },
    'bluetooth.devices': (Object? _) async {
      final Map<String, Object?> answer = await ask('bluetooth.known');
      return <Map<String, Object?>>[
        for (final Object? device in (answer['devices'] as List<Object?>?) ?? const <Object?>[])
          if (device is Map)
            <String, Object?>{
              // CoreBluetooth hides the MAC address; the identifier it hands
              // out instead is stable for this application on this device.
              'path': '${device['id']}',
              'address': '${device['id']}',
              if (device['name'] is String) 'name': device['name'],
              'connected': device['connected'] == true,
            },
      ];
    },
    'sensors.accelerometer': (Object? _) => sample('accelerometer'),
    'sensors.gyroscope': (Object? _) => sample('gyroscope'),
    'biometrics.canAuthenticate': (Object? _) async => (await ask('biometrics.can'))['available'] == true,
    'biometrics.authenticate': (Object? a) async {
      final Object? reason = argsOf(a)['reason'];
      return (await ask('biometrics.authenticate', <String, Object?>{
            'reason': reason is String && reason.isNotEmpty ? reason : dvIosDefaultBiometricReason,
          }))['authenticated'] ==
          true;
    },
    'notifications.sendLocal': (Object? a) async {
      final Map<String, Object?> args = argsOf(a);
      return (await ask('notifications.send', <String, Object?>{
            'title': '${args['title'] ?? ''}',
            'body': '${args['body'] ?? ''}',
          }))['delivered'] ==
          true;
    },
    'kiosk.enforce': (Object? a) async {
      final List<String> combos = <String>[
        for (final Object? c in (argsOf(a)['combos'] as List<Object?>?) ?? const <Object?>[]) '$c',
      ];
      final bool held = (await ask('kiosk.guidedAccess', <String, Object?>{'enabled': true}))['enabled'] == true;
      return dvIosKioskEnforced(combos, held: held);
    },
    'kiosk.release': (Object? _) async {
      await ask('kiosk.guidedAccess', <String, Object?>{'enabled': false});
      return true;
    },
  };
  assert(handlers.keys.toSet().containsAll(dvIosShimBindings) &&
      dvIosShimBindings.containsAll(handlers.keys));
  return handlers;
}

/// What a Guided Access request held, in the shape `DVKioskEnforced` reads.
///
/// Guided Access is all or nothing: when the session starts, the home
/// gesture, the switcher, notifications and a hardware keyboard's shortcuts
/// all stop, and when it is refused none of them do. iOS grants it to an
/// application only on a supervised device whose configuration profile
/// allows it Autonomous Single App Mode, which is the reason every refusal
/// gives.
Map<String, Object?> dvIosKioskEnforced(List<String> combos, {required bool held}) => <String, Object?>{
      'blocked': held ? combos : const <String>[],
      'unenforced': held
          ? const <String, String>{}
          : <String, String>{
              for (final String c in combos)
                c: 'iOS refused Guided Access: the device must be supervised, with this '
                    'application allowed Autonomous Single App Mode by its profile',
            },
      'fullscreen': held,
      'confined': held,
      'notificationsSuppressed': held,
    };

/// What an `NWPath` reported, as `DV.Platform.network` reads it.
///
/// Expensive (cellular, a personal hotspot) and constrained (Low Data Mode)
/// are both metered: a sync may run on them and a video prefetch should not.
DVNetworkStatus dvIosNetworkStatus(Map<String, Object?> event) => switch (event['status']) {
      'satisfied' when event['expensive'] == true || event['constrained'] == true => DVNetworkStatus.metered,
      'satisfied' => DVNetworkStatus.online,
      'unsatisfied' || 'requiresConnection' => DVNetworkStatus.offline,
      _ => DVNetworkStatus.unknown,
    };
