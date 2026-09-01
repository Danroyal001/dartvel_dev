// The lock, between two real processes.
//
// The in-process guard in DVSingleInstance would satisfy every same-process
// assertion on its own, so a suite that only ran in one process would pass
// with the file lock removed entirely -- and the file lock is the whole
// feature. A second launch of an application is a second *process*.
//
// So this one spawns them, and it is the test that would catch the lock being
// silently broken.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/src/windowing/single_instance.dart';
import 'package:test/test.dart';

/// Tries to take the lock, reports what it got, and exits.
const String _probe = r'''
import 'dart:io';
import 'package:dartvel_core/src/windowing/single_instance.dart';

void main(List<String> args) {
  final lock = DVSingleInstance.acquire(args[0]);
  if (!lock.isPrimary && args.length > 1) lock.send(args[1]);
  stdout.write(lock.isPrimary ? 'primary' : 'secondary');
  lock.release();
}
''';

/// Takes the lock, says so, and holds it until killed.
const String _holder = r'''
import 'dart:io';
import 'package:dartvel_core/src/windowing/single_instance.dart';

Future<void> main(List<String> args) async {
  final lock = DVSingleInstance.acquire(args[0]);
  stdout.writeln(lock.isPrimary ? 'primary' : 'secondary');
  await Future<void>.delayed(const Duration(seconds: 60));
}
''';

void main() {
  late Directory dir;
  late String probe;
  late String holder;

  // The suite's own resolution, so a child process sees dartvel_core.
  final String packages =
      '${Directory.current.path}/.dart_tool/package_config.json';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dv_lock_proc_');
    probe = '${dir.path}/probe.dart';
    holder = '${dir.path}/holder.dart';
    File(probe).writeAsStringSync(_probe);
    File(holder).writeAsStringSync(_holder);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Runs the probe against [lockPath], returning what it reported.
  Future<String> probeLock(String lockPath, [String? route]) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'run',
        '--packages=$packages',
        probe,
        lockPath,
        if (route != null) route,
      ],
    );
    if (result.exitCode != 0) fail('probe failed: ${result.stderr}');
    return '${result.stdout}'.trim();
  }

  test('a second process is refused while the first holds the lock', () async {
    final String path = '${dir.path}/app.lock';
    final DVInstanceLock held = DVSingleInstance.acquire(path);
    addTearDown(held.release);
    expect(held.isPrimary, isTrue);

    expect(await probeLock(path), 'secondary');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a second process gets the lock once the first releases', () async {
    // The property that makes a crash survivable: the lock is not a file that
    // has to be cleaned up, it is state the kernel drops.
    final String path = '${dir.path}/app.lock';
    DVSingleInstance.acquire(path).release();

    expect(await probeLock(path), 'primary');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the refused process hands over the route it was launched with',
      () async {
    // The point of the whole mechanism: a deep link arriving at a second
    // launch reaches the running application.
    final String path = '${dir.path}/app.lock';
    final DVInstanceLock primary = DVSingleInstance.acquire(path);
    addTearDown(primary.release);

    expect(await probeLock(path, '/orders/42'), 'secondary');
    expect(primary.takePending(), <String>['/orders/42']);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a killed holder does not keep the lock', () async {
    // The failure a pid file has and an advisory lock does not: SIGKILL gives
    // the process no chance to clean up, and the application must still be
    // able to start afterwards.
    final String path = '${dir.path}/app.lock';

    final Process process = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', '--packages=$packages', holder, path],
    );
    addTearDown(() => process.kill(ProcessSignal.sigkill));

    final String first = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((String line) => line.trim().isNotEmpty)
        .timeout(const Duration(seconds: 90));
    expect(first.trim(), 'primary');

    expect(await probeLock(path), 'secondary',
        reason: 'the holder is still alive');

    process.kill(ProcessSignal.sigkill);
    await process.exitCode;

    expect(await probeLock(path), 'primary',
        reason: 'an advisory lock is dropped when the holder dies, however it '
            'dies -- which is why this is not a pid file');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
