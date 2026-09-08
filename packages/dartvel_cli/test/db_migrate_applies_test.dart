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

    test('the columns are the ones the model itself carries', () async {
      // Two sources for one table is how the migration creates one shape and
      // the queries read another, and neither side would notice.
      //
      // The two statements are not the same string, and should not be: the
      // model resolves its table name at run time, because under
      // schemaPerTenant that name depends on which tenant is asking. What
      // has to agree is the columns, which is what a query names and what a
      // CREATE TABLE provides.
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
      final List<String> columns =
          (orders['columns']! as List<Object?>).cast<String>();

      // The migration statement is runnable SQL, not a Dart interpolation.
      expect(createSql, isNot(contains('\$')));
      expect(createSql, contains('CREATE TABLE IF NOT EXISTS orders ('));
      for (final String column in columns) {
        expect(createSql, contains('$column TEXT'));
        expect(models, contains(column));
      }
      // And the model's own statement resolves its name for the tenant
      // rather than writing it in.
      expect(models, contains("dvTenantTable('orders')"));
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

  group('a table that already exists', () {
    // CREATE TABLE IF NOT EXISTS is a no-op against a table that is already
    // there, so a model that gained a column since the table was made never
    // gets it, and every query naming that column fails against a database
    // the migration has just reported as migrated.
    const String unscoped = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Order {
  final String id;
  final String total;
  const _Order({required this.id, required this.total});
}
''';

    Future<Directory> migratedThenScoped({int rows = 0}) async {
      final Directory root = await _project(unscoped);
      await dvApplyMigrations(root.path);
      for (int i = 0; i < rows; i++) {
        await dvSqliteExecute(
          p.join(root.path, 'app.db'),
          "INSERT INTO orders (id, total) VALUES ('$i', '10')",
        );
      }
      // The model gains the annotation after the table exists, which is the
      // whole case: a deployment turning multi-tenancy on.
      File(p.join(root.path, 'lib', 'models', 'order.dart'))
          .writeAsStringSync(_order);
      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'migrate_app',
        buildId: 'test-build-2',
      );
      return root;
    }

    test('an added column reaches an empty table', () async {
      final Directory root = await migratedThenScoped();
      addTearDown(() => root.deleteSync(recursive: true));

      final DVMigrationReport report = await dvApplyMigrations(root.path);

      expect(report.added, contains('orders.dv_tenant'));
      expect(
        await dvSqliteColumns(p.join(root.path, 'app.db'), 'orders'),
        contains('dv_tenant'),
      );
    });

    test('a table with rows is refused until somebody says whose they are',
        () async {
      // The rows were written before the column existed, so they belong to
      // no tenant -- and a predicate on every read hides all of them from
      // everybody. That is not a smaller version of the feature: the table
      // reads as empty, which looks like data loss and is indistinguishable
      // from it until somebody checks.
      final Directory root = await migratedThenScoped(rows: 3);
      addTearDown(() => root.deleteSync(recursive: true));

      final DVMigrationReport report = await dvApplyMigrations(root.path);

      expect(report.needsTenant, contains('orders'));
      expect(report.added, isNot(contains('orders.dv_tenant')));
      // Nothing altered, so the application on the old code still works.
      expect(
        await dvSqliteColumns(p.join(root.path, 'app.db'), 'orders'),
        isNot(contains('dv_tenant')),
      );
    });

    test('naming the tenant migrates the rows to it', () async {
      final Directory root = await migratedThenScoped(rows: 3);
      addTearDown(() => root.deleteSync(recursive: true));

      final DVMigrationReport report =
          await dvApplyMigrations(root.path, tenant: 'acme');

      expect(report.needsTenant, isEmpty);
      expect(report.added, contains('orders.dv_tenant'));
      expect(
        await dvSqliteRows(
          p.join(root.path, 'app.db'),
          "SELECT COUNT(*) AS n FROM orders WHERE dv_tenant = 'acme'",
        ),
        <Map<String, Object?>>[
          <String, Object?>{'n': 3},
        ],
      );
    });

    test('orphaning them is possible and has to be asked for', () async {
      // A deployment whose existing rows genuinely belong to nobody -- a
      // staging database, a table being emptied -- can say so. What it
      // cannot do is have that happen by default.
      final Directory root = await migratedThenScoped(rows: 3);
      addTearDown(() => root.deleteSync(recursive: true));

      final DVMigrationReport report =
          await dvApplyMigrations(root.path, orphanExistingRows: true);

      expect(report.needsTenant, isEmpty);
      expect(report.added, contains('orders.dv_tenant'));
      expect(
        await dvSqliteRows(
          p.join(root.path, 'app.db'),
          'SELECT COUNT(*) AS n FROM orders WHERE dv_tenant IS NULL',
        ),
        <Map<String, Object?>>[
          <String, Object?>{'n': 3},
        ],
      );
    });

    test('an ordinary added column needs no permission', () async {
      // Only the tenant column hides rows. A new field is null on the old
      // ones, which is what adding a field means.
      final Directory root = await _project(_order);
      addTearDown(() => root.deleteSync(recursive: true));
      await dvApplyMigrations(root.path);
      await dvSqliteExecute(
        p.join(root.path, 'app.db'),
        "INSERT INTO orders (dv_tenant, id, total) VALUES ('acme', '1', '10')",
      );

      File(p.join(root.path, 'lib', 'models', 'order.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(tenantScoped: true)
class _Order {
  final String id;
  final String total;
  final String note;
  const _Order({required this.id, required this.total, required this.note});
}
''');
      await ModelGenerator.generate(
        root: root.path,
        pkgName: 'migrate_app',
        buildId: 'test-build-3',
      );

      final DVMigrationReport report = await dvApplyMigrations(root.path);

      expect(report.added, contains('orders.note'));
      expect(report.needsTenant, isEmpty);
    });
  });
}
