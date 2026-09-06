/// Everything the Android job does once an emulator is up.
///
/// This lives in one file because `reactivecircus/android-emulator-runner`
/// runs each **line** of its `script:` as its own `sh -c`. A multi-line
/// `(cd examples/dartvel_example && flutter test ...)` therefore reached the
/// shell as an opening parenthesis and nothing else, which is exactly the
/// "Syntax error: end of file unexpected" that let the lock-task verification
/// silently never run while the job reported success.
///
/// The step that calls this is `continue-on-error` so its diagnostics still
/// upload, so failing is not enough on its own: the verdict is also written
/// to a file, and a later step that is *not* continue-on-error reads it.
///
/// Imports are `dart:` only, so this runs from a bare checkout with nothing
/// resolved.
library;

import 'dart:convert';
import 'dart:io';

/// What Android says about lock task, as read out of `dumpsys`.
enum DVLockTaskState {
  /// A device owner is holding the task. No dialog was involved.
  locked,

  /// Screen pinning: the same hold, arrived at through the dialog.
  pinned,

  /// Asked, and told nothing is locked.
  none,

  /// Never answered. Not the same as [none] -- this is the job failing to
  /// ask, not Android contradicting the test.
  unknown,
}

/// Reads the lock task state out of `adb shell dumpsys activity activities`.
///
/// The last mention wins. Both the global state and a per-display one are
/// printed, in that order, and a parser that took the first match reported
/// NONE for a device that was locked.
DVLockTaskState dvLockTaskState(String dumpsys) {
  // Both spellings. dumpsys prints `mLockTaskModeState=LOCK_TASK_MODE_LOCKED`
  // on some API levels and `mLockTaskModeState=LOCKED` on others, and a
  // parser that knows one silently abstains on every device using the other
  // -- which is what sixty `unknown` readings on an API 34 emulator were.
  //
  // Anchored on the assignment rather than searched for as a substring:
  // `mLockTaskPackages[0]={com.example.locked}` is not a reading, and
  // matching loosely would make it one.
  final RegExp state = RegExp(
    r'mLockTaskModeState\s*=\s*(?:LOCK_TASK_MODE_)?(LOCKED|PINNED|NONE)',
  );
  DVLockTaskState found = DVLockTaskState.unknown;
  for (final RegExpMatch match in state.allMatches(dumpsys)) {
    // The last mention wins: the global state and a per-display one are both
    // printed, in that order, and taking the first reported NONE for a
    // device that was locked.
    found = switch (match.group(1)) {
      'LOCKED' => DVLockTaskState.locked,
      'PINNED' => DVLockTaskState.pinned,
      _ => DVLockTaskState.none,
    };
  }
  return found;
}

/// The message to fail on when the test and the platform disagree, or null
/// when they do not.
String? dvLockTaskDisagreement({
  required bool held,
  required DVLockTaskState state,
}) {
  if (state == DVLockTaskState.unknown) return null;
  final bool platformHeld =
      state == DVLockTaskState.locked || state == DVLockTaskState.pinned;
  if (held == platformHeld) return null;
  return held
      ? 'the kiosk test reported lock task held, and Android reports '
          '${state.name}. One of them is wrong, and it is not worth guessing '
          'which on a device this job can still inspect.'
      : 'the kiosk test reported lock task released, and Android reports '
          '${state.name}. Something is holding the task that Dartvel does '
          'not believe it put there.';
}


/// The strongest state seen across several readings.
///
/// Sampling matters more than the final reading: the kiosk test holds lock
/// task and then releases it, so asking once at the end cannot tell a
/// working hold from one that never happened. One `locked` among a hundred
/// `none`s is the evidence.
DVLockTaskState dvStrongest(Iterable<DVLockTaskState> samples) {
  DVLockTaskState best = DVLockTaskState.unknown;
  for (final DVLockTaskState sample in samples) {
    if (_rank(sample) > _rank(best)) best = sample;
  }
  return best;
}

int _rank(DVLockTaskState state) => switch (state) {
      DVLockTaskState.locked => 3,
      DVLockTaskState.pinned => 2,
      DVLockTaskState.none => 1,
      DVLockTaskState.unknown => 0,
    };
// ---------------------------------------------------------------------------
// The run itself.

const String _diag = '/tmp/diag';
const String _package = 'com.example.dartvel_example';
const String _example = 'examples/dartvel_example';
const String _device = 'emulator-5554';

/// Where the verdict is left for the step that is allowed to fail the job.
const String _verdict = '$_diag/android-verdict.txt';

