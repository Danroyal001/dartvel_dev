import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/ai_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AiCommand', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dartvel_ai_command_');
      exitCode = 0;
    });

    tearDown(() {
      root.deleteSync(recursive: true);
      exitCode = 0;
    });

    test('context writes a concrete project inventory', () async {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
      File(p.join(root.path, 'lib', 'main.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}\n');

      await _runAi(<String>['ai', 'context'], root);

      final context = aiContextFile(root.path);
      expect(context.existsSync(), isTrue);
      expect(context.readAsStringSync(), contains('`lib/main.dart`'));
      expect(context.readAsStringSync(), contains('`pubspec.yaml`'));
    });

    test('doctor reports concrete project errors', () {
      final diagnostics = inspectAiProject(root.path);

      expect(diagnostics.hasErrors, isTrue);
      expect(
        diagnostics.messages,
        containsAll(<String>[
          '[error] pubspec.yaml is missing',
          '[error] lib directory is missing',
          '[error] no Dart source files found under lib or test',
        ]),
      );
    });

    test('generate without provider exits instead of faking success', () async {
      await _runAi(<String>['ai', 'generate', 'make a page'], root);

      expect(exitCode, 78);
      expect(aiGenerateRequestFile(root.path).existsSync(), isFalse);
    });
  });
}

Future<void> _runAi(List<String> args, Directory root) {
  return (CommandRunner<void>('dartvel', 'test')
        ..addCommand(AiCommand(root: root.path)))
      .run(args);
}
