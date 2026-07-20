import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/admin_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AdminCommand', () {
    late Directory previous;
    late Directory temp;

    setUp(() {
      previous = Directory.current;
      temp = Directory.systemTemp.createTempSync('dartvel_admin_command');
      Directory.current = temp;
    });

    tearDown(() {
      Directory.current = previous;
      temp.deleteSync(recursive: true);
    });

    test('admin generate creates Dartvel admin pages', () async {
      final runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(AdminCommand());

      await runner.run(<String>['admin', 'generate']);

      final index = File(
        p.join(temp.path, 'lib', 'pages', '_dartvel_admin', 'index.page.dart'),
      );
      final queues = File(
        p.join(temp.path, 'lib', 'pages', '_dartvel_admin', 'queues.page.dart'),
      );
      expect(index.existsSync(), isTrue);
      expect(queues.existsSync(), isTrue);
      expect(index.readAsStringSync(), contains('@DVPage'));
      expect(index.readAsStringSync(), contains('DVBox.list'));
      expect(index.readAsStringSync(), contains('DVText'));
    });

    test('admin generate preserves existing files unless forced', () async {
      final first = DartvelAdminGenerator.generate(root: temp, force: false);
      expect(first.writtenFiles, isNotEmpty);
      final second = DartvelAdminGenerator.generate(root: temp, force: false);
      expect(second.writtenFiles, isEmpty);
      expect(second.skippedFiles, isNotEmpty);

      final forced = DartvelAdminGenerator.generate(root: temp, force: true);
      expect(forced.writtenFiles, hasLength(first.writtenFiles.length));
      expect(forced.skippedFiles, isEmpty);
    });

    test('devtools command generates the same admin surface', () async {
      final runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(DevtoolsCommand());

      await runner.run(<String>['devtools']);

      expect(
        File(p.join(
          temp.path,
          'lib',
          'pages',
          '_dartvel_admin',
          'routes.page.dart',
        )).existsSync(),
        isTrue,
      );
    });
  });
}
