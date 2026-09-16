// No framework table declares a timestamp, duration or quantity 32 bits wide.
//
// SQLite's INTEGER is 64 bits and PostgreSQL's and MySQL's are 32, so a
// column that holds `DateTime.millisecondsSinceEpoch` works in every local
// suite and refuses every row on a server. The live PostgreSQL suite proves
// the stores that exist today; this is what stops the next table from being
// written the same way, on a machine with no server to catch it.
import 'dart:io';

import 'package:dartvel_core/src/database/framework_tables.dart';
import 'package:test/test.dart';

/// A column name that says it holds a time, a duration or an amount:
/// `created_at`, `at_us`, `backoff_ms`, `expires_at`, `quantity`.
final RegExp _wideName = RegExp(
  r'(^|_)(at|us|ms|micros|millis|seconds|until|expires|bytes|size|quantity)$',
);

/// `name TYPE` in DDL, and `DVRecordColumn('name', type: 'TYPE')` in the
/// generator's column lists. Upper case only: `int x` is Dart, not SQL.
final RegExp _declaration = RegExp(
  r"\b([a-z_][a-z0-9_]*)'?\s*(?:,\s*type:\s*')?"
  r'(INTEGER|INT|INT4|SMALLINT|MEDIUMINT|TINYINT|SERIAL)\b',
);

/// Every 32-bit declaration of a wide-named column in [source], as
/// `line: column TYPE`. Comments are skipped: they describe, they do not
/// create.
List<String> narrowDeclarations(String source) => <String>[
  for (final (int index, String line) in source.split('\n').indexed)
    if (!line.trimLeft().startsWith('//'))
      for (final RegExpMatch match in _declaration.allMatches(line))
        if (_wideName.hasMatch(match.group(1)!))
          '${index + 1}: ${match.group(1)} ${match.group(2)}',
];

void main() {
  group('the scan', () {
    test('finds a narrow timestamp in DDL and in a generator column', () {
      expect(
        narrowDeclarations(
          "  'created_at INTEGER, last_seen_at INT NOT NULL, '\n"
          "  DVRecordColumn('occurred_at', type: 'INTEGER'),\n"
          "  'backoff_ms SMALLINT, quantity MEDIUMINT)'",
        ),
        <String>[
          '1: created_at INTEGER',
          '1: last_seen_at INT',
          '2: occurred_at INTEGER',
          '3: backoff_ms SMALLINT',
          '3: quantity MEDIUMINT',
        ],
      );
    });

    test('leaves wide columns, counters, flags, Dart and comments alone', () {
      expect(
        narrowDeclarations(
          "  'created_at BIGINT, attempts INTEGER, confirmed INTEGER, '\n"
          '  final int created_at = 0;\n'
          '  // created_at INTEGER was the bug\n'
          "  DVRecordColumn('deleted', type: 'INTEGER'),",
        ),
        isEmpty,
      );
    });
  });

  test('no package declares one', () {
    // Run from packages/dartvel_core, which is where `dart test` runs.
    final Directory packages = Directory('..').absolute;
    final List<String> found = <String>[];
    var scanned = 0;
    for (final FileSystemEntity entity in packages.listSync()) {
      final Directory lib = Directory('${entity.path}/lib');
      if (entity is! Directory || !lib.existsSync()) continue;
      for (final FileSystemEntity file in lib.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        scanned++;
        for (final String hit in narrowDeclarations(file.readAsStringSync())) {
          found.add('${file.path}:$hit');
        }
      }
    }
    // A scan that read nothing would pass.
    expect(scanned, greaterThan(500));
    expect(
      found,
      isEmpty,
      reason: 'Declare these BIGINT: 32 bits on PostgreSQL and MySQL.',
    );
  });

  test(
    'every table declaring BIGINT is made through dvEnsureFrameworkTable',
    () {
      // A table made with a bare CREATE TABLE IF NOT EXISTS keeps whatever
      // types an earlier release gave it, so a store whose DDL says BIGINT and
      // never widens goes on refusing every row on a server that already has
      // the table.
      final List<String> bare = <String>[];
      for (final FileSystemEntity file in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('framework_tables.dart')) continue;
        final String source = file.readAsStringSync();
        if (source.contains('CREATE TABLE') &&
            RegExp(r'\b[a-z_]+ BIGINT\b').hasMatch(source) &&
            !source.contains('dvEnsureFrameworkTable(')) {
          bare.add(file.path);
        }
      }
      expect(bare, isEmpty);
    },
  );

  group('dvBigIntColumnsIn', () {
    test('reads the table and its BIGINT columns from the DDL', () {
      final ({String table, List<String> columns}) read = dvBigIntColumnsIn(
        'CREATE TABLE IF NOT EXISTS dv_sessions (token_hash TEXT, '
        'created_at BIGINT, revoked_at BIGINT, claims TEXT)',
      );
      expect(read.table, 'dv_sessions');
      expect(read.columns, <String>['created_at', 'revoked_at']);
    });

    test('reads a schema-qualified table, as a tenant schema names it', () {
      // A record table's name may be `tenant.orders`, and the stores built
      // on one name their own tables after it.
      final ({String table, List<String> columns}) read = dvBigIntColumnsIn(
        'CREATE TABLE IF NOT EXISTS acme.orders__clock (record_key TEXT, '
        'at_micros BIGINT)',
      );
      expect(read.table, 'acme.orders__clock');
      expect(read.columns, <String>['at_micros']);
    });

    test('refuses DDL it cannot read rather than widening nothing', () {
      expect(
        () => dvBigIntColumnsIn('CREATE TABLE (x BIGINT)'),
        throwsArgumentError,
      );
    });
  });

  group('dvWidenToBigIntSql', () {
    test('PostgreSQL keeps NOT NULL on its own', () {
      expect(
        dvWidenToBigIntSql('dv_jobs', <({String name, bool nullable})>[
          (name: 'created_at', nullable: false),
          (name: 'backoff_ms', nullable: false),
        ], mysql: false),
        'ALTER TABLE dv_jobs ALTER COLUMN created_at TYPE BIGINT, '
        'ALTER COLUMN backoff_ms TYPE BIGINT',
      );
    });

    test('MySQL restates NOT NULL, which MODIFY would otherwise drop', () {
      expect(
        dvWidenToBigIntSql('dv_jobs', <({String name, bool nullable})>[
          (name: 'created_at', nullable: false),
          (name: 'revoked_at', nullable: true),
        ], mysql: true),
        'ALTER TABLE dv_jobs MODIFY COLUMN created_at BIGINT NOT NULL, '
        'MODIFY COLUMN revoked_at BIGINT NULL',
      );
    });
  });
}
