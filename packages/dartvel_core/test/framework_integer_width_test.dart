// No framework table declares a timestamp, duration or quantity 32 bits wide.
//
// SQLite's INTEGER is 64 bits and PostgreSQL's and MySQL's are 32, so a
// column that holds `DateTime.millisecondsSinceEpoch` works in every local
// suite and refuses every row on a server. The live PostgreSQL suite proves
// the stores that exist today; this is what stops the next table from being
// written the same way, on a machine with no server to catch it.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
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
  _columnTypes();

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

// ---------------------------------------------------------------------------
// Column types.
//
// SQLite takes `CREATE TABLE t (id, value)` and gives every column BLOB
// affinity. PostgreSQL and MySQL refuse the statement outright -- "syntax
// error at end of input" -- so a store written that way passed every local
// suite and could not make its table on a server at all. MySQL also refuses a
// TEXT column in a key, and PostgreSQL reads REAL as a 4-bit-short float4
// that keeps seven significant digits.

/// Every `CREATE TABLE` in [source] whose column list is spelled out in
/// string literals, as `line: problem`. A column list built at run time --
/// `($columns)` -- is not readable here, and dvEnsureFrameworkTable checks
/// it when the statement runs.
List<String> columnTypeProblems(String source) {
  final List<String> found = <String>[];
  final List<String> lines = source.split('\n');
  for (final (int index, String line) in lines.indexed) {
    if (line.trimLeft().startsWith('//')) continue;
    for (final RegExpMatch match in RegExp('CREATE TABLE').allMatches(line)) {
      final int offset =
          lines
              .take(index)
              .fold<int>(0, (int n, String l) => n + l.length + 1) +
          match.start;
      final String? ddl = dvLiteralStatementAt(source, offset);
      if (ddl == null) continue;
      for (final String problem in dvFrameworkTableProblems(ddl)) {
        found.add('${index + 1}: $problem');
      }
    }
  }
  return found;
}

void _columnTypes() {
  group('dvFrameworkTableProblems', () {
    test('names a column with no type, and a table constraint is not one', () {
      expect(
        dvFrameworkTableProblems(
          'CREATE TABLE IF NOT EXISTS t (id VARCHAR(64), value, seq NOT NULL, '
          'PRIMARY KEY (id))',
        ),
        <String>['t.value has no type', 't.seq has no type'],
      );
    });

    test('names TEXT in a key, which MySQL refuses', () {
      expect(
        dvFrameworkTableProblems(
          'CREATE TABLE t (id TEXT PRIMARY KEY, a TEXT NOT NULL, '
          'b VARCHAR(64), n BIGINT, UNIQUE (a, b, n))',
        ),
        <String>['t.id is TEXT in a key', 't.a is TEXT in a key'],
      );
    });

    test('names REAL and FLOAT, which are float4 somewhere', () {
      expect(
        dvFrameworkTableProblems(
          'CREATE TABLE t (amount REAL NOT NULL, rate FLOAT, '
          'total DOUBLE PRECISION)',
        ),
        <String>['t.amount is REAL', 't.rate is FLOAT'],
      );
    });

    test('passes a table every server can make', () {
      expect(
        dvFrameworkTableProblems(
          'CREATE TABLE IF NOT EXISTS dv_jobs (id VARCHAR(255) PRIMARY KEY, '
          'payload TEXT NOT NULL, created_at BIGINT NOT NULL, '
          'amount DOUBLE PRECISION, UNIQUE (id, created_at))',
        ),
        isEmpty,
      );
    });
  });

  group('dvEnsureFrameworkTable', () {
    test('refuses an untyped column before running anything', () async {
      final MemoryDVDatabaseAdapter memory = MemoryDVDatabaseAdapter();
      await expectLater(
        dvEnsureFrameworkTable(memory, 'CREATE TABLE t (id TEXT, value)'),
        throwsA(isA<DVFrameworkTableError>()),
      );
      // Not made: a table that exists would make the next call succeed.
      await memory.execute('CREATE TABLE t (id TEXT)');
    });
  });

  group('the source scan', () {
    test('reads a statement split across literals, and skips a built one', () {
      expect(
        columnTypeProblems(
          '  await db.execute(\n'
          "    'CREATE TABLE IF NOT EXISTS \$table (id TEXT, '\n"
          "    'value, amount REAL)',\n"
          '  );\n'
          "  await db.execute('CREATE TABLE IF NOT EXISTS \$t (\$columns)');\n"
          '  // CREATE TABLE t (untyped) in a comment\n'
          "  help: 'sqflite CREATE TABLE statements under lib/.';\n",
        ),
        <String>[r'2: $table.value has no type', r'2: $table.amount is REAL'],
      );
    });

    test('no package makes a table a server refuses', () {
      final Directory packages = Directory('..').absolute;
      final List<String> found = <String>[];
      var statements = 0;
      for (final FileSystemEntity entity in packages.listSync()) {
        final Directory lib = Directory('${entity.path}/lib');
        if (entity is! Directory || !lib.existsSync()) continue;
        for (final FileSystemEntity file in lib.listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;
          final String source = file.readAsStringSync();
          statements += 'CREATE TABLE'.allMatches(source).length;
          for (final String hit in columnTypeProblems(source)) {
            found.add('${file.path}:$hit');
          }
        }
      }
      // A scan that found no statements would pass.
      expect(statements, greaterThan(30));
      expect(found, isEmpty);
    });
  });
}

