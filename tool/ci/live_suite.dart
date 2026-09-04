/// Runs a native live suite and reports what the tests said.
///
///     dart run tool/ci/live_suite.dart flutter test test/x_live_test.dart
///
/// The macOS and Windows binding suites exercise real AppKit panels and Win32
/// dialogs. Both have reached the state where every test passes and the tester
/// process then does not exit — AppKit and the shell hold onto things after a
/// panel has been answered, and the harness waits for a process that is not
/// coming back. Judged on the exit code alone, a suite in which nothing failed
/// goes red, which says the wrong thing about the code under test and hides
/// the run in which something really does fail.
///
/// So the verdict comes from the reporter, which is the thing that actually
/// knows: any test failing fails the step. A process that then would not exit
/// is printed as a warning, loudly, because it is worth fixing and worth
/// seeing — it just is not the tests failing.
library;

import 'dart:convert';
import 'dart:io';

Future<int> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('usage: live_suite.dart <flutter> test <path> ...');
    exitCode = 2;
    return 2;
  }

  // Run once; run again only if the tester went away mid-suite. On a macOS
  // runner the panel service occasionally takes the process with it, which
  // marks every test after that one as failed and says nothing true about any
  // of them. Two deaths in a row is a failure — this retries an accident, not
  // a fault.
  _Run run = await _run(arguments);
  if (run.diedPartway) {
    stdout.writeln('  the tester went away mid-run, so the results after it '
        'say nothing; running the suite again');
    run = await _run(arguments);
    if (run.diedPartway) {
      run.lines.forEach(stdout.writeln);
      stdout.writeln('::error::the tester went away mid-run twice');
      exitCode = 1;
      return 1;
    }
  }

  run.lines.forEach(stdout.writeln);
  stdout.writeln(
      '\n${run.passed} passed, ${run.failures.length} failed, ${run.skipped} skipped');
  if (run.stderr.trim().isNotEmpty) stdout.writeln(run.stderr.trim());

  int fail(String message) {
    stdout.writeln(message);
    exitCode = 1;
    return 1;
  }

  if (run.failures.isNotEmpty) {
    for (final String name in run.failures) {
      stdout.writeln('::error::$name failed');
    }
    exitCode = 1;
    return 1;
  }
  if (run.verdict == false) {
    return fail('::error::the reporter says the run did not succeed');
  }
  if (run.verdict == null && run.passed == 0) {
    return fail('::error::the suite produced no results before it was stopped');
  }
  if (run.passed == 0 && run.skipped == 0) {
    // A run that matched nothing. package:test says the run succeeded — it
    // did, there was nothing to do — and a filter with a typo in it then
    // reports a green step for a test nobody ran, which is the one outcome
    // worse than a red one.
    return fail('::error::no test matched; the suite ran nothing');
  }
  if (run.hung) {
    stdout.writeln('::warning::every test passed and the tester never exited: '
        'something native is still holding the process open after the suite. '
        'Worth fixing, and not the tests failing.');
  } else if (run.exitCode != 0) {
    stdout.writeln('::warning::every test passed and the tester exited '
        '${run.exitCode}: something native is still holding the process open '
        'after the suite. Worth fixing, and not the tests failing.');
  }
  return 0;
}

/// One line of the rendered report, before its errors are attached.
class _Result {
  const _Result(this.status, this.name, this.testId);

  final String status;
  final String name;
  final Object? testId;
}

/// What one run of a suite reported.
class _Run {
  int passed = 0;
  int skipped = 0;
  final List<String> failures = <String>[];
  List<String> lines = <String>[];
  final List<_Result> results = <_Result>[];
  bool? verdict;
  bool hung = false;
  int exitCode = 0;
  String stderr = '';
  bool testerLeft = false;

  /// Whether the tester ended without finishing what it started.
  ///
  /// Two shapes, both meaning the process went away mid-run rather than a test
  /// failing. It can leave no verdict at all; or the harness notices first,
  /// says so in its own words — 'Shell subprocess ended cleanly. Did main()
  /// call exit()?' — and marks everything left as failed, which arrives
  /// looking exactly like a suite in which fourteen things broke at once.
  bool get diedPartway {
    if (verdict == null && !hung && passed > 0) return true;
    return testerLeft;
  }
}

