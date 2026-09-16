/// The tables the framework makes for itself, made so that every server can
/// make them and their 64-bit columns are 64 bits on every server.
///
/// SQLite's `INTEGER` is 64 bits; PostgreSQL's and MySQL's are 32. Timestamps
/// in milliseconds or microseconds, long durations and usage quantities are
/// past 2,147,483,647, so a framework table that declared them `INTEGER`
/// worked in every local suite and refused every row on a server --
/// "value out of range for type integer" on the first sign-in.
///
/// The fix is in the DDL, not in the adapters: every framework table declares
/// such columns `BIGINT`, which all three servers read as 64 bits (SQLite gives
/// it INTEGER affinity, so its storage is unchanged). Rewriting `INTEGER` to
/// `BIGINT` inside the PostgreSQL and MySQL adapters would change the meaning
/// of every application's own DDL passed through them, and on SQLite it would
/// break `INTEGER PRIMARY KEY`, which only aliases the rowid when spelled
/// exactly that way.
///
/// The same holds for the other ways SQLite is lenient and a server is not,
/// which [dvFrameworkTableProblems] names and [dvEnsureFrameworkTable] refuses
/// on every adapter, so a local suite catches them:
///
/// * a column with **no type**. SQLite gives it BLOB affinity; PostgreSQL and
///   MySQL refuse the whole statement, so the store cannot make its table.
/// * **TEXT in a key**. MySQL cannot index a TEXT column without a prefix
///   length and refuses the table; `VARCHAR(n)` is TEXT affinity on SQLite and
///   an indexable string on both servers.
/// * **REAL** or **FLOAT**. PostgreSQL's REAL and MySQL's FLOAT are 4-byte
///   floats that keep about seven significant digits, so 123456.789 is stored
///   as 123456.79. `DOUBLE PRECISION` is an 8-byte float on all three (REAL
///   affinity on SQLite, which is already 8 bytes), and it round-trips a Dart
///   `double` exactly. `NUMERIC` would not do: SQLite's NUMERIC affinity turns
///   a stored 2.0 into the integer 2, and PostgreSQL returns it unbounded.
///
/// Changing the DDL is not enough on its own. `CREATE TABLE IF NOT EXISTS`
/// leaves a table an earlier release made exactly as it was, so a server that
/// already has one keeps refusing rows. [dvEnsureFrameworkTable] therefore
/// also widens what an earlier release left narrow -- through the schema
/// planner, and only where that cannot hold anybody up.
library dartvel_core.database.framework_tables;

import '../observability/observability.dart';
import '../schema/schema_change.dart';
import '../schema/schema_planner.dart';
import 'adapter.dart';
import 'mysql.dart';
import 'postgres.dart';

final RegExp _createTable = RegExp(
  r'^\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?'
  r'((?:[A-Za-z_][A-Za-z0-9_]*\.)?[A-Za-z_][A-Za-z0-9_]*)\s*\(',
  caseSensitive: false,
);

final RegExp _sqlType = RegExp(
  r'^[A-Za-z][A-Za-z0-9_]*(?: [A-Za-z][A-Za-z0-9_]*)*'
  r'(?:\(\d+(?:, ?\d+)?\))?$',
);

/// Whether [type] reads as a SQL column type -- `TEXT`, `BIGINT`,
/// `DOUBLE PRECISION`, `VARCHAR(255)`, `NUMERIC(12, 2)` -- and nothing else.
///
/// A type an application hands the framework is written into DDL, so it is
/// checked rather than trusted, as an identifier is.
bool dvIsSqlType(String type) => _sqlType.hasMatch(type);

final RegExp _bigIntColumn = RegExp(
  r'(?:^|[(,])\s*([A-Za-z_][A-Za-z0-9_]*)\s+BIGINT\b',
  caseSensitive: false,
);

final RegExp _doubleColumn = RegExp(
  r'(?:^|[(,])\s*([A-Za-z_][A-Za-z0-9_]*)\s+DOUBLE(?:\s+PRECISION)?\b',
  caseSensitive: false,
);

/// A framework table's DDL that a server would refuse or mangle.
///
/// Thrown before the statement runs, on every adapter: the point is that the
/// in-memory and SQLite adapters every local suite uses refuse what only a
/// server would otherwise have refused.
class DVFrameworkTableError extends Error {
  DVFrameworkTableError(this.createSql, this.problems);

