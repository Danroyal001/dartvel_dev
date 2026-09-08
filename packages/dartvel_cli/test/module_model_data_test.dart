// A module's generated model asks where its data is, rather than assuming.
//
// The data mode is the parent's decision and the model is the module's code,
// generated from the module's own project long before anybody mounts it. So
// the table name and the connection cannot be written into the generated
// source: they have to be asked for at run time, by the module's own id.
//
// Before this, they were written in. A module mounted schema-isolated
// queried the same bare table as a shared one, which is a module reading
// somebody else's rows with nothing to show for it.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Order {
  final String id;
  final String reference;

  const _Order({required this.id, required this.reference});
}
''';

/// Generates models in a project, which is a module when [moduleId] is given.
Future<String> generate({String? moduleId}) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_module_model_');
  addTearDown(() => root.deleteSync(recursive: true));

  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'models', 'order.dart'))
      .writeAsStringSync(_model);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: orders_app
dartvel:
${moduleId == null ? '  pagesDir: lib/pages' : '  module:\n    id: $moduleId'}
''');

  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'orders_app',
    buildId: 'test-build',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
      .readAsStringSync();
}

void main() {
  group('an ordinary application', () {
    test('queries the table by name, through the application database',
        () async {
      final String source = await generate();

      // Its own table, resolved the way an application resolves one --
      // dvTenantTable answers with the plain name unless a schema per tenant
      // is configured -- rather than through a module registration.
      expect(source, contains("FROM \${dvTenantTable('orders')}"));
      expect(source, isNot(contains("_dvModule.table('orders')")),
          reason: 'nothing mounted this, and nothing will');
      expect(source, isNot(contains('DVModuleData')),
          reason: 'nothing mounted this, and nothing will');
    });
  });

  group('a module', () {
    test('resolves its table through its own module id', () async {
      final String source = await generate(moduleId: 'store');

      expect(source, contains("DVModuleData('store')"),
          reason: 'the module id in its own pubspec is what it asks by');
      // The literal is gone: a query that still names the table directly is
      // one the parent's declaration cannot move.
      expect(source, isNot(contains("FROM orders'")),
          reason: 'a bare table name in the SQL ignores the data mode');
    });

    test('reads and writes through the database the mode chose', () async {
      final String source = await generate(moduleId: 'store');

      // Not `const DVDatabase()`: that is the application's connection, and
      // a database-isolated module's data is not in it.
      expect(source, isNot(contains('const DVDatabase().query')));
    });

    test('every statement it generates goes through the same resolution',
        () async {
      // SELECT, INSERT, UPDATE and DELETE all name the table. One left
      // behind is the shape of bug this is about: reads land in the right
      // place and writes do not, so the data is split across two tables and
      // looks merely missing.
      //
      // Every statement resolves the name through a call now, on both sides
      // -- an application through dvTenantTable, because a schema per tenant
      // changes what the table is called, and a module through its own
      // registration. So what must never appear is the bare name.
      final RegExp bare = RegExp(r'(FROM|INTO|UPDATE) orders\b');
      final RegExp resolved =
          RegExp(r"(FROM|INTO|UPDATE) \$\{(dvTenantTable|_dvModule\.table)\('orders'\)\}");

      final String application = await generate();
      // The patterns earn their keep on real output first. One that matched
      // nothing would pass every assertion below while checking nothing.
      expect(resolved.allMatches(application), isNotEmpty);
      expect(bare.allMatches(application), isEmpty);

      final String mounted = await generate(moduleId: 'store');
      expect(resolved.allMatches(mounted), isNotEmpty);
      expect(
        bare.allMatches(mounted),
        isEmpty,
        reason: "a module's statements resolve the table through DVModuleData",
      );
    });
  });
}
