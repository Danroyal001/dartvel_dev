// Every column a framework table declares has a type.
//
// SQLite takes `CREATE TABLE t (id, value)` and gives each column no
// affinity. PostgreSQL and MySQL refuse it with a syntax error, before a row
// is written, so a store that declares one works in every local suite and
// cannot start against a server. The live PostgreSQL suite proves the stores
// that exist today; this is what stops the next one from being written the
// same way, on a machine with no server to catch it.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
// The record layer, which an application does not name and a test of it
// does.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

/// Where an interpolation stood in a string literal.
const String _hole = '\x00';

/// Every string in [source] as the program would build it: adjacent literals
/// joined, each interpolation replaced by [_hole], with the line it starts
/// on. Comments are skipped: they describe, they do not create.
List<({int line, String text})> stringsIn(String source) {
  final List<({int line, String text})> strings = <({int line, String text})>[];
  final StringBuffer current = StringBuffer();
  int currentLine = 0;
  bool open = false;
  int i = 0;

  int lineAt(int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;

  void close() {
    if (open) strings.add((line: currentLine, text: current.toString()));
    current.clear();
    open = false;
  }

  // Reads the literal starting at [start] (its opening quote), appending its
  // contents to [out], and returns the offset just past its closing quote.
  int readString(int start, StringBuffer? out, {required bool raw}) {
    final String quote = source[start];
    final bool triple = source.startsWith(quote * 3, start);
    final String end = triple ? quote * 3 : quote;
    int j = start + end.length;
    while (j < source.length) {
      if (source.startsWith(end, j)) return j + end.length;
      final String c = source[j];
      if (!raw && c == r'\') {
        out?.write(source.substring(j, j + 2));
        j += 2;
        continue;
      }
      if (!raw && c == r'$') {
        if (j + 1 < source.length && source[j + 1] == '{') {
          int depth = 1;
          j += 2;
          while (j < source.length && depth > 0) {
            final String d = source[j];
            if (d == "'" || d == '"') {
              j = readString(j, null, raw: false);
              continue;
            }
            if (d == '{') depth++;
            if (d == '}') depth--;
            j++;
          }
          out?.write(_hole);
          continue;
        }
        final Match? name = RegExp(
          r'[A-Za-z_][A-Za-z0-9_]*',
        ).matchAsPrefix(source, j + 1);
        if (name != null) {
          out?.write(_hole);
          j = name.end;
          continue;
        }
      }
      out?.write(c);
      j++;
    }
    return j;
  }

  while (i < source.length) {
    final String c = source[i];
    if (source.startsWith('//', i)) {
      final int newline = source.indexOf('\n', i);
      i = newline < 0 ? source.length : newline;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final int shut = source.indexOf('*/', i + 2);
      i = shut < 0 ? source.length : shut + 2;
      continue;
    }
    final bool raw =
        c == 'r' &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"') &&
        (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i - 1]));
    if (raw || c == "'" || c == '"') {
      if (!open) {
        open = true;
        currentLine = lineAt(i);
      }
      i = readString(raw ? i + 1 : i, current, raw: raw);
      continue;
    }
    if (c.trim().isNotEmpty) close();
    i++;
  }
  close();
  return strings;
}

