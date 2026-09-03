/// Device APIs on Linux: the capability manifest, health, the watchdog,
/// provisioning and diagnostics.
///
/// Linux tells most of this through procfs and sysfs, so these bindings read
/// files rather than call libraries; the one native call is sd_notify's
/// datagram, so a systemd unit with WatchdogSec= sees the heartbeat and
/// restarts the app when it stops. Without systemd the watchdog restarts
/// the process itself by exiting non-zero for whatever supervises it -- and
/// counts the restarts, so a loop is noticed rather than looped.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../dartvel_flutter.dart' show DVNativeBridge;

typedef _SocketN = Int32 Function(Int32, Int32, Int32);
typedef _SocketD = int Function(int, int, int);
typedef _SendToN = IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int32, Pointer<Uint8>, Uint32);
typedef _SendToD = int Function(int, Pointer<Uint8>, int, int, Pointer<Uint8>, int);
typedef _CloseN = Int32 Function(Int32);
typedef _CloseD = int Function(int);

class DVLinuxDevice {
  const DVLinuxDevice._();

  static const Set<String> implemented = <String>{
    'device.capabilityManifest',
    'device.health',
    'device.watchdog.arm',
    'device.watchdog.heartbeat',
    'device.fleet.provision',
    'device.diagnostics.collect',
  };

  /// Where the device id, provisioning and restart record live. Null means
  /// `~/.dartvel/device`.
  static String? stateDirectory;

  /// What a missed heartbeat does. Exits 70 by default -- EX_SOFTWARE, so a
  /// supervisor with restart-on-failure starts the app again.
  static void Function(String reason) restart = _exitForSupervisor;

  /// Called when a restart loop is detected instead of restarting again
  /// (DV-KIOSK-008). The app shows its diagnostics screen from here.
  static void Function(String finding)? onRestartLoop;

  /// The systemd notify socket, or null to read NOTIFY_SOCKET.
  static String? notifySocket;

  static Timer? _watchdog;
  static Duration? _watchdogTimeout;

  static void _exitForSupervisor(String reason) {
    debugPrint('[dartvel] $reason; exiting for the supervisor to restart.');
    exit(70);
  }

  static String get _dir {
    final String dir = stateDirectory ??
        '${Platform.environment['HOME'] ?? Directory.systemTemp.path}/.dartvel/device';
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

  static Map<String, int> _meminfo() {
    final Map<String, int> out = <String, int>{};
    final File f = File('/proc/meminfo');
    if (!f.existsSync()) return out;
    for (final String line in f.readAsLinesSync()) {
      final List<String> parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final int? kb = int.tryParse(parts[1]);
        if (kb != null) out[parts[0].replaceAll(':', '')] = kb * 1024;
      }
    }
    return out;
  }

  static int _diskFreeBytes(String path) {
    try {
      final ProcessResult r = Process.runSync('df', <String>['-B1', '--output=avail', path]);
      final List<String> lines = '${r.stdout}'.trim().split('\n');
      return int.tryParse(lines.last.trim()) ?? 0;
    } on ProcessException {
      return 0;
    }
  }