Future<void> main(List<String> arguments) async {
  final List<String> failures = <String>[];

  Directory(_diag).createSync(recursive: true);

  await _step('install the APK', failures, () => _adb(<String>[
        'install',
        '-r',
        '$_example/build/app/outputs/flutter-apk/app-debug.apk',
      ]));

  await _step(
      'launch it',
      failures,
      () => _adb(<String>[
            'shell',
            'monkey',
            '-p',
            _package,
            '-c',
            'android.intent.category.LAUNCHER',
            '1',
          ]));

  // Long enough for the first frame on a software-rendered emulator. The
  // screenshot is the evidence a later step checks, so a short sleep here
  // reads as a build failure there.
  await Future<void>.delayed(const Duration(seconds: 25));

  await _step('photograph the screen', failures, () async {
    final ProcessResult shot = await Process.run(
        'adb', <String>['exec-out', 'screencap', '-p'],
        stdoutEncoding: null);
    if (shot.exitCode != 0) throw StateError('screencap failed');
    File('$_diag/android.png').writeAsBytesSync(shot.stdout as List<int>);
  });

  // Diagnostics, never a reason to fail.
  final ProcessResult logcat =
      await Process.run('adb', <String>['logcat', '-d', '-s', 'flutter:*']);
  File('$_diag/android-logcat.log').writeAsStringSync('${logcat.stdout}');

  // Links, tapped on the device. A widget test cannot tell a working link
  // from one whose handler builds a callback and never calls it.
  await _step('tap links on the device', failures,
      () => _flutterTest('integration_test/link_navigation_test.dart'));

  // Put the application back before asking the device anything about it.
  //
  // This is the bug, and it took three checks to find because every one of
  // them was pointed at the wrong stage. `flutter test` installs the
  // application to run an integration test and uninstalls it again when the
  // test finishes -- so by the time the link-navigation test above has
  // returned, the package is gone. `dpm set-device-owner` was being asked to
  // make a component of an uninstalled package the device owner, and
  // answered "Unknown admin", which reads exactly like a missing receiver
  // and is not one. The manifest was right the whole time.
  //
  // Reinstalled with -r, which is an update rather than a fresh install:
  // device-owner status survives an update and does not survive an
  // uninstall, so the kiosk test below can install over this one without
  // taking away what is about to be granted.
  final ProcessResult reinstall = await Process.run('adb', <String>[
    'install',
    '-r',
    '-t',
    // From the repository root, which is where this runs. The flutter test
    // above is the thing with a working directory of its own, and the first
    // version of this line copied the path out of that command and reached
    // adb as a path relative to nothing: "failed to stat".
    '$_example/build/app/outputs/flutter-apk/app-debug.apk',
  ]);
  stdout.writeln('== put the application back after flutter test removed it');
  stdout.writeln('   ${'${reinstall.stdout}${reinstall.stderr}'.trim()}');

  // And a guard, because the whole of the last three runs was a check that
  // could not fail for the reason it was looking for. If the package is not
  // here now, nothing below this line means anything.
  final ProcessResult present =
      await Process.run('adb', <String>['shell', 'pm', 'path', _package]);
  if (!'${present.stdout}'.trim().startsWith('package:')) {
    stdout.writeln('!! $_package is still not installed. Everything below '
        'would report a missing receiver for a package that is not there. '
        'The APK was looked for at '
        '$_example/build/app/outputs/flutter-apk/app-debug.apk.');
    failures.add('the application would not stay installed');
  }

  // What the device thinks the package declares, before asking it to make
  // one of them the owner. `set-device-owner` failed with "Unknown admin"
  // against a manifest that demonstrably carries the receiver.
  //
  // `pm query-receivers`, not `dumpsys package <pkg>`: the per-package dump
  // has no receiver table, so the first version of this probe reported "no
  // receiver of any kind" for every application including working ones. A
  // diagnostic that is confidently wrong is worse than none.
  final ProcessResult declared = await Process.run('adb', <String>[
    'shell',
    'pm',
    'query-receivers',
    '-a',
    'android.app.action.DEVICE_ADMIN_ENABLED',
  ]);
  final String receivers = '${declared.stdout}${declared.stderr}';
  File('$_diag/android-receivers.log').writeAsStringSync(receivers);
  stdout.writeln('== device-admin receivers on this device');
  final List<String> ours = const LineSplitter()
      .convert(receivers)
      .where((String line) => line.contains(_package))
      .toList();
  if (ours.isEmpty) {
    stdout.writeln('   none belonging to $_package. The manifest block did '
        'not reach the installed package.');
    // The whole list, so "ours is missing" can be told apart from "the
    // query returned nothing at all".
    stdout.writeln('   the query returned '
        '${const LineSplitter().convert(receivers).length} line(s).');
  } else {
    ours.take(10).forEach((String line) => stdout.writeln('   $line'));
  }



  // The last gap: the APK on the build machine against the one on the
  // device. The build-time check has already proven the generator wrote the
  // receiver and the packager kept it, and the device says it has no such
  // admin -- so either the install carries something else, or the query is
  // asking the wrong question. Reading the manifest back off the device
  // settles which, and nothing short of it does.
  stdout.writeln('== the manifest the device actually has');
  final ProcessResult where =
      await Process.run('adb', <String>['shell', 'pm', 'path', _package]);
  final String pathLine = '${where.stdout}'.trim();
  if (!pathLine.startsWith('package:')) {
    stdout.writeln('   $_package is not installed at all: $pathLine');
  } else {
    final String remote = pathLine.split('\n').first.substring('package:'.length).trim();
    stdout.writeln('   installed from $remote');
    final String local = '$_diag/installed.apk';
    final ProcessResult pulled =
        await Process.run('adb', <String>['pull', remote, local]);
    if (pulled.exitCode != 0) {
      stdout.writeln('   could not pull it: ${pulled.stderr}');
    } else {
      final String? aapt2 = await _aapt2();
      if (aapt2 == null) {
        stdout.writeln('   aapt2 is not on PATH, so it was not read. This is '
            'a gap in the check, not a pass.');
      } else {
        final ProcessResult dump = await Process.run(aapt2, <String>[
          'dump', 'xmltree', local, '--file', 'AndroidManifest.xml',
        ]);
        final String tree = '${dump.stdout}';
        File('$_diag/android-installed-manifest.txt').writeAsStringSync(tree);
        if (tree.contains('DartvelDeviceAdminReceiver')) {
          stdout.writeln('   the installed APK DOES carry the receiver, so '
              'the package is right and the query is asking the wrong '
              'question. Look at the probe, not at the build.');
          for (final String line in const LineSplitter().convert(tree)) {
            if (line.contains('DartvelDeviceAdminReceiver') ||
                line.contains('DEVICE_ADMIN_ENABLED') ||
                line.contains('BIND_DEVICE_ADMIN')) {
              stdout.writeln('     ${line.trim()}');
            }
          }
        } else {
          stdout.writeln('   the installed APK does NOT carry the receiver, '
              'though the one that was built does. Something between the '
              'build directory and the device replaced it -- look at what '
              'runs between them, not at the generator.');
        }
      }
    }
  }

  // And the resolver table the system actually matches against, filtered to
  // this package. `pm query-receivers` performs implicit resolution; this is
  // the table it resolves in, and the two disagreeing is itself the answer.
  final ProcessResult resolver = await Process.run(
      'adb', <String>['shell', 'dumpsys', 'package', 'r', 'receiver']);
  final List<String> mine = const LineSplitter()
      .convert('${resolver.stdout}')
      .where((String line) => line.contains(_package))
      .toList();
  stdout.writeln('== the receiver resolver table, for this package');
  if (mine.isEmpty) {
    stdout.writeln('   nothing at all, which agrees with the query.');
  } else {
    mine.take(12).forEach((String line) => stdout.writeln('   ${line.trim()}'));
  }
  // Device owner first: without it, startLockTask shows the "pin this
  // screen?" dialog and waits for somebody who is not there. This is also
  // how a kiosk is actually provisioned, so the test exercises the
  // deployment rather than a shortcut.
  final ProcessResult owner = await Process.run('adb', <String>[
    'shell',
    'dpm',
    'set-device-owner',
    '$_package/.DartvelDeviceAdminReceiver',
  ]);
  final String ownerLog = '${owner.stdout}${owner.stderr}';
  File('$_diag/android-device-owner.log').writeAsStringSync(ownerLog);
  stdout.writeln('dpm set-device-owner: exit ${owner.exitCode}');
  stdout.writeln(ownerLog.trim());

  // Whether it took, asked of the platform rather than inferred from an exit
  // code. And asked again after the kiosk test, because that test installs
  // the application over this one: an update keeps device-owner status and
  // an uninstall does not, so if the two answers differ, the reinstall
  // rather than the enforcement is what to look at.
  Future<String> deviceOwner() async {
    final ProcessResult policy = await Process.run(
        'adb', <String>['shell', 'dumpsys', 'device_policy']);
    final Iterable<String> lines = const LineSplitter()
        .convert('${policy.stdout}')
        .where((String line) => line.contains('Device Owner') ||
            line.contains('device owner'));
    return lines.isEmpty ? 'none' : lines.first.trim();
  }

  stdout.writeln('   the device owner is now: ${await deviceOwner()}');

  // The platform's own answer, sampled while the test runs. Reading dumpsys
  // afterwards proves nothing: the test releases the task before it ends, so
  // a healthy run and a run where lock task never engaged both read NONE.
  final List<DVLockTaskState> samples = <DVLockTaskState>[];
  bool sampling = true;
  final Future<void> sampler = () async {
    while (sampling) {
      final ProcessResult dump = await Process.run(
          'adb', <String>['shell', 'dumpsys', 'activity', 'activities']);
      final DVLockTaskState seen = dvLockTaskState('${dump.stdout}');
      samples.add(seen);
      if (seen == DVLockTaskState.locked || seen == DVLockTaskState.pinned) {
        File('$_diag/android-lock-task.log').writeAsStringSync(
          const LineSplitter()
              .convert('${dump.stdout}')
              .where((String line) => line.contains('LockTask'))
              .join('\n'),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }();

  bool held = false;
  await _step('hold and release lock task', failures, () async {
    await _flutterTest('integration_test/kiosk_lock_task_test.dart');
    held = true;
  });

  sampling = false;
  await sampler;

  // The same question again. If the owner was set before the test and is
  // gone after it, the kiosk did not fail to hold -- it was never provisioned
  // by the time it tried, because the test's own install took the owner away
  // with it. That is a different fix, and the two answers side by side are
  // what say which.
  stdout.writeln('   the device owner after the test: ${await deviceOwner()}');

  final DVLockTaskState state = dvStrongest(samples);
  stdout.writeln('Android reported lock task: ${state.name} '
      '(${samples.length} readings)');
  if (state == DVLockTaskState.unknown) {
    // Nothing matched, on any reading. That is the parser and the platform
    // disagreeing about the wording, not the platform saying no -- and the
    // only way to tell is to keep what it actually printed.
    final ProcessResult raw = await Process.run(
        'adb', <String>['shell', 'dumpsys', 'activity', 'activities']);
    File('$_diag/android-dumpsys-activities.log')
        .writeAsStringSync('${raw.stdout}');
    final List<String> mentions = const LineSplitter()
        .convert('${raw.stdout}')
        .where((String line) => line.toLowerCase().contains('locktask'))
        .toList();
    stdout.writeln('   dumpsys said nothing this reads. Lines mentioning '
        'lock task: ${mentions.isEmpty ? 'none at all' : ''}');
    mentions.take(10).forEach((String line) => stdout.writeln('   $line'));
  }

  final String? disagreement = dvLockTaskDisagreement(held: held, state: state);
  if (disagreement != null) failures.add(disagreement);

  final String result = failures.isEmpty
      ? 'passed'
      : 'failed\n${failures.map((String f) => '- $f').join('\n')}';
  File(_verdict).writeAsStringSync('$result\n');
  stdout.writeln('verdict: $result');
  exitCode = failures.isEmpty ? 0 : 1;
}

Future<void> _step(
  String what,
  List<String> failures,
  Future<void> Function() body,
) async {
  stdout.writeln('== $what');
  try {
    await body();
  } on Object catch (error) {
    // Kept going deliberately: the remaining steps produce diagnostics that
    // say why this one failed, and a job that stops at the first problem
    // uploads nothing to look at.
    stdout.writeln('!! $what failed: $error');
    failures.add('$what: $error');
  }
}

Future<void> _adb(List<String> arguments) => _run('adb', arguments);

Future<void> _flutterTest(String path) => _run(
      'flutter',
      <String>['test', path, '-d', _device],
      workingDirectory: _example,
    );

Future<void> _run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final int code = await process.exitCode;
  if (code != 0) {
    throw StateError('$executable ${arguments.join(' ')} exited $code');
  }
}

/// aapt2, from the SDK the runner already has.
///
/// The same lookup as tool/ci/android_manifest_check.dart, which runs on the
/// build machine rather than here. Duplicated rather than shared because
/// this file is called with `dart tool/ci/...` from inside the emulator
/// action, where the root package is not resolved and an import of anything
/// but `dart:` would not load.
Future<String?> _aapt2() async {
  final ProcessResult which = await Process.run('which', <String>['aapt2']);
  if (which.exitCode == 0) return '${which.stdout}'.trim();

  final String? sdk = Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'];
  if (sdk == null) return null;
  final Directory tools = Directory('$sdk/build-tools');
  if (!tools.existsSync()) return null;
  final List<String> versions = tools
      .listSync()
      .whereType<Directory>()
      .map((Directory d) => d.path)
      .toList()
    ..sort();
  for (final String version in versions.reversed) {
    final File candidate = File('$version/aapt2');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}
