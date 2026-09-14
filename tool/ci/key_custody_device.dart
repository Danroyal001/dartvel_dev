/// Launches the key custody probe twice on a device and reads what it said.
///
///   dart tool/ci/key_custody_device.dart android
///   dart tool/ci/key_custody_device.dart ios <simulator udid> <path to Runner.app>
///
/// The probe -- examples/dartvel_example/integration_test/app_key_custody_probe.dart
/// -- is the entry point of the build this installs. Its first launch makes
/// and moves keys; the process is then stopped, and the second launch, a new
/// process, has to read the same keys back. `flutter test` cannot run this:
/// it uninstalls the application when it finishes, and an uninstall is what
/// deletes a Keystore entry and a Keychain item.
///
/// A verdict is written to /tmp/diag/key-custody-<target>-verdict.txt as well
/// as the exit code, because the emulator step that calls this is
/// continue-on-error so its logs upload, and a later step reads the verdict.
///
/// Imports are `dart:` only, so this runs from a bare checkout inside the
/// emulator action, which runs each line of its script as its own `sh -c`.
library;

import 'dart:convert';
import 'dart:io';

const String _diag = '/tmp/diag';
const String _tag = 'DV-KEY-CUSTODY-RESULT';
const String _androidPackage = 'com.example.dartvel_example';
const String _iosBundle = 'com.example.dartvelExample';
const String _apk = 'examples/dartvel_example/build/app/outputs/flutter-apk/app-debug.apk';

/// How long one launch has to report. A debug build starts slowly on an
/// emulator; a probe that never reports is a failure, not a wait.
const Duration _patience = Duration(minutes: 3);

Future<void> main(List<String> arguments) async {
  Directory(_diag).createSync(recursive: true);
  final String target = arguments.isEmpty ? '' : arguments.first;
  final List<String> failures = <String>[];
  try {
    switch (target) {
      case 'android':
        await _android(failures);
      case 'ios':
        if (arguments.length < 3) {
          throw ArgumentError('ios needs a simulator udid and the path to Runner.app');
        }
        await _ios(arguments[1], arguments[2], failures);
      default:
        throw ArgumentError('expected android or ios, got "$target"');
    }
  } on Object catch (error) {
    failures.add('the run did not finish: $error');
  }
  File('$_diag/key-custody-$target-verdict.txt')
      .writeAsStringSync(failures.isEmpty ? 'passed\n' : 'failed\n${failures.join('\n')}\n');
  stdout.writeln('== verdict: ${failures.isEmpty ? 'passed' : 'failed'}');
  for (final String failure in failures) {
    stdout.writeln('!! $failure');
  }
  exitCode = failures.isEmpty ? 0 : 1;
}