  final String createSql;
  final List<String> problems;

  @override
  String toString() =>
      'DVFrameworkTableError: ${problems.join('; ')}, which PostgreSQL or '
      'MySQL would refuse or store wrongly, in: $createSql';
}

/// The table [createSql] makes and the columns it declares `BIGINT`, in
/// order.
///
/// Throws [ArgumentError] for a statement it cannot read: a table whose
/// columns were silently not found would never be widened.
({String table, List<String> columns}) dvBigIntColumnsIn(String createSql) {
  final ({String table, List<({String name, String type})> columns}) wide =
      _wideColumnsIn(createSql);
  return (
    table: wide.table,
    columns: <String>[
      for (final ({String name, String type}) c in wide.columns)
        if (c.type == 'BIGINT') c.name,
    ],
  );
}

({String table, List<({String name, String type})> columns}) _wideColumnsIn(
  String createSql,
) {
  final RegExpMatch? create = _createTable.firstMatch(createSql);
  if (create == null) {
    throw ArgumentError.value(
      createSql,
      'createSql',
      'is not a CREATE TABLE statement naming its table',
    );
  }
  final String body = createSql.substring(create.end - 1);
  final Map<int, ({String name, String type})> found =
      <int, ({String name, String type})>{
        for (final RegExpMatch m in _bigIntColumn.allMatches(body))
          m.start: (name: m.group(1)!, type: 'BIGINT'),
        for (final RegExpMatch m in _doubleColumn.allMatches(body))
          m.start: (name: m.group(1)!, type: 'DOUBLE PRECISION'),
      };
  return (
    table: create.group(1)!,
    columns: <({String name, String type})>[
      for (final int at in found.keys.toList()..sort()) found[at]!,
    ],
  );
}

/// Words that can follow a column's name and are not its type.
const Set<String> _notTypes = <String>{
  'NOT',
  'NULL',
  'PRIMARY',
  'UNIQUE',
  'DEFAULT',
  'REFERENCES',
  'CHECK',
  'CONSTRAINT',
  'COLLATE',
  'GENERATED',
  'AUTOINCREMENT',
};

/// Types MySQL cannot index without a prefix length.
const Set<String> _unkeyable = <String>{
  'TEXT',
  'TINYTEXT',
  'MEDIUMTEXT',
  'LONGTEXT',
  'BLOB',
  'TINYBLOB',
  'MEDIUMBLOB',
  'LONGBLOB',
};