final RegExp _createTable = RegExp(
  r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[^\s(]+\s*\(',
  caseSensitive: false,
);

final RegExp _addColumn = RegExp(
  r'ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?([^\s,)]+)([^,)]*)',
  caseSensitive: false,
);

final RegExp _constraint = RegExp(
  r'^(?:UNIQUE|PRIMARY\s+KEY|FOREIGN\s+KEY|CHECK|CONSTRAINT)\b',
  caseSensitive: false,
);

/// What [sql] declares: `untyped` names each column given no type, and
/// `dynamic` each definition built at run time, which only running it can
/// check.
({List<String> untyped, List<String> dynamic}) columnsIn(String sql) {
  final List<String> untyped = <String>[];
  final List<String> dynamic = <String>[];
  for (final RegExpMatch create in _createTable.allMatches(sql)) {
    int depth = 1;
    int j = create.end;
    final List<String> items = <String>[];
    final StringBuffer item = StringBuffer();
    for (; j < sql.length && depth > 0; j++) {
      final String c = sql[j];
      if (c == '(') depth++;
      if (c == ')') depth--;
      if ((c == ',' && depth == 1) || depth == 0) {
        items.add(item.toString().trim());
        item.clear();
      } else {
        item.write(c);
      }
    }
    if (depth > 0) {
      dynamic.add(sql.substring(create.start));
      continue;
    }
    for (final String definition in items) {
      if (definition.isEmpty || _constraint.hasMatch(definition)) continue;
      if (definition.contains(_hole)) {
        dynamic.add(definition);
      } else if (definition.split(RegExp(r'\s+')).length < 2) {
        untyped.add(definition);
      }
    }
  }
  for (final RegExpMatch add in _addColumn.allMatches(sql)) {
    final String column = add.group(1)!;
    final String rest = add.group(2)!.trim();
    if (column.contains(_hole) || rest.startsWith(_hole)) {
      dynamic.add('ADD COLUMN ${add.group(0)!.substring(11).trim()}');
    } else if (rest.isEmpty) {
      untyped.add(column);
    }
  }
  return (untyped: untyped, dynamic: dynamic);
}

/// A string that reads as SQL rather than as a sentence about it.
String _show(String text) => text.replaceAll(_hole, r'$…');

/// Definitions built at run time, and why each one is typed. Every entry is
/// a promise a scan cannot keep, so each names what does.
const Map<String, String> _dynamicSites = <String, String>{
  'dartvel_core/lib/src/data/record_history.dart':
      'DVRecordTable writes its types; every framework record table passes '
      'them, checked below and run below.',
  'dartvel_core/lib/src/metering/meters.dart':
      'The meter store interpolates one typed constant twice; run below.',
  'dartvel_core/lib/src/database/framework_tables.dart':
      'dvEnsureFrameworkColumns refuses a column with no SQL type before it '
      'writes one; run in framework_added_columns_test.',
  'dartvel_core/lib/src/schema/schema_change.dart':
      "A change's description, for people. Nothing executes it.",
  'dartvel_cli/lib/src/generators/record_columns.dart':
      'The history table is built from dvHistoryColumns, each with a type.',
  'dartvel_cli/lib/src/generators/model_generator.dart':
      "A model's columns are TEXT and dvRecordColumns, each with a type.",
  'dartvel_core/lib/src/schema/generated_schema.dart':
      "dvAddColumnSql writes the change's type, TEXT when none is recorded.",
  'dartvel_core/lib/src/database/records.dart':
      'Every column comes from a DVRecordShape field, whose DVFieldType is a '
      'closed set of SQL types; a text key is VARCHAR(255). Run below.',
};

class _Ddl implements DVDatabaseAdapter {
  _Ddl(this.inner);

  final DVDatabaseAdapter inner;
  final List<String> statements = <String>[];

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) => inner.query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) {
    if (RegExp(r'^\s*(CREATE|ALTER)\s', caseSensitive: false).hasMatch(sql)) {
      statements.add(sql);
    }
    return inner.execute(sql, params);
  }
}

