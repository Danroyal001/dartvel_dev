// `dartvel db migrate` said it had migrated and had touched no database.
//
// It discovered the local schema, printed "[+] Migrated table: orders" for
// each one and "Migration complete. N tables synced successfully", and then
// wrote a JSON snapshot. No statement was ever executed. The generated
// `createTableSql` -- one per model, correct, carrying the tenant column --
// was called by nothing anywhere in the repository, and the index said
// "dartvel db migrate creates those tables under the same names".
//
// Two halves, and they have to arrive together. The generator writes the
// statements down where something other than Dart can read them, and the
// command runs them. Written by the generator rather than rebuilt here,
// because a second parser deciding what a table's columns are is how the
// migration comes to create one table and the queries to read another.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/commands/db_command.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _order = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(tenantScoped: true)
class _Order {
  final String id;
  final String total;
  const _Order({required this.id, required this.total});
}
''';

Future<Directory> _project(String model) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_migrate_');
  Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
  Directory(
    p.join(root.path, 'lib', 'dartvel_client'),
  ).createSync(recursive: true);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: migrate_app\n'
    'dartvel:\n'
    '  database:\n'
    '    provider: sqlite\n'
    '    path: app.db\n',
  );
  File(p.join(root.path, 'lib', 'models', 'order.dart'))
      .writeAsStringSync(model);
  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'migrate_app',
    buildId: 'test-build',
  );
  return root;
}

void main() {
  group('the generator writes the statements down', () {
    test('one per model, with the columns the queries use', () async {
      final Directory root = await _project(_order);
      addTearDown(() => root.deleteSync(recursive: true));

      final File artifact = File(
        p.join(root.path, '.dart_tool', 'dartvel_schema.g.json'),
      );
      expect(artifact.existsSync(), isTrue);

      final Map<String, Object?> schema =
          jsonDecode(artifact.readAsStringSync()) as Map<String, Object?>;
      final List<Object?> tables = schema['tables']! as List<Object?>;
      final Map<String, Object?> orders =
          tables.first as Map<String, Object?>;

      expect(orders['table'], 'orders');
      expect(orders['model'], 'Order');
      expect(orders['tenantScoped'], isTrue);
      // The tenant column is in the statement, or the migration creates a
      // table every generated query then fails against.
      expect(orders['createSql'], contains('dv_tenant'));
      expect(orders['createSql'], startsWith('CREATE TABLE IF NOT EXISTS'));
      expect(
        (orders['columns']! as List<Object?>).cast<String>(),
        containsAll(<String>['dv_tenant', 'id', 'total']),
      );
    });

    test('the statement is the one the model itself carries', () async {
      // Two sources for one table is how the migration creates one shape and
      // the queries read another, and neither side would notice.
      final Directory root = await _project(_order);
      addTearDown(() => root.deleteSync(recursive: true));

      final String models = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      ).readAsStringSync();
      final Map<String, Object?> schema = jsonDecode(
        File(p.join(root.path, '.dart_tool', 'dartvel_schema.g.json'))
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final Map<String, Object?> orders =
          (schema['tables']! as List<Object?>).first as Map<String, Object?>;
      final String createSql = orders['createSql']! as String;

      expect(models, contains(createSql));
    });
  });

  group('migrate runs them', () {
    test('the table is there afterwards, with its columns', () async {
      final Directory root = await _project(_order);
      addTearDown(() => root.deleteSync(recursive: true));

      final DVMigrationReport report = await dvApplyMigrations(root.path);

      expect(report.applied, contains('orders'));
      expect(report.skippedReason, isNull);

      final List<String> columns = await dvSqliteColumns(
        p.join(root.path, 'app.db'),
        'orders',
      );
      expect(columns, containsAll(<String>['dv_tenant', 'id', 'total']));
    });

    test('running it twice is not an error', () async {
      // A migration somebody runs on every deploy has to be safe to run on
      // every deploy.
      final Directory root = await _project(_order);
      addTearDown(() => root.deleteSync(recursive: true));

      await dvApplyMigrations(root.path);
      final DVMigrationReport again = await dvApplyMigrations(root.path);

      expect(again.applied, contains('orders'));
    });

    test('a provider it cannot reach is said, not claimed', () async {
      // The failure this whole change exists to remove: reporting success
      // for work that did not happen. The CLI has no connection to a managed
      // Postgres, and saying so with the statements to run is worth more
      // than a green line.
      final Directory root = await _project(_order);
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
        'name: migrate_app\n'
        'dartvel:\n'
        '  database:\n'
        '    provider: postgres\n',
      );

      final DVMigrationReport report = await dvApplyMigrations(root.path);

      expect(report.applied, isEmpty);
      expect(report.skippedReason, contains('postgres'));
      // With the statements written out, so there is something to run.
      expect(
        File(p.join(root.path, '.dart_tool', 'dartvel_migration.sql'))
            .existsSync(),
        isTrue,
      );
    });

    test('a project with no models migrates nothing and says so', () async {
      final Directory root =
          await Directory.systemTemp.createTemp('dartvel_migrate_empty_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      File(p.join(root.path, 'pubspec.yaml'))
          .writeAsStringSync('name: empty_app\n');

      final DVMigrationReport report = await dvApplyMigrations(root.path);

      expect(report.applied, isEmpty);
      expect(report.skippedReason, isNull);
    });
  });
}