Future<_Run> _run(List<String> command) async {
  final _Run result = _Run();

  // Written to files rather than to pipes. `flutter` spawns the tester, and
  // killing the parent leaves the child holding the pipe open, so anything
  // reading it waits for a process nobody is waiting for — which is how the
  // cap that exists to stop this suite hanging the job hung the job.
  final Directory workspace =
      Directory.systemTemp.createTempSync('dartvel_live_suite_');
  final File out = File('${workspace.path}/machine.jsonl');
  final File err = File('${workspace.path}/stderr.txt');
  String stdoutText = '';
  String stderrText = '';
  int code = 0;

  try {
    final IOSink outSink = out.openWrite();
    final IOSink errSink = err.openWrite();
    // On Windows `flutter` is a batch file, and a process started by name
    // without the extension is not found — which reads as "flutter is not
    // installed" on a runner that has just used it. runInShell resolves it
    // the way the shell would.
    final Process process = await Process.start(
      command.first,
      <String>[...command.skip(1), '--machine'],
      runInShell: true,
    );
    final Future<void> piped = Future.wait<void>(<Future<void>>[
      outSink.addStream(process.stdout),
      errSink.addStream(process.stderr),
    ]);

    try {
      code = await process.exitCode.timeout(const Duration(seconds: 600));
    } on Object {
      result.hung = true;
      await _killTree(process.pid);
      code = await process.exitCode
          .timeout(const Duration(seconds: 60), onTimeout: () => -1);
    }
    await piped.catchError((Object _) {});
    await outSink.close();
    await errSink.close();

    stdoutText = out.readAsStringSync();
    stderrText = err.readAsStringSync();
  } finally {
    workspace.deleteSync(recursive: true);
  }

  final Map<Object?, String> names = <Object?, String>{};
  final Map<Object?, List<String>> errors = <Object?, List<String>>{};
  final List<String> loose = <String>[];

  // What the process said that was not a report. The machine reporter's own
  // output is JSON per line, so anything else is the runtime talking — an
  // AppKit warning, a native log — and it was being dropped. A failure the
  // reporter attaches no error to leaves that as the only account of what
  // happened.
  final List<String> said = <String>[];

  for (final String raw in const LineSplitter().convert(stdoutText)) {
    final String line = raw.trim();
    if (!line.startsWith('{')) {
      if (line.isNotEmpty) said.add(line);
      continue;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, Object?>) continue;
    switch (decoded['type']) {
      case 'testStart':
        final Object? test = decoded['test'];
        if (test is Map) {
          names[test['id']] = '${test['name'] ?? ''}';
        }
      case 'testDone':
        final String name = names[decoded['testID']] ?? '';
        if (name.startsWith('loading ') || decoded['hidden'] == true) continue;
        if (decoded['skipped'] == true) {
          result.skipped++;
          result.results.add(_Result('skipped', name, null));
        } else if (decoded['result'] == 'success') {
          result.passed++;
          result.results.add(_Result('ok', name, null));
        } else {
          result.failures.add(name);
          // Recorded, not printed: package:test emits a test's errors after
          // its result as often as before it, so printing here named the
          // failing test and said nothing about it — which is most of the way
          // back to reading the raw log this exists to replace.
          result.results.add(_Result('FAILED', name, decoded['testID']));
        }
      case 'error':
        // Kept against the test it belongs to and printed with it: an error
        // printed on its own, before the result it explains, is a line nobody
        // connects to anything.
        final List<String> details = <String>[
          for (final String d
              in const LineSplitter().convert('${decoded['error'] ?? ''}'))
            if (d.trim().isNotEmpty) d,
        ];
        final List<String> trace =
            const LineSplitter().convert('${decoded['stackTrace'] ?? ''}');
        if (trace.isNotEmpty) details.add(trace.first.trim());
        if (details.any((String d) => d.contains('Shell subprocess ended'))) {
          result.testerLeft = true;
        }
        final List<String> kept = details.take(6).toList();
        errors.putIfAbsent(decoded['testID'], () => <String>[]).addAll(kept);
        if (decoded['testID'] == null) loose.addAll(kept);
      case 'print':
        final String message = '${decoded['message'] ?? ''}'.trim();
        if (message.isNotEmpty) said.add(message);
      case 'done':
        final Object? success = decoded['success'];
        result.verdict = success is bool ? success : null;
    }
  }

  // Now that every event has been read, each result can be printed with the
  // errors that belong to it.
  final List<String> rendered = <String>[];
  for (final _Result line in result.results) {
    rendered.add('  ${line.status.padRight(8)} ${line.name}');
    if (line.status == 'FAILED') {
      for (final String detail in errors[line.testId] ?? const <String>[]) {
        rendered.add('           $detail');
      }
    }
  }
  rendered.addAll(loose.map((String d) => '  error: $d'));

  // Anything that was reported and belongs to nothing that was printed. An
  // error attached to an id that never produced a result — a synthesised
  // (tearDownAll), a load failure — was collected and then dropped, which left
  // a FAILED line with no reason under it: exactly the shape this tool exists
  // to replace.
  final Set<Object?> printed =
      result.results.map((_Result r) => r.testId).toSet();
  errors.forEach((Object? testId, List<String> details) {
    if (testId == null || printed.contains(testId)) return;
    for (final String detail in details) {
      rendered.add('  error (${names[testId] ?? testId}): $detail');
    }
  });

  // And the case with no explanation at all, said rather than left blank.
  if (result.failures.isNotEmpty && errors.isEmpty) {
    rendered.add('  the reporter failed these and attached no error to any of '
        'them, so what the process itself said is all there is:');
    for (final String line in said.skip(said.length > 40 ? said.length - 40 : 0)) {
      rendered.add('    $line');
    }
    if (said.isEmpty) rendered.add('    (it said nothing at all)');
  }
  result.lines = rendered;

  if (stderrText.contains('Shell subprocess ended')) result.testerLeft = true;
  result.exitCode = code;
  result.stderr = stderrText;
  return result;
}

/// Ends the tester as well as the tool that started it.
///
/// `flutter` is a launcher: killing it leaves flutter_tester running, and a
/// tester that is still running is exactly the thing being timed out.
Future<void> _killTree(int pid) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', <String>['/F', '/T', '/PID', '$pid']);
    return;
  }
  await Process.run('pkill', <String>['-9', '-P', '$pid']);
  Process.killPid(pid, ProcessSignal.sigkill);
  await Process.run('pkill', <String>['-9', '-f', 'flutter_tester']);
}
