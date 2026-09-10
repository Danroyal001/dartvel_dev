import 'dart:convert';
// Device APIs on Linux: the capability manifest, health, the watchdog,
// provisioning and diagnostics -- what a kiosk or an embedded device
// reports about itself and how it stays alive.
//
// Linux tells most of this through procfs and sysfs, so the bindings read
// files rather than call libraries, and every one of them runs on a CI
// runner. What the tests hold to: the manifest names the bindings that are
// actually registered and the hardware it can measure; health is a
// verdict with the numbers behind it; the watchdog restarts on a missed
// heartbeat and notices a restart loop rather than looping forever;
// provisioning is remembered across starts; diagnostics bundle the lot.
import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_device.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  setUpAll(() {
    home = Directory.systemTemp.createTempSync('dv_device_');
    DVLinuxDevice.stateDirectory = home.path;
    expect(DVLinuxBindings.register(), isTrue);
  });
  tearDownAll(() {
    DVLinuxBindings.unregister();
    DVLinuxDevice.stateDirectory = null;
    home.deleteSync(recursive: true);
  });

  test('the device bindings are among what the Linux bindings implement', () {
    expect(DVLinuxBindings.implemented, containsAll(<String>[
      'device.capabilityManifest',
      'device.health',
      'device.watchdog.arm',
      'device.watchdog.heartbeat',
      'device.fleet.provision',
      'device.diagnostics.collect',
    ]));
  });

  group('the capability manifest', () {
    test('names this machine and what it can do', () async {
      final DVHardwareCapabilityManifest m = await DV.Platform.device.capabilityManifest();
      expect(m.deviceId, isNotEmpty);
      final Map<String, DVHardwareCapability> byName = <String, DVHardwareCapability>{
        for (final DVHardwareCapability c in m.capabilities) c.id: c,
      };
      expect(byName['cpu.cores']!.available, isTrue);
      expect(int.parse(byName['cpu.cores']!.metadata['count']!), Platform.numberOfProcessors);
      expect(byName['memory']!.available, isTrue);
      expect(int.parse(byName['memory']!.metadata['totalBytes']!), greaterThan(0));
      expect(byName['os']!.metadata['kernel'], isNotEmpty);
      expect(byName['display']!.available, (Platform.environment['DISPLAY'] ?? '').isNotEmpty);
    });

    test('lists the bindings that are actually registered, not the names declared', () async {
      final DVHardwareCapabilityManifest m = await DV.Platform.device.capabilityManifest();
      final DVHardwareCapability bindings = m.capabilities.singleWhere((DVHardwareCapability c) => c.id == 'bindings');
      final List<String> names = bindings.metadata['registered']!.split(',');
      expect(names, containsAll(<String>['clipboard.copy', 'printing.toFile', 'device.health']));
      expect(names, isNot(contains('camera.takePhoto')), reason: 'no Linux camera binding exists');
    });

    test('the device id is stable across calls and starts', () async {
      final String a = (await DV.Platform.device.capabilityManifest()).deviceId;
      final String b = (await DV.Platform.device.capabilityManifest()).deviceId;
      expect(a, b);
      expect(File('${home.path}/device-id').readAsStringSync().trim(), a);
    });
  });

  group('health', () {
    test('is a verdict with the numbers behind it', () async {
      final DVDeviceHealth h = await DV.Platform.device.health();
      expect(h.healthy, isTrue);
      expect(h.checkedAt.difference(DateTime.now()).abs(), lessThan(const Duration(minutes: 1)));
      expect(double.parse(h.diagnostics['uptimeSeconds']!), greaterThan(0));
      expect(double.parse(h.diagnostics['load1']!), greaterThanOrEqualTo(0));
      expect(int.parse(h.diagnostics['memoryAvailableBytes']!), greaterThan(0));
      expect(int.parse(h.diagnostics['diskFreeBytes']!), greaterThan(0));
    });

    test('is unhealthy when memory or disk is nearly gone', () {
      expect(DVLinuxDevice.verdict(memoryAvailableBytes: 10 << 20, memoryTotalBytes: 8 << 30, diskFreeBytes: 50 << 30), isFalse);
      expect(DVLinuxDevice.verdict(memoryAvailableBytes: 4 << 30, memoryTotalBytes: 8 << 30, diskFreeBytes: 100 << 20), isFalse);
      expect(DVLinuxDevice.verdict(memoryAvailableBytes: 4 << 30, memoryTotalBytes: 8 << 30, diskFreeBytes: 50 << 30), isTrue);
    });
  });

  group('the watchdog', () {
    late List<String> restarts;
    setUp(() {
      restarts = <String>[];
      DVLinuxDevice.restart = (String reason) => restarts.add(reason);
      DVLinuxDevice.resetWatchdogForTest();
    });
    tearDown(DVLinuxDevice.resetWatchdogForTest);

    test('a heartbeat within the timeout keeps the app alive; a missed one restarts it', () async {
      await DV.Platform.device.armWatchdog(timeout: const Duration(milliseconds: 120), reason: 'startup');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await DV.Platform.device.heartbeat();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await DV.Platform.device.heartbeat();
      expect(restarts, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(restarts, <String>['watchdog: no heartbeat within 120ms']);
    });

    test('a restart loop is noticed rather than looped', () async {
      // Three restarts inside the window is the loop the spec names; the
      // fourth arm reports it (DV-KIOSK-008) instead of restarting again.
      for (int i = 0; i < 3; i++) {
        DVLinuxDevice.recordRestart(DateTime.now());
      }
      final bool looping = DVLinuxDevice.restartLoopDetected(within: const Duration(minutes: 5), more: 2);
      expect(looping, isTrue);
      expect(DVLinuxDevice.restartLoopDetected(within: const Duration(minutes: 5), more: 5), isFalse);
    });

    test('with systemd watching, a heartbeat tells it so', () async {
      // sd_notify's protocol: a datagram on the socket NOTIFY_SOCKET names.
      // A tiny listener stands in for systemd.
      final String socketPath = '${home.path}/notify.sock';
      final _NotifySocket listener = _NotifySocket.bind(socketPath);
      addTearDown(listener.close);
      DVLinuxDevice.notifySocket = socketPath;
      addTearDown(() => DVLinuxDevice.notifySocket = null);
      await DV.Platform.device.armWatchdog(timeout: const Duration(seconds: 5), reason: 'startup');
      await DV.Platform.device.heartbeat();
      expect(await listener.receive(const Duration(seconds: 5)), 'WATCHDOG=1');
    });
  });

  group('provisioning and diagnostics', () {
    test('provisioning is remembered, and the manifest carries it', () async {
      final DVDeviceProvisioningResult r = await DV.Platform.device.provision(
        const DVFleetProvisioningRequest(deviceId: 'kiosk-1', fleetId: 'storefront', labels: <String, String>{'zone': 'front'}),
      );
      expect(r.provisioned, isTrue);
      expect(r.deviceId, 'kiosk-1');
      expect(r.fleetId, 'storefront');
      expect(File('${home.path}/provisioning.json').existsSync(), isTrue);
      final DVHardwareCapabilityManifest m = await DV.Platform.device.capabilityManifest();
      expect(m.deviceId, 'kiosk-1', reason: 'a provisioned id replaces the generated one');
    });

    test('diagnostics bundle the manifest, health and recent log', () async {
      final DVDeviceDiagnosticsBundle d = await DV.Platform.device.collectDiagnostics();
      expect(d.deviceId, isNotEmpty);
      expect(d.metrics.keys, containsAll(<String>['uptimeSeconds', 'memoryAvailableBytes', 'diskFreeBytes']));
      expect(d.logs.keys, containsAll(<String>['manifest', 'provisioning']));
      expect(d.logs['manifest'], contains('cpu.cores'));
    });
  });
  startupInDiagnostics();
}

