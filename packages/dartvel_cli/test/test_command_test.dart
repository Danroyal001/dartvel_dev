import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/test_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('TestCommand', () {
    late Directory previous;
    late Directory temp;
    late CommandRunner<void> runner;

    setUp(() {
      previous = Directory.current;
      temp = Directory.systemTemp.createTempSync('dartvel_test_command');
      Directory.current = temp;
      runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(TestCommand());
    });

    tearDown(() {
      Directory.current = previous;
      temp.deleteSync(recursive: true);
    });

    test('resolves unit tests to dart test by default', () async {
      Directory(p.join(temp.path, 'test')).createSync();
      final invocation = DartvelTestInvocation.resolve(
        mode: 'unit',
        forceFlutter: false,
        forceDart: false,
        watch: false,
        reporter: 'compact',
        forwardedArgs: const <String>[],
        root: temp,
      );

      expect(invocation.executable, 'dart');
      expect(invocation.arguments, <String>[
        'test',
        'test',
        '--reporter',
        'compact',
      ]);
    });

    test('resolves e2e tests to integration_test when present', () {
      Directory(p.join(temp.path, 'integration_test')).createSync();
      final invocation = DartvelTestInvocation.resolve(
        mode: 'e2e',
        forceFlutter: true,
        forceDart: false,
        watch: false,
        reporter: null,
        forwardedArgs: const <String>['--plain-name', 'smoke'],
        root: temp,
      );

      expect(invocation.executable, 'flutter');
      expect(invocation.arguments, <String>[
        'test',
        'integration_test',
        '--plain-name',
        'smoke',
      ]);
    });

    test('dry-run command accepts golden mode', () async {
      await runner.run(<String>[
        'test',
        'golden',
        '--flutter',
        '--dry-run',
      ]);
    });
  });
}
