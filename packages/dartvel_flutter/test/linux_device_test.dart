import 'dart:async';
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
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_device.dart';
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
      final Process listener = await Process.start('python3', <String>[
        '-c',
        'import socket,sys; s=socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM); s.bind(sys.argv[1]); print("ready", flush=True); print(s.recv(4096).decode(), flush=True)',
        socketPath,
      ]);
      final Stream<String> lines = listener.stdout.transform(const SystemEncoding().decoder).transform(const LineSplitter());
      final List<String> seen = <String>[];
      final Completer<void> ready = Completer<void>();
      final Future<void> done = lines.forEach((String line) {
        seen.add(line);
        if (line == 'ready' && !ready.isCompleted) ready.complete();
      });
      await ready.future.timeout(const Duration(seconds: 10));
      DVLinuxDevice.notifySocket = socketPath;
      addTearDown(() => DVLinuxDevice.notifySocket = null);
      await DV.Platform.device.armWatchdog(timeout: const Duration(seconds: 5), reason: 'startup');
      await DV.Platform.device.heartbeat();
      await done.timeout(const Duration(seconds: 5));
      listener.kill();
      expect(seen, contains('ready'));
      expect(seen, contains('WATCHDOG=1'));
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
}
