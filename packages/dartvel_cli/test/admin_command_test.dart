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
      final indexSource = index.readAsStringSync();
      expect(indexSource, contains('@DVPage'));
      expect(indexSource, contains('Widget _dartvelAdminIndexPage('));
      expect(indexSource, contains('buildDartvelAdminIndexPage(context)'));
      expect(indexSource, isNot(contains('Widget dartvelAdminIndexPage(')));
      expect(indexSource, contains('DVBox.list'));
      expect(indexSource, contains('DVText'));
    });

    test('every modifier the admin pages call exists on DVModifier', () {
      // The generated pages are strings, so nothing compiles them until a user
      // does. They shipped calling a `.bold()` that DVModifier never had; this
      // checks the emitted calls against the real declarations instead.
      final modifiers = File(p.join(
        previous.path,
        '..',
        'dartvel_flutter',
        'lib',
        'dartvel_flutter.dart',
      ));
      expect(modifiers.existsSync(), isTrue,
          reason: 'dartvel_flutter must sit beside dartvel_cli');
      final declared = RegExp(r'^  DVModifier ([a-zA-Z0-9_]+)\(', multiLine: true)
          .allMatches(modifiers.readAsStringSync())
          .map((RegExpMatch m) => m.group(1))
          .toSet();
      expect(declared, contains('fontWeight'));

      final generated = DartvelAdminGenerator.generate(root: temp, force: true);
      for (final file in generated.writtenFiles) {
        final source = file.readAsStringSync();
        for (final call
            in RegExp(r'DVModifier\(\)((?:\.[a-zA-Z0-9_]+\([^;]*?\))+)')
                .allMatches(source)) {
          for (final method in RegExp(r'\.([a-zA-Z0-9_]+)\(')
              .allMatches(call.group(1)!)
              .map((RegExpMatch m) => m.group(1)!)) {
            expect(declared, contains(method),
                reason: '${p.basename(file.path)} calls DVModifier.$method');
          }
        }
      }
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
