/// The device APIs every desktop shares: the capability manifest, health,
/// the watchdog, provisioning and diagnostics.
///
/// What differs per platform is how the numbers are read -- procfs and sysfs
/// on Linux, Win32 on Windows, sysctl and Mach on macOS -- and that is all a
/// [DVDeviceProbes] supplies. Identity, the verdict, the watchdog and its
/// restart-loop detection, provisioning and the diagnostics bundle are the
/// same everywhere, so they live once, here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../dartvel_flutter.dart' show DVNativeBridge;

/// What a platform reads for the manifest and health.
abstract class DVDeviceProbes {
  const DVDeviceProbes();

  /// `totalBytes` and `availableBytes`; zero where unknown.
  Map<String, int> memory();
  double uptimeSeconds();

  /// One-, five- and fifteen-minute load, where the platform keeps one.
  List<String> load() => const <String>['0', '0', '0'];
  int diskFreeBytes(String path);
  String? temperatureC() => null;
  bool hasTouch();
  bool hasDisplay();
  String displayServer();

  /// A word to the supervisor, where there is one to tell (sd_notify).
  void notify(String state) {}
}

class DVDeviceRuntime {
  const DVDeviceRuntime._();

  static const Set<String> implemented = <String>{
    'device.capabilityManifest',
    'device.health',
    'device.watchdog.arm',
    'device.watchdog.heartbeat',
    'device.fleet.provision',
    'device.diagnostics.collect',
  };

  /// How this platform reads its numbers. Set by the platform's bindings
  /// before [register].
  static DVDeviceProbes probes = const _NoProbes();

  /// Where the device id, provisioning and restart record live. Null means
  /// `~/.dartvel/device`.
  static String? stateDirectory;

  /// What a missed heartbeat does. Exits 70 by default -- EX_SOFTWARE, so a
  /// supervisor with restart-on-failure starts the app again.
  static void Function(String reason) restart = _exitForSupervisor;

  /// Called when a restart loop is detected instead of restarting again
  /// (DV-KIOSK-008). The app shows its diagnostics screen from here.
  static void Function(String finding)? onRestartLoop;

  static Timer? _watchdog;
  static Duration? _watchdogTimeout;

  static void _exitForSupervisor(String reason) {
    debugPrint('[dartvel] $reason; exiting for the supervisor to restart.');
    exit(70);
  }

