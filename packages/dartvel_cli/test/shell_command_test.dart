import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/shell_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DartvelShellInvocation', () {
    test('parses quoted arguments without using a platform shell', () async {
      final invocation =
          await DartvelShellInvocation.parse('dart --define "name=value one"');

      expect(invocation.executable, 'dart');
      expect(invocation.arguments, <String>['--define', 'name=value one']);
    });

    test('expands globs relative to the working directory', () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_shell_glob');
      try {
        File(p.join(temp.path, 'b.dart')).writeAsStringSync('');
        File(p.join(temp.path, 'a.dart')).writeAsStringSync('');

        final invocation =
            await DartvelShellInvocation.parse('dart test *.dart', temp);

        expect(invocation.arguments, <String>['test', 'a.dart', 'b.dart']);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  });

  group('DartvelShell', () {
    test('returns typed stdout stderr and exit code', () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_shell_run');
      final script = File(p.join(temp.path, 'print_message.dart'))
        ..writeAsStringSync("void main() => print('dartvel-shell');");
      final result = await DartvelShell.run(
        '${Platform.resolvedExecutable} ${script.path}',
        streamOutput: false,
      );

      try {
        expect(result.exitCode, 0);
        expect(result.succeeded, isTrue);
        expect(result.stdoutText, contains('dartvel-shell'));
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  });

  group('TaskCommand', () {
    late Directory previous;
    late Directory temp;

    setUp(() {
      previous = Directory.current;
      temp = Directory.systemTemp.createTempSync('dartvel_task_command');
      Directory.current = temp;
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: task_test
dartvel:
  tasks:
    sdk: "${Platform.resolvedExecutable} --version"
''');
    });

    tearDown(() {
      Directory.current = previous;
      temp.deleteSync(recursive: true);
    });

    test('lists tasks from pubspec.yaml dartvel.tasks', () async {
      final runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(TaskCommand());

      await runner.run(<String>['task', '--list']);

      expect(DartvelTaskFile.load(temp).names, <String>['sdk']);
    });

    test('runs tasks from pubspec.yaml dartvel.tasks', () async {
      final runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(TaskCommand());

      await runner.run(<String>['task', 'sdk', '--quiet']);
    });
  });
}