  static Map<String, Object?> manifest() {
    final Map<String, int> mem = _meminfo();
    final bool display = (Platform.environment['DISPLAY'] ?? '').isNotEmpty ||
        (Platform.environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
    final String arch = Platform.version.contains('arm64') || Platform.version.contains('aarch64') ? 'arm64' : 'x64';
    Map<String, Object?> cap(String id, String label, bool available, Map<String, String> metadata) =>
        <String, Object?>{'id': id, 'label': label, 'available': available, 'metadata': metadata};
    return <String, Object?>{
      'deviceId': deviceId(),
      'capabilities': <Map<String, Object?>>[
        cap('cpu.cores', 'Processor cores', true, <String, String>{'count': '${Platform.numberOfProcessors}'}),
        cap('memory', 'Memory', (mem['MemTotal'] ?? 0) > 0, <String, String>{
          'totalBytes': '${mem['MemTotal'] ?? 0}',
          'availableBytes': '${mem['MemAvailable'] ?? 0}',
        }),
        cap('os', 'Operating system', true, <String, String>{
          'kernel': Platform.operatingSystemVersion,
          'arch': arch,
        }),
        cap('display', 'Display', display, <String, String>{
          'server': (Platform.environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty ? 'wayland' : 'x11',
        }),
        cap('touch', 'Touchscreen', _hasTouch(), const <String, String>{}),
        cap('bindings', 'Native bindings', true, <String, String>{'registered': DVNativeBridge.registered.join(',')}),
      ],
    };
  }

  static bool _hasTouch() {
    final Directory input = Directory('/sys/class/input');
    if (!input.existsSync()) return false;
    for (final FileSystemEntity e in input.listSync()) {
      final File name = File('${e.path}/device/name');
      if (name.existsSync() && name.readAsStringSync().toLowerCase().contains('touch')) return true;
    }
    return false;
  }

  /// Healthy unless memory or disk is nearly gone: under 5% of memory free,
  /// or under 200 MB of disk.
  static bool verdict({required int memoryAvailableBytes, required int memoryTotalBytes, required int diskFreeBytes}) {
    if (memoryTotalBytes > 0 && memoryAvailableBytes < memoryTotalBytes * 0.05) return false;
    if (diskFreeBytes < 200 << 20) return false;
    return true;
  }

  static Map<String, Object?> health() {
    final Map<String, int> mem = _meminfo();
    final String uptime = File('/proc/uptime').existsSync() ? File('/proc/uptime').readAsStringSync().split(' ').first : '0';
    final List<String> load = File('/proc/loadavg').existsSync() ? File('/proc/loadavg').readAsStringSync().split(' ') : <String>['0', '0', '0'];
    final int disk = _diskFreeBytes(_dir);
    String? temperature;
    final File thermal = File('/sys/class/thermal/thermal_zone0/temp');
    if (thermal.existsSync()) {
      final int? milli = int.tryParse(thermal.readAsStringSync().trim());
      if (milli != null) temperature = (milli / 1000).toStringAsFixed(1);
    }
    return <String, Object?>{
      'healthy': verdict(
        memoryAvailableBytes: mem['MemAvailable'] ?? 0,
        memoryTotalBytes: mem['MemTotal'] ?? 0,
        diskFreeBytes: disk,
      ),
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'diagnostics': <String, String>{
        'uptimeSeconds': uptime,
        'load1': load[0],
        'load5': load.length > 1 ? load[1] : '0',
        'memoryAvailableBytes': '${mem['MemAvailable'] ?? 0}',
        'memoryTotalBytes': '${mem['MemTotal'] ?? 0}',
        'diskFreeBytes': '$disk',
        if (temperature != null) 'temperatureC': temperature,
        'watchdog': _watchdog == null ? 'off' : 'armed ${_watchdogTimeout!.inMilliseconds}ms',
      },
    };
  }

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
    final String? socket = notifySocket ?? Platform.environment['NOTIFY_SOCKET'];
    if (socket != null && socket.isNotEmpty) _sdNotify(socket, 'WATCHDOG=1');
  }

  /// sd_notify without libsystemd: one datagram on the unix socket. A
  /// leading `@` names an abstract socket, as systemd documents.
  static void _sdNotify(String socketPath, String state) {
    final DynamicLibrary libc = DynamicLibrary.process();
    final _SocketD socket = libc.lookupFunction<_SocketN, _SocketD>('socket');
    final _SendToD sendTo = libc.lookupFunction<_SendToN, _SendToD>('sendto');
    final _CloseD close = libc.lookupFunction<_CloseN, _CloseD>('close');
    const int afUnix = 1;
    const int sockDgram = 2;
    final int fd = socket(afUnix, sockDgram, 0);
    if (fd < 0) return;
    final List<int> path = utf8.encode(socketPath);
    final Pointer<Uint8> addr = calloc<Uint8>(110);
    final Pointer<Uint8> message = calloc<Uint8>(state.length + 1);
    try {
      addr[0] = afUnix;
      addr[1] = 0;
      for (int i = 0; i < path.length && i < 107; i++) {
        addr[2 + i] = path[i] == 0x40 && i == 0 ? 0 : path[i];
      }
      final List<int> bytes = utf8.encode(state);
      for (int i = 0; i < bytes.length; i++) {
        message[i] = bytes[i];
      }
      sendTo(fd, message, bytes.length, 0, addr, 2 + path.length);
    } finally {
      calloc.free(addr);
      calloc.free(message);
      close(fd);
    }
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