/// The SQL of the statement whose string literal holds [offset], read across
/// the adjacent literals it is split into, up to the parenthesis that closes
/// its column list. Interpolations are kept as written. Null when the
/// statement ends before a column list opens: prose that mentions
/// `CREATE TABLE`.
String? dvLiteralStatementAt(String source, int offset) {
  // The quote this literal opened with.
  var start = offset;
  while (start > 0 && source[start - 1] != "'" && source[start - 1] != '"') {
    if (source[start - 1] == '\n') {
      // A multi-line literal: the statement starts in the ''' above it.
      final int triple = source.lastIndexOf("'''", start);
      if (triple < 0 || start - triple > 200) return null;
      start = triple + 3;
      break;
    }
    start--;
  }
  if (start == 0) return null;
  final String char = source[start - 1];
  String? quote = start >= 3 && source.substring(start - 3, start) == char * 3
      ? char * 3
      : char;

  final StringBuffer out = StringBuffer();
  var depth = 0;
  var opened = false;
  var i = offset;
  while (i < source.length) {
    final String c = source[i];
    if (quote != null) {
      if (source.startsWith(quote, i)) {
        i += quote.length;
        quote = null;
      } else if (c == r'\') {
        out.write(source.substring(i, (i + 2).clamp(0, source.length)));
        i += 2;
      } else if (c == r'$' && i + 1 < source.length && source[i + 1] == '{') {
        // Skipped whole, quotes and parentheses inside it included, and kept
        // as an empty interpolation: its value is only known at run time.
        var braces = 0;
        i++;
        do {
          if (source[i] == '{') braces++;
          if (source[i] == '}') braces--;
          i++;
        } while (braces > 0 && i < source.length);
        out.write(r'${}');
      } else {
        out.write(c);
        if (c == '(') {
          depth++;
          opened = true;
        } else if (c == ')') {
          depth--;
          if (opened && depth == 0) {
            final String sql = out.toString();
            return RegExp(
                  r'^CREATE TABLE\s+(?:IF NOT EXISTS\s+)?[^\s(,]+\s*\(',
                ).hasMatch(sql)
                ? sql
                : null;
          }
        }
        i++;
      }
    } else if (c == ';') {
      return null;
    } else if (source.startsWith('//', i)) {
      final int end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
    } else if (source.startsWith("'''", i) || source.startsWith('"""', i)) {
      quote = source.substring(i, i + 3);
      i += 3;
    } else if (c == "'" || c == '"') {
      quote = c;
      i++;
    } else {
      i++;
    }
  }
  return null;
}
