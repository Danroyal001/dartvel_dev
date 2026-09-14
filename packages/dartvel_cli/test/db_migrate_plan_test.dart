// `dartvel db migrate --plan` and `--dry-run --against snapshot`.
//
// The deploy gate from Schema Evolution. `--plan` prints the class of every
// change a migration would make and applies none of them. `--against
// snapshot` rehearses against a snapshot of production's schema, server
// version and row counts, so the classification a developer sees is the one
// production would apply rather than the one their empty local database
// implies. A blocking change heading for production is refused without an
// explicit, logged override (DV-SCHEMA-002).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/db_command.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _order = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Order {
  final String id;
  final String total;
  const _Order({required this.id, required this.total});
}
''';

const String _orderWithNote = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Order {
  final String id;
  final String total;
  final String note;
  const _Order({required this.id, required this.total, required this.note});
}
''';

Future<void> _generate(Directory root, String model, String build) async {
  File(p.join(root.path, 'lib', 'models', 'order.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(model);
  await ModelGenerator.generate(
    root: root.path,
    pkgName: 'plan_app',
    buildId: build,
  );
}

void _pubspec(Directory root, {String provider = 'sqlite'}) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: plan_app\n'
    'dartvel:\n'
    '  database:\n'
    '    provider: $provider\n'
    '    path: app.db\n',
  );
}