/// What in [createSql] PostgreSQL or MySQL would refuse or store wrongly, as
/// `table.column has no type`, `table.column is TEXT in a key` and
/// `table.column is REAL`, in column order.
///
/// A column whose definition is still a Dart interpolation (`$columns`) is
/// not read: this is also run over source code, where such a list is only
/// known when the statement runs.
List<String> dvFrameworkTableProblems(String createSql) {
  final RegExpMatch? head = RegExp(
    r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([^(]*?)\s*\(',
    caseSensitive: false,
  ).firstMatch(createSql);
  if (head == null) return const <String>[];
  final String table = head.group(1)!;
  final List<String> definitions = <String>[];
  final StringBuffer current = StringBuffer();
  var depth = 1;
  for (var i = head.end; i < createSql.length && depth > 0; i++) {
    final String c = createSql[i];
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (depth == 0 || (depth == 1 && c == ',')) {
      definitions.add(current.toString().trim());
      current.clear();
    } else {
      current.write(c);
    }
  }

  final List<({String name, String? type})> columns =
      <({String name, String? type})>[];
  final Set<String> keyed = <String>{};
  final RegExp constraint = RegExp(
    r'^(?:CONSTRAINT\s+\w+\s+)?(PRIMARY\s+KEY|UNIQUE|FOREIGN\s+KEY|CHECK)\b'
    r'\s*(?:\(([^)]*)\))?',
    caseSensitive: false,
  );
  for (final String definition in definitions) {
    if (definition.isEmpty || definition.contains(r'$')) continue;
    final RegExpMatch? tableConstraint = constraint.firstMatch(definition);
    if (tableConstraint != null) {
      final String kind = tableConstraint.group(1)!.toUpperCase();
      if (kind.startsWith('PRIMARY') || kind == 'UNIQUE') {
        keyed.addAll(
          (tableConstraint.group(2) ?? '')
              .split(',')
              .map((String c) => c.trim().toLowerCase()),
        );
      }
      continue;
    }
    final List<String> words = definition.split(RegExp(r'\s+'));
    final String name = words.first;
    final String? type =
        words.length < 2 || _notTypes.contains(words[1].toUpperCase())
        ? null
        : words[1].toUpperCase().split('(').first;
    columns.add((name: name, type: type));
    if (RegExp(
      r'\b(PRIMARY\s+KEY|UNIQUE)\b',
      caseSensitive: false,
    ).hasMatch(definition)) {
      keyed.add(name.toLowerCase());
    }
  }

  return <String>[
    for (final ({String name, String? type}) column in columns)
      if (column.type == null)
        '$table.${column.name} has no type'
      else if (column.type == 'REAL' || column.type == 'FLOAT')
        '$table.${column.name} is ${column.type}'
      else if (_unkeyable.contains(column.type) &&
          keyed.contains(column.name.toLowerCase()))
        '$table.${column.name} is ${column.type} in a key',
  ];
}

/// The statement that widens [columns] of [table] to `BIGINT`.
///
/// PostgreSQL's `ALTER COLUMN ... TYPE` keeps `NOT NULL`. MySQL's `MODIFY`
/// replaces the whole definition, so nullability is restated or it is lost.
String dvWidenToBigIntSql(
  String table,
  List<({String name, bool nullable})> columns, {
  required bool mysql,
}) => dvWidenColumnsSql(table, <({String name, String type, bool nullable})>[
  for (final ({String name, bool nullable}) c in columns)
    (name: c.name, type: 'BIGINT', nullable: c.nullable),
], mysql: mysql);

/// The statement that changes each of [columns] of [table] to its type.
String dvWidenColumnsSql(
  String table,
  List<({String name, String type, bool nullable})> columns, {
  required bool mysql,
}) {
  final List<String> clauses = <String>[
    for (final ({String name, String type, bool nullable}) column in columns)
      if (mysql)
        'MODIFY COLUMN ${column.name} ${column.type} '
            '${column.nullable ? 'NULL' : 'NOT NULL'}'
      else
        'ALTER COLUMN ${column.name} TYPE ${column.type}',
  ];
  return 'ALTER TABLE $table ${clauses.join(', ')}';
}

/// Runs [createSql] and makes sure every column it declares `BIGINT` is 64
/// bits wide, and every column it declares `DOUBLE PRECISION` an 8-byte
/// float, in the table as it actually is.
///
/// Before anything runs, [createSql] is checked with
/// [dvFrameworkTableProblems] and refused with a [DVFrameworkTableError] on
/// every adapter.
///
/// On PostgreSQL and MySQL the catalogue is asked; a column an earlier release
/// created narrower is a type change, which the schema planner classifies
/// with the adapter's own rules. A type change rewrites the table on both
/// servers, and the cost of a rewrite is its rows:
///
/// * on an **empty** table there is nothing to rewrite, and it runs. That is
///   the case every deployment is in for an integer: no framework write fits a
///   32-bit column, so on PostgreSQL, and on MySQL in its default strict mode,
///   every insert into such a table failed and the table holds nothing.
/// * on a table **with rows** it does not run. For an integer a StateError
///   carries the plan -- the class of each change and the expand/contract the
///   planner offers -- and the statement, for someone to schedule. Rows can
///   only be there from outside the framework, or from a MySQL server not in
///   strict mode, which clamped each timestamp to 2,147,483,647 rather than
///   refusing it. A 4-byte float took every write and only rounded it, so a
///   table of them is working and is not stopped: the plan and the statement
///   are logged as a warning instead.
///
/// Other adapters -- SQLite, the in-memory adapter, anything written outside
/// this package -- get the statement alone: SQLite's INTEGER is already 64
/// bits and its REAL 8, and nothing here knows another server's catalogue.
Future<void> dvEnsureFrameworkTable(
  DVDatabaseAdapter adapter,
  String createSql,
) async {
  final List<String> problems = dvFrameworkTableProblems(createSql);
  if (problems.isNotEmpty) throw DVFrameworkTableError(createSql, problems);
  final ({String table, List<({String name, String type})> columns}) wanted =
      _wideColumnsIn(createSql);
  await adapter.execute(createSql);
  if (wanted.columns.isEmpty) return;

  final bool mysql = adapter is DVMySqlDatabaseAdapter;
  if (!mysql && adapter is! DVPostgresDatabaseAdapter) return;

  // Unquoted identifiers are folded to lower case by PostgreSQL, and the
  // framework's are lower case already. A qualified name is looked up in its
  // own schema -- on MySQL, its own database.
  final String table = wanted.table.toLowerCase();
  final int dot = table.indexOf('.');
  final String? schema = dot < 0 ? null : table.substring(0, dot);
  final Map<String, String> columns = <String, String>{
    for (final ({String name, String type}) c in wanted.columns)
      c.name.toLowerCase(): c.type,
  };
  final List<Map<String, Object?>> catalogue = await adapter.query(
    'SELECT column_name AS name, data_type AS type, is_nullable AS nullable '
    'FROM information_schema.columns '
    'WHERE table_schema = '
    '${schema != null
        ? '?'
        : mysql
        ? 'DATABASE()'
        : 'current_schema()'} '
    'AND table_name = ?',
    <Object?>[?schema, table.substring(dot + 1)],
  );
  final List<({String name, String from, String to, bool nullable})> narrow =
      <({String name, String from, String to, bool nullable})>[
        for (final Map<String, Object?> row in catalogue)
          if (columns['${row['name']}'.toLowerCase()] case final String to
              when (to == 'BIGINT' ? _narrowTypes : _narrowFloats).contains(
                '${row['type']}'.toLowerCase(),
              ))
            (
              name: '${row['name']}'.toLowerCase(),
              from: '${row['type']}'.toLowerCase(),
              to: to,
              nullable: '${row['nullable']}'.toUpperCase() == 'YES',
            ),
      ];
  if (narrow.isEmpty) return;

  final String widen = dvWidenColumnsSql(
    table,
    <({String name, String type, bool nullable})>[
      for (final c in narrow) (name: c.name, type: c.to, nullable: c.nullable),
    ],
    mysql: mysql,
  );
  final DVSchemaPlan plan = await const DVSchemaPlanner().planFor(
    adapter,
    <DVSchemaChange>[
      for (final c in narrow)
        DVChangeColumnType(table, c.name, from: c.from, to: c.to),
    ],
  );
  final bool holdsAnybody = plan.steps.any(
    (DVSchemaPlanStep step) => step.changeClass == DVSchemaChangeClass.blocking,
  );
  if (holdsAnybody) {
    final List<Map<String, Object?>> counted = await adapter.query(
      'SELECT COUNT(*) AS n FROM $table',
    );
    final int rows = int.parse('${counted.single['n']}');
    if (rows > 0) {
      final bool integers = narrow.any((c) => c.to == 'BIGINT');
      final String message =
          '$table was created by an earlier release with ${narrow.length} '
          'column(s) narrower than the framework writes to them '
          '(${narrow.map((c) => '${c.name} ${c.from}').join(', ')}), '
          '${integers ? 'so every write to it fails' : 'so each value is rounded to about seven significant digits'}. '
          'Widening them rewrites the table, and it has $rows '
          'row${rows == 1 ? '' : 's'}, so it has not been run here.\n'
          '${plan.describe()}'
          'Schedule it, or run the expand/contract above:\n  $widen';
      if (integers) throw StateError(message);
      DVObservability.log(message, level: DVLogLevel.warn);
      return;
    }
  }
  await adapter.execute(widen);
}

/// Integer types narrower than 64 bits, as `information_schema` names them
/// on PostgreSQL (`integer`, `smallint`) and MySQL (`int`, `mediumint`, ...).
const Set<String> _narrowTypes = <String>{
  'integer',
  'smallint',
  'int',
  'mediumint',
  'tinyint',
};

/// 4-byte floats: PostgreSQL's `real`, MySQL's `float`.
const Set<String> _narrowFloats = <String>{'real', 'float'};

/// Adds each of [columns] to its framework table where the table does not
/// have it yet.
///
/// `CREATE TABLE IF NOT EXISTS` leaves a table an earlier release made
/// exactly as it was, so a column added to a framework table's DDL exists on
/// every fresh install and on no upgraded one, and the first write naming it
/// fails on exactly the deployments that have data. Call this after
/// [dvEnsureFrameworkTable] with the columns added since the table first
/// shipped.
///
/// Each column is checked as [dvEnsureFrameworkTable] checks a CREATE TABLE,
/// on every adapter. Missing ones are classified by the schema planner with
/// the adapter's own rules, and the cost of a change that holds the table is
/// its rows, as for widening: on an empty table it runs, on a table with rows
/// it does not, and a StateError carries the plan and the statement. A
/// nullable column with no default is instant on every server the planner
/// knows, so that is what a column added later should be.
///
/// Where the column already is, nothing runs, however often this is called.
/// The in-memory adapter is skipped: its tables live only in the process that
/// created them, from the current DDL, so no earlier release made one.
Future<void> dvEnsureFrameworkColumns(
  DVDatabaseAdapter adapter,
  List<DVAddColumn> columns,
) async {
  for (final DVAddColumn column in columns) {
    final String statement = _addColumnSql(column);
    final List<String> problems = <String>[
      ...dvFrameworkTableProblems(
        'CREATE TABLE ${column.table} (${column.column} ${column.type})',
      ),
    ];
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(column.column) ||
        !RegExp(
          r'^(?:[A-Za-z_][A-Za-z0-9_]*\.)?[A-Za-z_][A-Za-z0-9_]*$',
        ).hasMatch(column.table)) {
      problems.add(
        '${column.table}.${column.column} is not a plain identifier',
      );
    }
    if (!dvIsSqlType(column.type)) {
      problems.add('${column.table}.${column.column} has no usable type');
    }
    if (problems.isNotEmpty) throw DVFrameworkTableError(statement, problems);
  }
  if (adapter is MemoryDVDatabaseAdapter) return;

  final List<DVAddColumn> missing = <DVAddColumn>[
    for (final DVAddColumn column in columns)
      if (!await _hasColumn(adapter, column.table, column.column)) column,
  ];
  if (missing.isEmpty) return;

  final DVSchemaPlan plan = await const DVSchemaPlanner().planFor(
    adapter,
    missing,
  );
  for (final DVSchemaPlanStep step in plan.steps) {
    final DVAddColumn column = step.change as DVAddColumn;
    final String statement = _addColumnSql(column);
    if (step.changeClass == DVSchemaChangeClass.blocking) {
      final List<Map<String, Object?>> counted = await adapter.query(
        'SELECT COUNT(*) AS n FROM ${column.table}',
      );
      final int rows = int.parse('${counted.single['n']}');
      if (rows > 0) {
        throw StateError(
          '${column.table} was created by an earlier release without '
          '${column.column}, which this release writes. Adding it holds the '
          'table, and it has $rows row${rows == 1 ? '' : 's'}, so it has not '
          'been run here.\n'
          '${plan.describe()}'
          'Schedule it:\n  $statement',
        );
      }
    }
    await adapter.execute(statement);
  }
}

