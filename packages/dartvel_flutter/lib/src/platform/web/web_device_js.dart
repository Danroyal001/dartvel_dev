/// `device.capabilityManifest`, `device.health` and
/// `device.diagnostics.collect` in a browser.
///
/// The native versions of these read procfs, sysfs, Win32 and Mach. A browser
/// hands out a much shorter list on purpose — most of what a machine knows
/// about itself is a fingerprint — so this reports what it is given and marks
/// the rest unavailable rather than filling it with zeroes. A capability
/// entry with `available: false` is the shape the manifest already has for
/// "this machine does not have one", and it is the right shape for "this
/// browser will not say".
///
/// The identity is the part that differs most. There is no hardware id here
/// and nothing that survives somebody clearing site data, so the device id is
/// a random value kept in `localStorage`: stable for this browser profile on
/// this origin, and gone when the person clears storage. That is why
/// `device.fleet.provision` is not implemented — a fleet identity a browser
/// setting erases is worse than none — and the doc on [deviceId] says so
/// where somebody reading the value will see it.
library dartvel_flutter.platform.web.device;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import 'web_interop.dart';

class DVWebDevice {
  const DVWebDevice._();

  static const Set<String> implemented = <String>{
    'device.capabilityManifest',
    'device.health',
    'device.diagnostics.collect',
  };

