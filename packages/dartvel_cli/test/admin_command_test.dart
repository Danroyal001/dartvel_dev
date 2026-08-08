import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/admin_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String modelSource = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Order {
  final String id;
  const _Order({required this.id});
}

@DVModel()
@pragma('vm:entry-point')
class _Customer {
  final String id;
  const _Customer({required this.id});
}
''';

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

    test('the admin opens the Studio rather than only naming it', () async {
      final runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(AdminCommand());
      await runner.run(<String>['admin', 'generate']);

      final admin = p.join(temp.path, 'lib', 'pages', '_dartvel_admin');
      final studio =
          File(p.join(admin, 'studio.page.dart')).readAsStringSync();
      expect(studio, contains("path: '/_dartvel_admin/studio'"));
      // Delegating to the tested widget, not re-emitting an editor as source.
      expect(studio, contains('const DVStudioScreen()'));

      final index = File(p.join(admin, 'index.page.dart')).readAsStringSync();
      expect(index, contains("'/_dartvel_admin/studio'"));
      // Cards that name a page without navigating leave the admin a dead end.
      expect(index, contains('context.navigateToPage'));
    });

    test('the queues page is a live dashboard, not placeholder cards', () {
      final generated = DartvelAdminGenerator.generate(root: temp, force: true);
      final queues = generated.writtenFiles
          .firstWhere((File f) => f.path.endsWith('queues.page.dart'))
          .readAsStringSync();

      expect(queues, contains('DVQueueAdmin'));
      // The old page named three surfaces and showed none of them.
      expect(queues, isNot(contains("DVText('Pending jobs')")));
      expect(queues, isNot(contains("DVText('Failed jobs')")));
    });

    test('models found in lib/models get a CRUD admin', () {
      Directory(p.join(temp.path, 'lib', 'models')).createSync(recursive: true);
      File(p.join(temp.path, 'lib', 'models', 'shop.dart'))
          .writeAsStringSync(modelSource);

      final generated = DartvelAdminGenerator.generate(root: temp, force: true);
      final models = generated.writtenFiles
          .firstWhere((File f) => f.path.endsWith('models.page.dart'))
          .readAsStringSync();

      // Scanned rather than configured, so a model added later is not
      // silently left out of the admin.
      expect(models, contains('Customer.Admin()'));
      expect(models, contains('Order.Admin()'));
      // The generated public type, not the private annotated input.
      expect(models, isNot(contains('_Order')));
      expect(models, contains("path: '/_dartvel_admin/models'"));
    });

    test('an app with no models says so rather than showing a blank page', () {
      final generated = DartvelAdminGenerator.generate(root: temp, force: true);
      final models = generated.writtenFiles
          .firstWhere((File f) => f.path.endsWith('models.page.dart'))
          .readAsStringSync();

      expect(models, contains('No @DVModel classes found'));
    });

    test('the index links to the model admin', () {
      final generated = DartvelAdminGenerator.generate(root: temp, force: true);
      final index = generated.writtenFiles
          .firstWhere((File f) => f.path.endsWith('index.page.dart'))
          .readAsStringSync();

      // Model CRUD is generated per model; without this it is unreachable.
      expect(index, contains("'/_dartvel_admin/models'"));
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