// A fleet asking why a device is slow to come up is asking for the startup
// profile; a bundle without it sends somebody to the device to find out.
void startupInDiagnostics() {
  test('the diagnostics bundle carries what startup took', () {
    DVStartupProfile.current
      ..reset()
      ..mark('configure')
      ..mark('first frame');

    final Map<String, Object?> bundle = DVLinuxDevice.diagnostics();
    final Map<String, String> logs = (bundle['logs']! as Map).cast<String, String>();
    final Map<String, String> metrics = (bundle['metrics']! as Map).cast<String, String>();

    expect(logs['startup'], contains('first frame'));
    expect(int.parse(metrics['startupMicros']!), greaterThan(0));
  });
}

// A systemd standing in for systemd: an AF_UNIX datagram socket, which is
// what NOTIFY_SOCKET names and what sd_notify writes one message to.
//
// Over libc rather than dart:io because `RawDatagramSocket.bind` refuses
// anything but an IPv4 or IPv6 address -- Dart has unix sockets for streams
// and not for datagrams. This used to be a `python3 -c` one-liner, which
// worked and put Python in a repository whose whole tooling rule is that
// there is none.
typedef _SocketNative = Int32 Function(Int32, Int32, Int32);
typedef _SocketDart = int Function(int, int, int);
typedef _BindNative = Int32 Function(Int32, Pointer<Uint8>, Uint32);
typedef _BindDart = int Function(int, Pointer<Uint8>, int);
typedef _RecvNative = IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int32);
typedef _RecvDart = int Function(int, Pointer<Uint8>, int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

class _NotifySocket {
  _NotifySocket._(this._fd, this._path);

  static const int _afUnix = 1;
  static const int _sockDgram = 2;

  /// Return without waiting when there is nothing to read. A blocking recv on
  /// the isolate running the test would stop the very code that is supposed
  /// to send the datagram.
  static const int _dontWait = 0x40;

  final int _fd;
  final String _path;

  static final DynamicLibrary _libc = DynamicLibrary.process();

  static _NotifySocket bind(String path) {
    final int fd = _libc.lookupFunction<_SocketNative, _SocketDart>('socket')(_afUnix, _sockDgram, 0);
    expect(fd, greaterThanOrEqualTo(0), reason: 'socket(AF_UNIX, SOCK_DGRAM)');
    final List<int> bytes = utf8.encode(path);
    // sockaddr_un: two bytes of family, then the path, then a terminator.
    final Pointer<Uint8> address = calloc<Uint8>(110);
    try {
      address[0] = _afUnix;
      address[1] = 0;
      for (int i = 0; i < bytes.length && i < 107; i++) {
        address[2 + i] = bytes[i];
      }
      final int bound = _libc.lookupFunction<_BindNative, _BindDart>('bind')(fd, address, 2 + bytes.length + 1);
      expect(bound, 0, reason: 'bind($path)');
    } finally {
      calloc.free(address);
    }
    return _NotifySocket._(fd, path);
  }

  /// The first datagram to arrive within [within].
  ///
  /// Polled rather than awaited: there is no way to wait on a raw descriptor
  /// from Dart, and the sender is in this same isolate anyway.
  Future<String> receive(Duration within) async {
    final _RecvDart recv = _libc.lookupFunction<_RecvNative, _RecvDart>('recv');
    final Pointer<Uint8> buffer = calloc<Uint8>(4096);
    final DateTime deadline = DateTime.now().add(within);
    try {
      while (DateTime.now().isBefore(deadline)) {
        final int read = recv(_fd, buffer, 4096, _dontWait);
        if (read > 0) {
          return utf8.decode(List<int>.generate(read, (int i) => buffer[i]));
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      calloc.free(buffer);
    }
    return 'nothing arrived within $within';
  }

  void close() {
    _libc.lookupFunction<_CloseNative, _CloseDart>('close')(_fd);
    final File file = File(_path);
    if (file.existsSync()) file.deleteSync();
  }
}