void main() {
  group('the scan', () {
    test('joins adjacent literals and marks interpolations', () {
      expect(
        stringsIn(
          "db.execute(\n"
          "  'CREATE TABLE IF NOT EXISTS \$logTable (change_id, '\n"
          "  // a comment between them\n"
          "  'model, \${columns.join(', ')})',\n"
          ");\n"
          "final String x = r'\$raw';\n",
        ).map((s) => (s.line, _show(s.text))),
        <(int, String)>[
          (2, r'CREATE TABLE IF NOT EXISTS $… (change_id, model, $…)'),
          (6, r'$raw'),
        ],
      );
    });

    test('finds the untyped columns this release shipped', () {
      // Verbatim, from before every column had a type.
      for (final String shipped in <String>[
        'CREATE TABLE IF NOT EXISTS dv_capture_log (change_id, change_seq, '
            'model, record_key, operation)',
        'CREATE TABLE IF NOT EXISTS dv_privacy_tombstones (subject, erased_at)',
        'CREATE TABLE IF NOT EXISTS dv_schema_evolution (id, state)',
      ]) {
        expect(columnsIn(shipped).untyped, isNotEmpty, reason: shipped);
      }
      expect(
        columnsIn(
          'CREATE TABLE t (id TEXT PRIMARY KEY, note, n BIGINT NOT NULL, '
          'total NUMERIC(12, 2), UNIQUE (id, n))',
        ).untyped,
        <String>['note'],
      );
      expect(columnsIn('ALTER TABLE t ADD COLUMN note').untyped, <String>[
        'note',
      ]);
    });

    test('passes typed columns, constraints and prose', () {
      for (final String fine in <String>[
        'CREATE TABLE IF NOT EXISTS t (id TEXT, n BIGINT NOT NULL, '
            'UNIQUE (id, n), PRIMARY KEY (id))',
        'ALTER TABLE t ADD COLUMN IF NOT EXISTS note TEXT NOT NULL',
        'Found no CREATE TABLE statements under lib/.',
        'It runs CREATE TABLE, INSERT and UPDATE.',
      ]) {
        expect(columnsIn(fine).untyped, isEmpty, reason: fine);
        expect(columnsIn(fine).dynamic, isEmpty, reason: fine);
      }
    });

    test('sets aside what is built at run time', () {
      expect(
        columnsIn('CREATE TABLE $_hole ($_hole, UNIQUE (a, b))').dynamic,
        <String>[_hole],
      );
      expect(
        columnsIn('ALTER TABLE $_hole ADD COLUMN $_hole$_hole').dynamic,
        hasLength(1),
      );
    });
  });

  test('every framework record table declares its types', () {
    // A record table without types makes untyped columns at run time, where
    // the scan above cannot see them.
    final List<String> bare = <String>[];
    var calls = 0;
    for (final FileSystemEntity file in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final String source = file.readAsStringSync();
      for (final RegExpMatch call in RegExp(
        r'DVRecordTable\((?!\{)',
      ).allMatches(source)) {
        final String line = source.substring(
          source.lastIndexOf('\n', call.start) + 1,
          call.start,
        );
        if (line.trimLeft().startsWith('//')) continue;
        int depth = 1;
        int j = call.end;
        while (j < source.length && depth > 0) {
          if (source[j] == '(') depth++;
          if (source[j] == ')') depth--;
          j++;
        }
        calls++;
        if (!source.substring(call.end, j).contains(RegExp(r'\btypes:'))) {
          bare.add(
            '${file.path}:${'\n'.allMatches(source.substring(0, call.start)).length + 1}',
          );
        }
      }
    }
    // A floor, so a refactor that stopped finding the calls fails here
    // rather than passing on nothing. It came down by one when the
    // organization tables went.
    expect(calls, greaterThan(8));
    expect(bare, isEmpty);
  });

  group('the statements run', () {
    // What the stores actually send, including the definitions built at run
    // time, on SQLite.
    late _Ddl ddl;
    final DateTime now = DateTime.utc(2026, 9, 16, 12);

    setUp(() => ddl = _Ddl(SqliteDVDatabaseAdapter.memory()));

    tearDown(() {
      const DVDatabase().unconfigure();
      for (final String statement in ddl.statements) {
        final ({List<String> untyped, List<String> dynamic}) found = columnsIn(
          statement,
        );
        expect(found.untyped, isEmpty, reason: statement);
        expect(found.dynamic, isEmpty, reason: statement);
      }
      expect(ddl.statements, isNotEmpty);
    });

    test('by the framework record tables', () async {
      final DVApiScopes scopes = DVApiScopes(const <String, List<String>>{
        'read': <String>['Thing.view'],
      });
      await DVApiKeys(database: ddl, scopes: scopes).ensureSchema();
      await DVOAuthProvider(database: ddl, scopes: scopes).ensureSchema();
      await DVContentWorkflow<String>(
        kind: 'page',
        database: ddl,
        encode: (String page) => <String, Object?>{'page': page},
        decode: (Map<String, Object?> json) => '${json['page']}',
        documentId: (String page) => page,
        actorId: (Object? user) => '$user',
      ).ensureSchema();
      await DVPrivacy(
        models: const <DVPrivacyModel>[],
        database: ddl,
        signingKey: List<int>.filled(32, 7),
      ).ensureSchema();
      expect(
        ddl.statements.where((String s) => s.contains('__history')),
        hasLength(greaterThanOrEqualTo(6)),
      );
    });

    test('by the reference warehouse sink', () async {
      // The sink writes through the record operations, so its collection is
      // created with the fields it knows and a later field is added to it:
      // both statements have to carry types.
      final DVWarehouseSink sink = DVWarehouseSink(
        database: ddl,
        fieldType: (String model, String field) => DVFieldType.text,
      );
      await sink.evolve(
        DVCaptureSchemaChange(
          sequence: 1,
          model: 'orders',
          phase: DVCaptureSchemaPhase.expand,
          columns: const <String>['id', 'note'],
        ),
      );
      await sink.evolve(
        DVCaptureSchemaChange(
          sequence: 2,
          model: 'orders',
          phase: DVCaptureSchemaPhase.expand,
          columns: const <String>['channel'],
        ),
      );
      expect(
        ddl.statements.where((String s) => s.contains('ADD COLUMN channel')),
        hasLength(1),
      );
    });

    test('by the meter store', () async {
      const DVDatabase().configure(ddl);
      await DVDatabaseMeterStore().add(
        DVMeterRecord(
          tenant: 't1',
          meter: 'calls',
          idempotencyKey: 'k1',
          amount: 1,
          at: now,
          period: DVMeterPeriod.calendarMonth(now),
        ),
      );
    });
  });

  test('no package declares an untyped column', () {
    // Run from packages/dartvel_core, which is where `dart test` runs.
    final Directory packages = Directory('..').absolute;
    final List<String> untyped = <String>[];
    final Map<String, List<String>> dynamic = <String, List<String>>{};
    var scanned = 0;
    for (final FileSystemEntity entity in packages.listSync()) {
      final Directory lib = Directory('${entity.path}/lib');
      if (entity is! Directory || !lib.existsSync()) continue;
      for (final FileSystemEntity file in lib.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        scanned++;
        final String path = file.path.substring(packages.path.length + 1);
        for (final ({int line, String text}) s in stringsIn(
          file.readAsStringSync(),
        )) {
          final ({List<String> untyped, List<String> dynamic}) found =
              columnsIn(s.text);
          for (final String column in found.untyped) {
            untyped.add('$path:${s.line}: $column in ${_show(s.text)}');
          }
          for (final String definition in found.dynamic) {
            (dynamic[path] ??= <String>[]).add(_show(definition));
          }
        }
      }
    }
    // A scan that read nothing would pass.
    expect(scanned, greaterThan(500));
    expect(
      untyped,
      isEmpty,
      reason:
          'PostgreSQL and MySQL refuse a column with no type. Give each the '
          'type of what is written to it.',
    );
    expect(
      dynamic.keys.toSet(),
      _dynamicSites.keys.toSet(),
      reason:
          'A definition built at run time cannot be read here: say in '
          '_dynamicSites what keeps it typed. Found: $dynamic',
    );
  });
}
