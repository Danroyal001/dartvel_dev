// `dartvel dev` keeps the project's agent rules matched to the Dartvel that is
// running.
//
// The block is written once, at create, and every later version of Dartvel can
// change what the rules say. A block that only refreshes when somebody runs a
// command nobody knows about names the API as it was on the day the project was
// made, and an agent then writes code against a version that has since moved.
// So `dev` refreshes it on the way in, before generation.
//
// This runs the command itself rather than the helper it calls, because the
// failure it guards against is the helper being wired in but never reached.
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/agents/agent_docs.dart';
import 'package:dartvel_cli/src/commands/dev_command.dart';
import 'package:dartvel_cli/src/commands/generate_command.dart'
    show DartvelCommandRunner;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_dev_agent_docs_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  /// Runs `dartvel dev` in [root] and stops at the first thing that needs a
  /// real Flutter toolchain.
  ///
  /// The agent sync runs before any of that, so the files are on disk whatever
  /// happens next. Every failure after that point is expected and ignored:
  /// what is under test is the step in front of them.
  Future<void> runDev([List<String> arguments = const <String>[]]) async {
    try {
      await (DartvelCommandRunner('dartvel', 'test')..addCommand(DevCommand(root: root.path)))
          .run(<String>['dev', ...arguments]);
    } catch (_) {
      // The generation, the Flutter run or the server bind failed because
      // there is no toolchain in a temp directory. Not what this asserts.
    }
  }

  test('a stale block is refreshed by starting dev', () async {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: probe\n');
    // A block from an older Dartvel, as a project created before this existed
    // would have after its first `dartvel dev`.
    File(p.join(root.path, 'AGENTS.md')).writeAsStringSync(
      '# Dartvel\n\n'
      '${dvAgentBlock(version: '0.9.0', rules: '- write data through records')}\n',
    );

    await runDev();

    final String body = File(p.join(root.path, 'AGENTS.md')).readAsStringSync();
    expect(body, isNot(contains('- write data through records')));
    expect(body, contains(dvAgentBlockBegin));
    expect(body, isNot(contains('0.9.0')));
  });

  test('the rest of the agent files appear too, not just AGENTS.md', () async {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: probe\n');

    await runDev();

    for (final String path in <String>[
      'CLAUDE.md',
      'GEMINI.md',
      '.cursorrules',
      '.cursor/rules/dartvel.mdc',
      '.github/copilot-instructions.md',
    ]) {
      expect(File(p.join(root.path, path)).existsSync(), isTrue,
          reason: '$path is missing after dartvel dev');
    }
  });

  // The subprocess below is a cold Dart VM loading the whole CLI, which takes
  // about a minute on a quiet machine; the default test timeout is 30 seconds.
  test('serving a release build refreshes them too', () async {
    // `dartvel dev --release` is still `dartvel dev`, and a developer who only
    // ever serves builds that way would otherwise never get a refreshed block.
    //
    // A subprocess, not the command in this process: with no build to serve,
    // `--release` calls exit(1), which would take the test runner with it.
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: probe\n');
    File(p.join(root.path, 'AGENTS.md')).writeAsStringSync(
      '${dvAgentBlock(version: '0.8.0', rules: '- the rules of an older day')}\n',
    );
    expect(File(p.join(_cliRoot(), 'bin', 'dartvel.dart')).existsSync(), isTrue,
        reason: 'the subprocess below needs the CLI entry point to be there');

    await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(_cliRoot(), '.dart_tool', 'package_config.json')}',
        p.join(_cliRoot(), 'bin', 'dartvel.dart'),
        'dev',
        '--release',
      ],
      workingDirectory: root.path,
    ).timeout(const Duration(seconds: 180), onTimeout: () => throw StateError(
        'dartvel dev --release did not finish in a temp project'));

    final String body = File(p.join(root.path, 'AGENTS.md')).readAsStringSync();
    expect(body, isNot(contains('0.8.0')));
    expect(body, contains(dvAgentBlockBegin));
  }, timeout: const Timeout(Duration(seconds: 200)));

  test('a usage error writes nothing at all', () async {
    // --port without --release is a mistake, and a command that fixed
    // documentation before complaining about the mistake has half-run.
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: probe\n');

    await runDev(<String>['--port', '9999']);

    expect(File(p.join(root.path, 'AGENTS.md')).existsSync(), isFalse,
        reason: 'a rejected command still set the project up');
  });
}

/// The package root this test runs from, so a subprocess can be launched out of
/// the same checkout rather than a published release.
///
/// Resolved through a `package:` URI, because the test file's own location says
/// nothing once the runner has compiled it somewhere else.
String _cliRoot() => p.dirname(p.dirname(p.dirname(p.dirname(
    Isolate.resolvePackageUriSync(Uri.parse(
            'package:dartvel_cli/src/agents/agent_docs.dart'))!
        .toFilePath()))));