  /// Where the generated id is kept.
  static const String _idKey = 'dartvel.device-id';

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('device.capabilityManifest', (Object? _) => manifest());
    register('device.health', (Object? _) => health());
    register('device.diagnostics.collect', (Object? _) => diagnostics());
  }

  /// A random id, kept in `localStorage` for as long as the browser keeps it.
  ///
  /// Not a device id in the sense the native bindings mean. It identifies a
  /// browser profile on one origin: a second browser on the same machine gets
  /// a different one, and clearing site data throws it away. Where
  /// `localStorage` is unavailable — a private window with storage blocked —
  /// this returns a fresh value each call, and a caller that treats it as
  /// stable will see a new device on every page load.
  static String deviceId() {
    try {
      final String? kept = web.window.localStorage.getItem(_idKey);
      if (kept != null && kept.isNotEmpty) return kept;
      final String fresh = _randomId();
      web.window.localStorage.setItem(_idKey, fresh);
      return fresh;
    } on Object {
      return _randomId();
    }
  }

  static String _randomId() {
    final Random random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// What this browser will admit about the machine.
  static Future<Map<String, Object?>> manifest() async {
    final JSObject? navigator = dvNavigator;
    final num? cores =
        navigator == null ? null : dvJsNum(navigator, 'hardwareConcurrency');
    // deviceMemory is Chromium-only and is deliberately rounded to a power of
    // two, so it is a floor rather than a measurement. Reported in the
    // metadata as the browser gave it rather than multiplied into a byte
    // count that looks precise.
    final num? memoryGb =
        navigator == null ? null : dvJsNum(navigator, 'deviceMemory');
    final num? touchPoints =
        navigator == null ? null : dvJsNum(navigator, 'maxTouchPoints');
    final Map<String, num> storage = await _storage();

    Map<String, Object?> capability(
      String id,
      String label,
      bool available,
      Map<String, String> metadata,
    ) =>
        <String, Object?>{
          'id': id,
          'label': label,
          'available': available,
          'metadata': metadata,
        };

    return <String, Object?>{
      'deviceId': deviceId(),
      'capabilities': <Map<String, Object?>>[
        capability('cpu.cores', 'Processor cores', cores != null,
            <String, String>{if (cores != null) 'count': '$cores'}),
        capability('memory', 'Memory', memoryGb != null, <String, String>{
          if (memoryGb != null) 'approximateGb': '$memoryGb',
          if (memoryGb == null)
            'note': 'this browser does not report how much memory the machine '
                'has',
        }),
        capability('storage', 'Storage', storage.isNotEmpty, <String, String>{
          for (final MapEntry<String, num> entry in storage.entries)
            entry.key: '${entry.value}',
        }),
        capability('os', 'Operating system', true, <String, String>{
          'userAgent': web.window.navigator.userAgent,
          'language': web.window.navigator.language,
        }),
        capability('display', 'Display', true, <String, String>{
          'width': '${web.window.screen.width}',
          'height': '${web.window.screen.height}',
          'devicePixelRatio': '${web.window.devicePixelRatio}',
        }),
        capability(
          'touch',
          'Touchscreen',
          (touchPoints ?? 0) > 0,
          <String, String>{
            if (touchPoints != null) 'maxTouchPoints': '$touchPoints',
          },
        ),
        capability('bindings', 'Native bindings', true, <String, String>{
          'registered': DVNativeBridge.registered.join(','),
        }),
      ],
    };
  }

  /// Whether this tab is in a state worth continuing in.
  ///
  /// Three things a browser will actually say, and each one is a real way for
  /// a web application to stop working:
  ///
  ///   * storage nearly at quota, after which every write throws and the
  ///     failure surfaces somewhere unrelated;
  ///   * a battery under five per cent and not charging, which is a device
  ///     about to go dark mid-transaction;
  ///   * offline, which is the whole application for anything server-backed.
  ///
  /// Where the browser withholds a number the check it feeds is skipped
  /// rather than defaulted. Treating an unknown battery as empty would put
  /// every desktop into an unhealthy state for ever.
  static Future<Map<String, Object?>> health() async {
    final Map<String, num> storage = await _storage();
    final Map<String, Object?> battery = await _battery();
    final JSObject? navigator = dvNavigator;
    final JSObject? connection =
        navigator == null ? null : dvJsObject(navigator, 'connection');
    final bool online =
        navigator == null || dvJsValue(navigator, 'onLine').dartify() != false;

    final num? quota = storage['quotaBytes'];
    final num? usage = storage['usageBytes'];
    final bool storageTight =
        quota != null && usage != null && quota > 0 && usage > quota * 0.95;

    final Object? level = battery['batteryLevel'];
    final bool batteryCritical = level is num &&
        level < 0.05 &&
        battery['batteryCharging'] == false;

    return <String, Object?>{
      'healthy': online && !storageTight && !batteryCritical,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'diagnostics': <String, String>{
        'online': '$online',
        for (final MapEntry<String, num> entry in storage.entries)
          entry.key: '${entry.value}',
        for (final MapEntry<String, Object?> entry in battery.entries)
          entry.key: '${entry.value}',
        if (connection != null) ...<String, String>{
          if (dvJsString(connection, 'effectiveType') != null)
            'networkType': dvJsString(connection, 'effectiveType')!,
          if (dvJsNum(connection, 'downlink') != null)
            'downlinkMbps': '${dvJsNum(connection, 'downlink')}',
          if (dvJsNum(connection, 'rtt') != null)
            'rttMs': '${dvJsNum(connection, 'rtt')}',
        },
        // Named so a reader of a bundle knows the gaps are the browser's
        // rather than a binding that failed halfway.
        'source': 'browser',
      },
    };
  }

  /// The bundle a fleet asks for when a tab is misbehaving.
  ///
  /// There are no logs: a page cannot read its own console, and inventing an
  /// empty `recent` entry would read as an application with nothing to
  /// report. What it has instead is the manifest, the address it is running
  /// at and what the browser says it is, which is what actually answers "why
  /// does it only break for that one person".
  static Future<Map<String, Object?>> diagnostics() async {
    final Map<String, Object?> current = await health();
    return <String, Object?>{
      'deviceId': deviceId(),
      'logs': <String, String>{
        'manifest': jsonEncode(await manifest()),
        'userAgent': web.window.navigator.userAgent,
        'url': web.window.location.href,
        'displayMode': web.window.matchMedia('(display-mode: standalone)').matches
            ? 'standalone'
            : 'browser',
      },
      'metrics': <String, String>{
        ...(current['diagnostics']! as Map<String, String>),
        'healthy': '${current['healthy']}',
      },
    };
  }

  /// The storage estimate, or an empty map where the browser has none.
  static Future<Map<String, num>> _storage() async {
    final JSObject? navigator = dvNavigator;
    final JSObject? storage =
        navigator == null ? null : dvJsObject(navigator, 'storage');
    if (storage == null || dvJsMethod(storage, 'estimate') == null) {
      return const <String, num>{};
    }
    try {
      final JSAny? result = await dvJsCall(storage, 'estimate');
      if (result == null || !result.isA<JSObject>()) {
        return const <String, num>{};
      }
      final JSObject estimate = result as JSObject;
      final num? quota = dvJsNum(estimate, 'quota');
      final num? usage = dvJsNum(estimate, 'usage');
      return <String, num>{
        if (quota != null) 'quotaBytes': quota,
        if (usage != null) 'usageBytes': usage,
      };
    } on Object {
      return const <String, num>{};
    }
  }

  /// The battery, where the browser has the API.
  ///
  /// Firefox and Safari removed it, so most of the time this is empty. The
  /// keys are absent rather than zero for exactly that reason: a laptop with
  /// no reading and a laptop about to die must not look the same.
  static Future<Map<String, Object?>> _battery() async {
    final JSObject? navigator = dvNavigator;
    if (navigator == null || dvJsMethod(navigator, 'getBattery') == null) {
      return const <String, Object?>{};
    }
    try {
      final JSAny? result = await dvJsCall(navigator, 'getBattery');
      if (result == null || !result.isA<JSObject>()) {
        return const <String, Object?>{};
      }
      final JSObject battery = result as JSObject;
      final num? level = dvJsNum(battery, 'level');
      final Object? charging = dvJsValue(battery, 'charging').dartify();
      return <String, Object?>{
        if (level != null) 'batteryLevel': level,
        if (charging is bool) 'batteryCharging': charging,
      };
    } on Object {
      return const <String, Object?>{};
    }
  }
}
