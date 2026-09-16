/// OTA on a real Android emulator: a release built with Shorebird's engine
/// checks for a patch through `DV.Updates`, applies it, and is the patch on
/// the next launch -- served by Dartvel's own patch source, with no Shorebird
/// account.
///
/// Run by the "OTA updates" workflow inside android-emulator-runner, which
/// runs each line of its script as its own `sh -c`, so everything is here.
/// The step is continue-on-error; the verdict is written to a file a later
/// step reads.
///
/// Expects, from the build step: /tmp/ota/release.apk, /tmp/ota/patch.bin
/// (the diff from the release's libapp.so to the patched one) and
/// /tmp/ota/patched.sha256.
///
/// Imports are `dart:` only.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _package = 'com.example.dartvel_example';
const String _diag = '/tmp/diag';
const String _ota = '/tmp/ota';
const String _appId = 'dartvel-example-ota';

Future<String> _adb(List<String> args) async {
  final ProcessResult result = await Process.run('adb', args);
  if (result.exitCode != 0) {
    throw StateError('adb ${args.join(' ')}: ${result.stderr}${result.stdout}');
  }
  return '${result.stdout}';
}

Future<String> _log() => _adb(<String>['logcat', '-d', '-s', 'flutter:*']);

Future<void> _screenshot(String name) async {
  final ProcessResult shot = await Process.run('adb', <String>[
    'exec-out',
    'screencap',
    '-p',
  ], stdoutEncoding: null);
  if (shot.exitCode == 0) {
    File('$_diag/$name.png').writeAsBytesSync(shot.stdout as List<int>);
  }
}

Future<String> _uiDump() async {
  try {
    await _adb(<String>['shell', 'uiautomator', 'dump', '/sdcard/ui.xml']);
    return await _adb(<String>['shell', 'cat', '/sdcard/ui.xml']);
  } on Object catch (error) {
    return 'uiautomator failed: $error';
  }
}

Future<bool> _waitFor(
  String what,
  Future<bool> Function() condition, {
  required Duration within,
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (watch.elapsed < within) {
    if (await condition()) {
      stdout.writeln('== $what (${watch.elapsed.inSeconds}s)');
      return true;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  stdout.writeln('== timed out: $what');
  return false;
}

Future<void> _launch() => _adb(<String>[
  'shell',
  'monkey',
  '-p',
  _package,
  '-c',
  'android.intent.category.LAUNCHER',
  '1',
]);

Future<void> main() async {
  Directory(_diag).createSync(recursive: true);
  final List<String> failures = <String>[];
  Process? server;
  final IOSink serverLog = File('$_diag/ota-server.log').openWrite();

  try {
    await _adb(<String>['install', '-r', '$_ota/release.apk']);
    final String package = await _adb(<String>[
      'shell',
      'dumpsys',
      'package',
      _package,
    ]);
    final String? name = RegExp(r'versionName=(\S+)').firstMatch(package)?.group(1);
    final String? code = RegExp(r'versionCode=(\d+)').firstMatch(package)?.group(1);
    if (name == null || code == null) {
      throw StateError('dumpsys did not report the installed version');
    }
    // The updater's release_version: versionName+versionCode.
    final String release = '$name+$code';
    stdout.writeln('== installed release $release');

    final ProcessResult published = await Process.run('dart', <String>[
      'run',
      'tool/ci/ota_patch_server.dart',
      'publish',
      '$_ota/store',
      _appId,
      release,
      'android',
      'x86_64',
      '$_ota/patch.bin',
      File('$_ota/patched.sha256').readAsStringSync().trim(),
    ]);
    stdout.writeln('${published.stdout}${published.stderr}');
    if (published.exitCode != 0) throw StateError('publishing the patch failed');

    server = await Process.start('dart', <String>[
      'run',
      'tool/ci/ota_patch_server.dart',
      'serve',
      '$_ota/store',
      '9090',
    ]);
    final List<String> served = <String>[];
    for (final Stream<List<int>> s in <Stream<List<int>>>[
      server.stdout,
      server.stderr,
    ]) {
      s.transform(utf8.decoder).transform(const LineSplitter()).listen((
        String line,
      ) {
        served.add(line);
        serverLog.writeln(line);
        stdout.writeln('[patch source] $line');
      });
    }
    if (!await _waitFor(
      'the patch source is listening',
      () async => served.any((String l) => l.startsWith('patch source on')),
      within: const Duration(minutes: 3),
    )) {
      throw StateError('the patch source did not start');
    }

    await _adb(<String>['logcat', '-c']);
    await _launch();
    final bool ran = await _waitFor(
      'the release is running',
      () async => (await _log()).contains('OTA-PROBE running OTA-PROBE-ONE'),
      within: const Duration(minutes: 2),
    );
    if (!ran) failures.add('the release never started');
    final String first = await _log();
    if (first.contains('registered=false')) {
      failures.add(
        'the Shorebird bindings did not register on a Shorebird build',
      );
    }
    final bool installed = await _waitFor(
      'DV.Updates applied the patch',
      () async {
        final String log = await _log();
        return log.contains('OTA-PROBE apply installed') ||
            log.contains('OTA-PROBE error');
      },
      within: const Duration(minutes: 4),
    );
    final String afterApply = await _log();
    File('$_diag/ota-logcat-1.log').writeAsStringSync(afterApply);
    if (!installed || !afterApply.contains('OTA-PROBE apply installed')) {
      failures.add('the patch was not installed through DV.Updates');
    }
    if (!served.any((String l) => l.contains('/api/v1/patches/check'))) {
      failures.add('the device never asked the Dartvel patch source');
    }
    if (!served.any((String l) => l.startsWith('GET /updates/patches/'))) {
      failures.add('the device never downloaded the patch');
    }
    await _screenshot('ota-1-release');

    await _adb(<String>['shell', 'am', 'force-stop', _package]);
    await Future<void>.delayed(const Duration(seconds: 3));
    await _adb(<String>['logcat', '-c']);
    await _launch();
    final bool patched = await _waitFor(
      'the relaunch runs the patch',
      () async => (await _log()).contains('OTA-PROBE running OTA-PROBE-TWO'),
      within: const Duration(minutes: 2),
    );
    await Future<void>.delayed(const Duration(seconds: 8));
    File('$_diag/ota-logcat-2.log').writeAsStringSync(await _log());
    await _screenshot('ota-2-patched');
    final String ui = await _uiDump();
    File('$_diag/ota-2-patched.xml').writeAsStringSync(ui);
    if (!patched) failures.add('the relaunched app is not the patch');
    if (ui.contains('OTA-PROBE') && !ui.contains('OTA-PROBE-TWO')) {
      failures.add('the screen after relaunch does not show OTA-PROBE-TWO');
    }
  } on Object catch (error, stack) {
    failures.add('the check stopped: $error');
    stderr.writeln(stack);
  } finally {
    server?.kill();
    await serverLog.flush();
    await serverLog.close();
    final File verdict = File('$_diag/ota-verdict.txt')
      ..writeAsStringSync(
        failures.isEmpty ? 'passed\n' : 'failed\n${failures.join('\n')}\n',
      );
    stdout.writeln(verdict.readAsStringSync());
  }
  exit(failures.isEmpty ? 0 : 1);
}
