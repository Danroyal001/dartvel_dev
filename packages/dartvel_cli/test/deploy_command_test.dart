import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/deploy_command.dart';
import 'package:test/test.dart';

void main() {
  group('DeployCommand', () {
    setUp(() {
      exitCode = 0;
    });

    tearDown(() {
      exitCode = 0;
    });

    test('stops when production build fails', () async {
      final calls = <String>[];

      await _runDeploy(
        <String>['deploy', '--provider', 'vercel'],
        processRun: (executable, arguments, {runInShell = false}) async {
          calls.add('$executable ${arguments.join(' ')}');
          return ProcessResult(1, 23, '', 'build failed');
        },
      );

      expect(exitCode, 23);
      expect(
          calls, <String>['dart run dartvel_cli:dartvel build --platform all']);
    });

    test('vercel deployment failure sets exit code', () async {
      await _runDeploy(
        <String>['deploy', '--no-build', '--provider', 'vercel'],
        processRun: (executable, arguments, {runInShell = false}) async {
          expect(executable, 'vercel');
          expect(arguments, <String>['--prod']);
          return ProcessResult(2, 17, '', 'deploy failed');
        },
      );

      expect(exitCode, 17);
    });

    test('firebase verifies cli before deploying', () async {
      final calls = <String>[];

      await _runDeploy(
        <String>['deploy', '--no-build', '--provider', 'firebase'],
        processRun: (executable, arguments, {runInShell = false}) async {
          calls.add('$executable ${arguments.join(' ')}');
          return ProcessResult(3, 127, '', 'missing');
        },
      );

      expect(exitCode, 127);
      expect(calls, <String>['firebase --version']);
    });
  });
}

Future<void> _runDeploy(
  List<String> args, {
  required DeployProcessRun processRun,
}) {
  return (CommandRunner<void>('dartvel', 'test')
        ..addCommand(DeployCommand(processRun: processRun)))
      .run(args);
}
