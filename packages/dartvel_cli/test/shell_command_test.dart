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

    test('pipes stdout between commands without a platform shell', () async {
      final temp = Directory.systemTemp.createTempSync('dartvel_shell_pipe');
      try {
        final emit = File(p.join(temp.path, 'emit.dart'))
          ..writeAsStringSync("void main() => print('dartvel-pipe');");
        final upper = File(p.join(temp.path, 'upper.dart'))
          ..writeAsStringSync('''
import 'dart:io';

Future<void> main() async {
  final input = await stdin.transform(systemEncoding.decoder).join();
  stdout.write(input.toUpperCase());
}
''');

        final result = await DartvelShell.run(
          '${Platform.resolvedExecutable} ${emit.path} | ${Platform.resolvedExecutable} ${upper.path}',
          streamOutput: false,
        );

        expect(result.exitCode, 0);
        expect(result.stdoutText, contains('DARTVEL-PIPE'));
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('redirects stdout and stderr to files', () async {
      final temp =
          Directory.systemTemp.createTempSync('dartvel_shell_redirect');
      try {
        final script = File(p.join(temp.path, 'emit.dart'))
          ..writeAsStringSync('''
import 'dart:io';

void main() {
  stdout.write('out-file');
  stderr.write('err-file');
}
''');

        final result = await DartvelShell.run(
          '${Platform.resolvedExecutable} ${script.path} > out.txt 2> err.txt',
          workingDirectory: temp,
          streamOutput: false,
        );

        expect(result.exitCode, 0);
        expect(result.stdoutText, isEmpty);
        expect(result.stderrText, isEmpty);
        expect(
            File(p.join(temp.path, 'out.txt')).readAsStringSync(), 'out-file');
        expect(
            File(p.join(temp.path, 'err.txt')).readAsStringSync(), 'err-file');
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

    test('loads task declarations from .dartvel.sh', () {
      File(p.join(temp.path, '.dartvel.sh')).writeAsStringSync('''
# Dartvel local tasks
task clean: ${Platform.resolvedExecutable} --version
build:web: ${Platform.resolvedExecutable} --version
''');

      final tasks = DartvelTaskFile.load(temp);

      expect(tasks.names, <String>['build:web', 'clean', 'sdk']);
      expect(tasks.commandFor('clean'),
          '${Platform.resolvedExecutable} --version');
    });

    test('loads task declarations from .dartvel.dart', () {
      File(p.join(temp.path, '.dartvel.dart')).writeAsStringSync('''
// task check: ${Platform.resolvedExecutable} --version
void main() {}
''');

      final tasks = DartvelTaskFile.load(temp);

      expect(tasks.names, <String>['check', 'sdk']);
      expect(tasks.commandFor('check'),
          '${Platform.resolvedExecutable} --version');
    });

    test('exposes .dartvel.dart as a default dartvel task', () {
      File(p.join(temp.path, '.dartvel.dart')).writeAsStringSync('''
void main() {
  print('default task');
}
''');

      final tasks = DartvelTaskFile.load(temp);

      expect(tasks.names, <String>['dartvel', 'sdk']);
      expect(tasks.commandFor('dartvel'), contains('.dartvel.dart'));
    });
  });
}