void _snapshot(Directory root, Map<String, Object?> json, {String? path}) {
  File(path ?? p.join(root.path, '.dartvel', 'db', 'production.snapshot.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(json));
}

Map<String, Object?> _ordersSnapshot(String provider, String version) =>
    <String, Object?>{
      'provider': provider,
      'serverVersion': version,
      'tables': <String, Object?>{
        'orders': <String, Object?>{
          'columns': <String>['id', 'total'],
          'rows': 120000000,
        },
      },
    };

Future<void> _migrate(List<String> args) => (CommandRunner<void>(
  'dartvel',
  'test',
)..addCommand(DbCommand())).run(<String>['db', 'migrate', ...args]);

File _overrideLog(Directory root) =>
    File(p.join(root.path, '.dartvel', 'db', 'schema_overrides.jsonl'));

void main() {
  late Directory previous;
  late Directory root;

  setUp(() {
    previous = Directory.current;
    root = Directory.systemTemp.createTempSync('dartvel_migrate_plan_');
    Directory(
      p.join(root.path, 'lib', 'dartvel_client'),
    ).createSync(recursive: true);
    _pubspec(root);
    Directory.current = root;
    exitCode = 0;
  });

  tearDown(() {
    Directory.current = previous;
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  group('what a migration would change', () {
    test('a missing table is created and a missing column added', () {
      final List<DVSchemaChange> changes = dvPendingSchemaChanges(
        <Map<String, Object?>>[
          <String, Object?>{
            'table': 'orders',
            'columns': <String>['id', 'total', 'note'],
          },
          <String, Object?>{
            'table': 'invoices',
            'columns': <String>['id'],
          },
        ],
        <String, List<String>>{
          'orders': <String>['id', 'total', 'legacy'],
        },
      );

      expect(changes.map((DVSchemaChange c) => c.description), <String>[
        'add column orders.note TEXT',
        'create table invoices (id)',
      ]);
    });

    test('a column the model no longer has is not dropped', () {
      // Migrate never drops, so the plan does not claim it would.
      expect(
        dvPendingSchemaChanges(
          <Map<String, Object?>>[
            <String, Object?>{
              'table': 'orders',
              'columns': <String>['id'],
            },
          ],
          <String, List<String>>{
            'orders': <String>['id', 'legacy'],
          },
        ),
        isEmpty,
      );
    });
  });

  group('--plan', () {
    test('classifies the new column against the local database', () async {
      await _generate(root, _order, 'b1');
      await dvApplyMigrations(root.path);
      await _generate(root, _orderWithNote, 'b2');

      final DVSchemaPlan plan = await dvPlanMigration(root.path);

      final DVSchemaPlanStep step = plan.steps.single;
      expect(step.change.description, 'add column orders.note TEXT');
      expect(step.changeClass, DVSchemaChangeClass.instant);
      expect(step.classifiedByAdapter, isTrue);
    });

    test('applies nothing', () async {
      await _generate(root, _order, 'b1');
      await dvApplyMigrations(root.path);
      await _generate(root, _orderWithNote, 'b2');

      await _migrate(<String>['--plan']);

      expect(exitCode, 0);
      expect(
        await dvSqliteColumns(p.join(root.path, 'app.db'), 'orders'),
        isNot(contains('note')),
      );
    });

    test('does not create a database that is not there', () async {
      await _generate(root, _order, 'b1');

      await _migrate(<String>['--plan']);

      expect(exitCode, 0);
      expect(File(p.join(root.path, 'app.db')).existsSync(), isFalse);
      final DVSchemaPlan plan = await dvPlanMigration(root.path);
      expect(plan.steps.single.change, isA<DVCreateTable>());
    });
  });

  group('--dry-run --against snapshot', () {
    test(
      'classifies with production\'s server and carries its row counts',
      () async {
        await _generate(root, _orderWithNote, 'b1');
        _snapshot(root, _ordersSnapshot('postgres', '10.23'));

        final DVSchemaPlan plan = await dvPlanMigration(
          root.path,
          against: DVSchemaSnapshot.fromJson(
            _ordersSnapshot('postgres', '10.23'),
          ),
        );
        expect(
          plan.steps.single.change.description,
          'add column orders.note TEXT',
        );
        expect(plan.steps.single.rows, 120000000);
        expect(plan.steps.single.classifiedByAdapter, isTrue);

        await _migrate(<String>['--dry-run', '--against', 'snapshot']);
        expect(exitCode, 0);
        // A rehearsal: no database was touched.
        expect(File(p.join(root.path, 'app.db')).existsSync(), isFalse);
      },
    );

    test('a change production\'s server cannot classify is refused', () async {
      // MySQL 5.7 is not a server the MySQL adapter describes, so adding even
      // a nullable column there is unclassified and treated as blocking.
      await _generate(root, _orderWithNote, 'b1');
      _snapshot(root, _ordersSnapshot('mysql', '5.7.44'));

      await _migrate(<String>['--dry-run', '--against', 'snapshot']);

      expect(exitCode, 1);
      expect(_overrideLog(root).existsSync(), isFalse);
    });

    test(
      'an override lets the rehearsal pass, and a rehearsal logs nothing',
      () async {
        await _generate(root, _orderWithNote, 'b1');
        _snapshot(root, _ordersSnapshot('mysql', '5.7.44'));

        await _migrate(<String>[
          '--dry-run',
          '--against',
          'snapshot',
          '--allow-blocking',
          'maintenance window agreed',
        ]);

        expect(exitCode, 0);
        expect(_overrideLog(root).existsSync(), isFalse);
      },
    );

    test('the snapshot file can be named', () async {
      await _generate(root, _orderWithNote, 'b1');
      final String elsewhere = p.join(root.path, 'prod.json');
      _snapshot(root, _ordersSnapshot('mysql', '5.7.44'), path: elsewhere);

      await _migrate(<String>[
        '--dry-run',
        '--against',
        'snapshot',
        '--snapshot',
        elsewhere,
      ]);
      expect(exitCode, 1);
    });

    test('a missing snapshot is an error, not an empty production', () async {
      await _generate(root, _orderWithNote, 'b1');

      await _migrate(<String>['--dry-run', '--against', 'snapshot']);

      expect(exitCode, 1);
    });

    test('--against takes only snapshot', () async {
      // Refused by the argument parser, as every other bad option value is:
      // the command runner turns this into a usage error before the command
      // runs, so nothing is planned against a production that means nothing.
      await _generate(root, _orderWithNote, 'b1');
      await expectLater(
        _migrate(<String>['--dry-run', '--against', 'production']),
        throwsA(isA<UsageException>()),
      );
      expect(File(p.join(root.path, 'app.db')).existsSync(), isFalse);
    });

    test('--against without --dry-run or --plan is refused', () async {
      // Rehearsing and applying are different requests; a flag naming a
      // snapshot should not quietly apply against the local database.
      await _generate(root, _orderWithNote, 'b1');
      _snapshot(root, _ordersSnapshot('postgres', '16.2'));

      await _migrate(<String>['--against', 'snapshot']);

      expect(exitCode, 1);
      expect(File(p.join(root.path, 'app.db')).existsSync(), isFalse);
    });
  });

  group('--production', () {
    test('a provider nothing can classify needs an override', () async {
      // The CLI has no connection to a managed Postgres, so nothing can say
      // what its changes cost; against production that is blocking.
      _pubspec(root, provider: 'postgres');
      await _generate(root, _order, 'b1');

      await _migrate(<String>['--production']);

      expect(exitCode, 1);
      expect(
        File(
          p.join(root.path, '.dart_tool', 'dartvel_migration.sql'),
        ).existsSync(),
        isFalse,
      );
    });

    test('and the override is written down with its reason', () async {
      _pubspec(root, provider: 'postgres');
      await _generate(root, _order, 'b1');

      await _migrate(<String>[
        '--production',
        '--allow-blocking',
        '3am, everyone told',
      ]);

      expect(exitCode, 0);
      final List<String> lines = _overrideLog(root).readAsLinesSync();
      final Map<String, Object?> record =
          jsonDecode(lines.single) as Map<String, Object?>;
      expect(record['code'], 'DV-SCHEMA-002');
      expect(record['reason'], '3am, everyone told');
      expect(record['changes'], <String>['create table orders (id, total)']);
      // And the migration went on to do what it does for this provider.
      expect(
        File(
          p.join(root.path, '.dart_tool', 'dartvel_migration.sql'),
        ).existsSync(),
        isTrue,
      );
    });

    test('an instant change on SQLite needs no override', () async {
      await _generate(root, _order, 'b1');

      await _migrate(<String>['--production']);

      expect(exitCode, 0);
      expect(
        await dvSqliteColumns(p.join(root.path, 'app.db'), 'orders'),
        containsAll(<String>['id', 'total']),
      );
      expect(_overrideLog(root).existsSync(), isFalse);
    });
  });
}