  static String get _dir {
    final String dir = stateDirectory ??
        '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path}/.dartvel/device';
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    bind('device.capabilityManifest', (Object? _) => manifest());
    bind('device.health', (Object? _) => health());
    bind('device.watchdog.arm', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      final int ms = m['timeoutMs'] is int ? m['timeoutMs']! as int : 10000;
      arm(Duration(milliseconds: ms), reason: '${m['reason'] ?? 'startup'}');
      return true;
    });
    bind('device.watchdog.heartbeat', (Object? _) {
      heartbeat();
      return true;
    });
    bind('device.fleet.provision', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      return provision(m);
    });
    bind('device.diagnostics.collect', (Object? _) => diagnostics());
  }

  static void unregister() => resetWatchdogForTest();

  /// Cancels the watchdog and forgets its state. For tests.
  static void resetWatchdogForTest() {
    _watchdog?.cancel();
    _watchdog = null;
    _watchdogTimeout = null;
  }

  // --- identity ------------------------------------------------------------

  static Map<String, Object?>? _provisioning() {
    final File f = File('$_dir/provisioning.json');
    if (!f.existsSync()) return null;
    try {
      final Object? decoded = jsonDecode(f.readAsStringSync());
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  /// The provisioned id, else one generated once and kept.
  static String deviceId() {
    final Object? provisioned = _provisioning()?['deviceId'];
    if (provisioned is String && provisioned.isNotEmpty) return provisioned;
    final File f = File('$_dir/device-id');
    if (f.existsSync()) {
      final String id = f.readAsStringSync().trim();
      if (id.isNotEmpty) return id;
    }
    final Random r = Random.secure();
    final String id = List<String>.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    f.writeAsStringSync(id);
    return id;
  }

  // --- manifest and health -------------------------------------------------

  static String get arch =>
      Platform.version.contains('arm64') || Platform.version.contains('aarch64') ? 'arm64' : 'x64';

  static Map<String, Object?> manifest() {
    final Map<String, int> mem = probes.memory();
    Map<String, Object?> cap(String id, String label, bool available, Map<String, String> metadata) =>
        <String, Object?>{'id': id, 'label': label, 'available': available, 'metadata': metadata};
    return <String, Object?>{
      'deviceId': deviceId(),
      'capabilities': <Map<String, Object?>>[
        cap('cpu.cores', 'Processor cores', true, <String, String>{'count': '${Platform.numberOfProcessors}'}),
        cap('memory', 'Memory', (mem['totalBytes'] ?? 0) > 0, <String, String>{
          'totalBytes': '${mem['totalBytes'] ?? 0}',
          'availableBytes': '${mem['availableBytes'] ?? 0}',
        }),
        cap('os', 'Operating system', true, <String, String>{
          'kernel': Platform.operatingSystemVersion,
          'arch': arch,
        }),
        cap('display', 'Display', probes.hasDisplay(), <String, String>{'server': probes.displayServer()}),
        cap('touch', 'Touchscreen', probes.hasTouch(), const <String, String>{}),
        cap('bindings', 'Native bindings', true, <String, String>{'registered': DVNativeBridge.registered.join(',')}),
      ],
    };
  }

  /// Healthy unless memory or disk is nearly gone: under 5% of memory free,
  /// or under 200 MB of disk.
  static bool verdict({required int memoryAvailableBytes, required int memoryTotalBytes, required int diskFreeBytes}) {
    if (memoryTotalBytes > 0 && memoryAvailableBytes < memoryTotalBytes * 0.05) return false;
    if (diskFreeBytes < 200 << 20) return false;
    return true;
  }

  static Map<String, Object?> health() {
    final Map<String, int> mem = probes.memory();
    final List<String> load = probes.load();
    final int disk = probes.diskFreeBytes(_dir);
    final String? temperature = probes.temperatureC();
    return <String, Object?>{
      'healthy': verdict(
        memoryAvailableBytes: mem['availableBytes'] ?? 0,
        memoryTotalBytes: mem['totalBytes'] ?? 0,
        diskFreeBytes: disk,
      ),
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'diagnostics': <String, String>{
        'uptimeSeconds': _plain(probes.uptimeSeconds()),
        'load1': load.isNotEmpty ? load[0] : '0',
        'load5': load.length > 1 ? load[1] : '0',
        'memoryAvailableBytes': '${mem['availableBytes'] ?? 0}',
        'memoryTotalBytes': '${mem['totalBytes'] ?? 0}',
        'diskFreeBytes': '$disk',
        if (temperature != null) 'temperatureC': temperature,
        'watchdog': _watchdog == null ? 'off' : 'armed ${_watchdogTimeout!.inMilliseconds}ms',
      },
    };
  }

  /// Seconds without a trailing `.0` for a whole number, which is how procfs
  /// spells it and what readers of the Linux field already parse.
  static String _plain(double seconds) =>
      seconds == seconds.roundToDouble() ? '${seconds.round()}' : seconds.toStringAsFixed(2);

  // --- watchdog --------------------------------------------------------------

  static File get _restarts => File('$_dir/restarts');

  static void recordRestart(DateTime at) =>
      _restarts.writeAsStringSync('${at.toUtc().toIso8601String()}\n', mode: FileMode.append);

  /// More than [more] restarts inside [within]: the loop the spec names.
  static bool restartLoopDetected({required Duration within, required int more}) {
    if (!_restarts.existsSync()) return false;
    final DateTime since = DateTime.now().toUtc().subtract(within);
    int recent = 0;
    for (final String line in _restarts.readAsLinesSync()) {
      final DateTime? at = DateTime.tryParse(line.trim());
      if (at != null && at.isAfter(since)) recent++;
    }
    return recent > more;
  }

  /// Arms the watchdog: a heartbeat must arrive within [timeout], every
  /// time, or [restart] runs. A `startup` arm is a boot, and a boot that is
  /// the fourth in five minutes is a loop, reported rather than restarted.
  static void arm(Duration timeout, {required String reason}) {
    if (reason == 'startup') {
      recordRestart(DateTime.now());
      if (restartLoopDetected(within: const Duration(minutes: 5), more: 3)) {
        const String finding = 'DV-KIOSK-008: restarted more than three times in five minutes; '
            'holding at the diagnostics screen instead of restarting again.';
        debugPrint('[dartvel] $finding');
        onRestartLoop?.call(finding);
        return;
      }
    }
    _watchdogTimeout = timeout;
    _rearm();
  }

  static void _rearm() {
    _watchdog?.cancel();
    final Duration? timeout = _watchdogTimeout;
    if (timeout == null) return;
    _watchdog = Timer(timeout, () {
      _watchdog = null;
      restart('watchdog: no heartbeat within ${timeout.inMilliseconds}ms');
    });
  }

  static void heartbeat() {
    if (_watchdogTimeout != null) _rearm();
    probes.notify('WATCHDOG=1');
  }

  // --- provisioning and diagnostics ----------------------------------------

  static Map<String, Object?> provision(Map<Object?, Object?> request) {
    final Map<String, Object?> record = <String, Object?>{
      'deviceId': '${request['deviceId'] ?? deviceId()}',
      'fleetId': '${request['fleetId'] ?? ''}',
      'labels': request['labels'] is Map
          ? (request['labels']! as Map).map((Object? k, Object? v) => MapEntry<String, String>('$k', '$v'))
          : const <String, String>{},
      'provisionedAt': DateTime.now().toUtc().toIso8601String(),
    };
    File('$_dir/provisioning.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(record));
    return <String, Object?>{
      'deviceId': record['deviceId'],
      'fleetId': record['fleetId'],
      'provisioned': true,
    };
  }

  static Map<String, Object?> diagnostics() {
    final Map<String, Object?> h = health();
    final Map<String, Object?>? p = _provisioning();
    final File log = File('$_dir/app.log');
    final String recentLog = log.existsSync()
        ? (log.readAsLinesSync().reversed.take(200).toList().reversed).join('\n')
        : '';
    return <String, Object?>{
      'deviceId': deviceId(),
      'logs': <String, String>{
        'manifest': jsonEncode(manifest()),
        'provisioning': p == null ? '' : jsonEncode(p),
        'restarts': _restarts.existsSync() ? _restarts.readAsStringSync() : '',
        'recent': recentLog,
      },
      'metrics': (h['diagnostics']! as Map<String, String>),
    };
  }
}

/// Before a platform has said how it reads: nothing known, nothing claimed.
class _NoProbes extends DVDeviceProbes {
  const _NoProbes();
  @override
  Map<String, int> memory() => const <String, int>{};
  @override
  double uptimeSeconds() => 0;
  @override
  int diskFreeBytes(String path) => 0;
  @override
  bool hasTouch() => false;
  @override
  bool hasDisplay() => false;
  @override
  String displayServer() => 'none';
}