/// One launch's report, checked for the phase it believed it was in and for
/// its own verdict.
void _judge(Map<String, Object?> report, int phase, String where, List<String> failures) {
  File('$_diag/key-custody-$where-launch$phase.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('== $where launch $phase: ${jsonEncode(report)}');
  if (report['phase'] != phase) {
    failures.add('$where launch $phase: the probe believed it was launch ${report['phase']}; '
        '${phase == 2 ? 'what the first launch left did not survive the restart' : 'an earlier run left state on the device'}');
  }
  if (report['passed'] != true) {
    final Object? why = report['failures'];
    failures.add('$where launch $phase failed: ${why is List ? why.join('; ') : why}');
  }
}

Map<String, Object?>? _reportIn(String text) {
  Map<String, Object?>? last;
  for (final String line in const LineSplitter().convert(text)) {
    final int at = line.indexOf(_tag);
    if (at < 0) continue;
    final Map<String, Object?>? decoded = _decode(line.substring(at + _tag.length).trim());
    if (decoded != null) last = decoded;
  }
  return last;
}

Map<String, Object?>? _decode(String text) {
  try {
    final Object? value = jsonDecode(text);
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    // Half-written, or truncated by the log: not a report yet.
    return null;
  }
}

Future<Map<String, Object?>?> _poll(Future<Map<String, Object?>?> Function() look) async {
  final DateTime deadline = DateTime.now().add(_patience);
  while (DateTime.now().isBefore(deadline)) {
    final Map<String, Object?>? found = await look();
    if (found != null) return found;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return null;
}

Future<ProcessResult> _must(String executable, List<String> arguments) async {
  final ProcessResult result = await Process.run(executable, arguments);
  final String said = '${result.stdout}${result.stderr}'.trim();
  stdout.writeln('\$ $executable ${arguments.join(' ')}${said.isEmpty ? '' : '\n$said'}');
  if (result.exitCode != 0) {
    throw StateError('$executable ${arguments.join(' ')} exited ${result.exitCode}');
  }
  return result;
}

Future<void> _android(List<String> failures) async {
  await _must('adb', <String>['wait-for-device']);
  // -r: an update keeps a Keystore entry, and nothing here relies on that --
  // but a first install from a clean emulator is what this is.
  await _must('adb', <String>['install', '-r', '-t', _apk]);
  for (final int phase in <int>[1, 2]) {
    await _must('adb', <String>['logcat', '-c']);
    await _must('adb', <String>[
      'shell', 'monkey', '-p', _androidPackage, '-c', 'android.intent.category.LAUNCHER', '1',
    ]);
    final Map<String, Object?>? report = await _poll(() async {
      final ProcessResult log = await Process.run('adb', <String>['logcat', '-d', '-v', 'raw', '-s', 'flutter:I']);
      return _reportIn('${log.stdout}');
    });
    final ProcessResult log = await Process.run('adb', <String>['logcat', '-d', '-t', '600']);
    File('$_diag/key-custody-android-logcat-$phase.txt').writeAsStringSync('${log.stdout}');
    if (report == null) {
      failures.add('android launch $phase printed no $_tag line within '
          '${_patience.inMinutes} minutes; its logcat is in the artifact');
      return;
    }
    _judge(report, phase, 'android', failures);

    // A new process for the next launch, and proof that it will be one.
    await _must('adb', <String>['shell', 'am', 'force-stop', _androidPackage]);
    await Future<void>.delayed(const Duration(seconds: 2));
    final ProcessResult pid = await Process.run('adb', <String>['shell', 'pidof', _androidPackage]);
    if ('${pid.stdout}'.trim().isNotEmpty) {
      failures.add('android: the process outlived force-stop (pid ${'${pid.stdout}'.trim()}), '
          'so the next launch would not have been a restart');
      return;
    }
  }
}

Future<void> _ios(String device, String app, List<String> failures) async {
  await _must('xcrun', <String>['simctl', 'install', device, app]);
  final ProcessResult container =
      await _must('xcrun', <String>['simctl', 'get_app_container', device, _iosBundle, 'data']);
  final String data = '${container.stdout}'.trim();
  if (data.isEmpty) throw StateError('no data container for $_iosBundle');
  for (final int phase in <int>[1, 2]) {
    final File result = File('$data/dv-key-custody-result-$phase.json');
    if (result.existsSync()) result.deleteSync();
    await _must('xcrun', <String>['simctl', 'launch', '--terminate-running-process', device, _iosBundle]);
    final Map<String, Object?>? report =
        await _poll(() async => result.existsSync() ? _decode(result.readAsStringSync()) : null);
    if (report == null) {
      final ProcessResult log = await Process.run('xcrun', <String>[
        'simctl', 'spawn', device, 'log', 'show', '--last', '5m', '--style', 'compact',
        '--predicate', 'process == "Runner"',
      ]);
      File('$_diag/key-custody-ios-log-$phase.txt').writeAsStringSync('${log.stdout}${log.stderr}');
      failures.add('ios launch $phase wrote no report to ${result.path} within '
          '${_patience.inMinutes} minutes; the simulator log is in the artifact');
      return;
    }
    _judge(report, phase, 'ios', failures);
    await Process.run('xcrun', <String>['simctl', 'terminate', device, _iosBundle]);
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}
