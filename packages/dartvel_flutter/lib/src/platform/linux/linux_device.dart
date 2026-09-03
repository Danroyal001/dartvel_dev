/// Device APIs on Linux: how the shared runtime reads its numbers here.
///
/// Linux tells most of this through procfs and sysfs, so these probes read
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

import 'package:ffi/ffi.dart';

import '../device_runtime.dart';

export '../device_runtime.dart' show DVDeviceProbes, DVDeviceRuntime;

typedef _SocketN = Int32 Function(Int32, Int32, Int32);
typedef _SocketD = int Function(int, int, int);
typedef _SendToN = IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int32, Pointer<Uint8>, Uint32);
typedef _SendToD = int Function(int, Pointer<Uint8>, int, int, Pointer<Uint8>, int);
typedef _CloseN = Int32 Function(Int32);
typedef _CloseD = int Function(int);

class DVLinuxDeviceProbes extends DVDeviceProbes {
  const DVLinuxDeviceProbes();

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

  @override
  Map<String, int> memory() {
    final Map<String, int> mem = _meminfo();
    return <String, int>{'totalBytes': mem['MemTotal'] ?? 0, 'availableBytes': mem['MemAvailable'] ?? 0};
  }

  @override
  double uptimeSeconds() {
    final File f = File('/proc/uptime');
    if (!f.existsSync()) return 0;
    return double.tryParse(f.readAsStringSync().split(' ').first) ?? 0;
  }

  @override
  List<String> load() {
    final File f = File('/proc/loadavg');
    return f.existsSync() ? f.readAsStringSync().split(' ') : const <String>['0', '0', '0'];
  }

  @override
  int diskFreeBytes(String path) {
    try {
      final ProcessResult r = Process.runSync('df', <String>['-B1', '--output=avail', path]);
      final List<String> lines = '${r.stdout}'.trim().split('\n');
      return int.tryParse(lines.last.trim()) ?? 0;
    } on ProcessException {
      return 0;
    }
  }

  @override
  String? temperatureC() {
    final File thermal = File('/sys/class/thermal/thermal_zone0/temp');
    if (!thermal.existsSync()) return null;
    final int? milli = int.tryParse(thermal.readAsStringSync().trim());
    return milli == null ? null : (milli / 1000).toStringAsFixed(1);
  }

  @override
  bool hasTouch() {
    final Directory input = Directory('/sys/class/input');
    if (!input.existsSync()) return false;
    for (final FileSystemEntity e in input.listSync()) {
      final File name = File('${e.path}/device/name');
      if (name.existsSync() && name.readAsStringSync().toLowerCase().contains('touch')) return true;
    }
    return false;
  }

  @override
  bool hasDisplay() =>
      (Platform.environment['DISPLAY'] ?? '').isNotEmpty || (Platform.environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;

  @override
  String displayServer() => (Platform.environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty ? 'wayland' : 'x11';

  @override
  void notify(String state) {
    final String? socket = DVLinuxDevice.notifySocket ?? Platform.environment['NOTIFY_SOCKET'];
    if (socket != null && socket.isNotEmpty) _sdNotify(socket, state);
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
}

/// The Linux device bindings: the shared runtime reading through
/// [DVLinuxDeviceProbes]. The statics forward, so what the Linux bindings
/// and their tests call is unchanged.
class DVLinuxDevice {
  const DVLinuxDevice._();

  static const Set<String> implemented = DVDeviceRuntime.implemented;

  /// The systemd notify socket, or null to read NOTIFY_SOCKET.
  static String? notifySocket;

  static String? get stateDirectory => DVDeviceRuntime.stateDirectory;
  static set stateDirectory(String? value) => DVDeviceRuntime.stateDirectory = value;

  static void Function(String reason) get restart => DVDeviceRuntime.restart;
  static set restart(void Function(String reason) value) => DVDeviceRuntime.restart = value;

  static void Function(String finding)? get onRestartLoop => DVDeviceRuntime.onRestartLoop;
  static set onRestartLoop(void Function(String finding)? value) => DVDeviceRuntime.onRestartLoop = value;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    DVDeviceRuntime.probes = const DVLinuxDeviceProbes();
    DVDeviceRuntime.register(bind);
  }

  static void unregister() => DVDeviceRuntime.unregister();
  static void resetWatchdogForTest() => DVDeviceRuntime.resetWatchdogForTest();
  static String deviceId() => DVDeviceRuntime.deviceId();
  static Map<String, Object?> manifest() => DVDeviceRuntime.manifest();
  static Map<String, Object?> health() => DVDeviceRuntime.health();
  static bool verdict({required int memoryAvailableBytes, required int memoryTotalBytes, required int diskFreeBytes}) =>
      DVDeviceRuntime.verdict(
          memoryAvailableBytes: memoryAvailableBytes, memoryTotalBytes: memoryTotalBytes, diskFreeBytes: diskFreeBytes);
  static void recordRestart(DateTime at) => DVDeviceRuntime.recordRestart(at);
  static bool restartLoopDetected({required Duration within, required int more}) =>
      DVDeviceRuntime.restartLoopDetected(within: within, more: more);
  static void arm(Duration timeout, {required String reason}) => DVDeviceRuntime.arm(timeout, reason: reason);
  static void heartbeat() => DVDeviceRuntime.heartbeat();
  static Map<String, Object?> provision(Map<Object?, Object?> request) => DVDeviceRuntime.provision(request);
  static Map<String, Object?> diagnostics() => DVDeviceRuntime.diagnostics();
}