String _addColumnSql(DVAddColumn column) =>
    'ALTER TABLE ${column.table} ADD COLUMN ${column.column} ${column.type}'
    '${column.nullable ? '' : ' NOT NULL'}'
    '${column.defaultSql == null ? '' : ' DEFAULT ${column.defaultSql}'}';

/// Whether [table] has [column], asked of the catalogue where the server has
/// one this knows, and of the table itself otherwise.
Future<bool> _hasColumn(
  DVDatabaseAdapter adapter,
  String table,
  String column,
) async {
  final String name = table.toLowerCase();
  final int dot = name.indexOf('.');
  final String? schema = dot < 0 ? null : name.substring(0, dot);
  final String bare = name.substring(dot + 1);
  final bool mysql = adapter is DVMySqlDatabaseAdapter;
  if (mysql || adapter is DVPostgresDatabaseAdapter) {
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT column_name AS name FROM information_schema.columns '
      'WHERE table_schema = '
      '${schema != null
          ? '?'
          : mysql
          ? 'DATABASE()'
          : 'current_schema()'} '
      'AND table_name = ?',
      <Object?>[?schema, bare],
    );
    return rows.any(
      (Map<String, Object?> row) =>
          '${row['name']}'.toLowerCase() == column.toLowerCase(),
    );
  }
  try {
    // SQLite and anything else: naming the column is the question. A
    // statement that fails for any reason reads as missing, and the ALTER
    // that follows says what is actually wrong if it is not.
    await adapter.query('SELECT $column FROM $table LIMIT 1');
    return true;
  } on Object {
    return false;
  }
}
