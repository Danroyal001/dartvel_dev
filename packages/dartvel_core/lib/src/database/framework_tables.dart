/// The tables the framework makes for itself, made so that their 64-bit
/// columns are 64 bits on every server.
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
/// Changing the DDL is not enough on its own. `CREATE TABLE IF NOT EXISTS`
/// leaves a table an earlier release made exactly as it was, so a server that
/// already has one keeps refusing rows. [dvEnsureFrameworkTable] therefore
/// also widens what an earlier release left narrow -- through the schema
/// planner, and only where that cannot hold anybody up.
library dartvel_core.database.framework_tables;

import '../schema/schema_change.dart';
import '../schema/schema_planner.dart';
import 'adapter.dart';
import 'mysql.dart';
import 'postgres.dart';

final RegExp _createTable = RegExp(
  r'^\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(',
  caseSensitive: false,
);

final RegExp _bigIntColumn = RegExp(
  r'(?:^|[(,])\s*([A-Za-z_][A-Za-z0-9_]*)\s+BIGINT\b',
  caseSensitive: false,
);

/// The table [createSql] makes and the columns it declares `BIGINT`, in
/// order.
///
/// Throws [ArgumentError] for a statement it cannot read: a table whose
/// columns were silently not found would never be widened.
({String table, List<String> columns}) dvBigIntColumnsIn(String createSql) {
  final RegExpMatch? create = _createTable.firstMatch(createSql);
  if (create == null) {
    throw ArgumentError.value(
      createSql,
      'createSql',
      'is not a CREATE TABLE statement naming its table',
    );
  }
  return (
    table: create.group(1)!,
    columns: <String>[
      for (final RegExpMatch column in _bigIntColumn.allMatches(
        createSql.substring(create.end - 1),
      ))
        column.group(1)!,
    ],
  );
}

/// The statement that widens [columns] of [table] to `BIGINT`.
///
/// PostgreSQL's `ALTER COLUMN ... TYPE` keeps `NOT NULL`. MySQL's `MODIFY`
/// replaces the whole definition, so nullability is restated or it is lost.
String dvWidenToBigIntSql(
  String table,
  List<({String name, bool nullable})> columns, {
  required bool mysql,
}) {
  final List<String> clauses = <String>[
    for (final ({String name, bool nullable}) column in columns)
      if (mysql)
        'MODIFY COLUMN ${column.name} BIGINT '
            '${column.nullable ? 'NULL' : 'NOT NULL'}'
      else
        'ALTER COLUMN ${column.name} TYPE BIGINT',
  ];
  return 'ALTER TABLE $table ${clauses.join(', ')}';
}

/// Runs [createSql] and makes sure every column it declares `BIGINT` is 64
/// bits wide in the table as it actually is.
///
/// On PostgreSQL and MySQL the catalogue is asked; a column an earlier release
/// created 32 bits wide is a type change, which the schema planner classifies
/// with the adapter's own rules. A type change rewrites the table on both
/// servers, and the cost of a rewrite is its rows:
///
/// * on an **empty** table there is nothing to rewrite, and it runs. That is
///   the case every deployment is in: no framework write fits a 32-bit column,
///   so on PostgreSQL, and on MySQL in its default strict mode, every insert
///   into such a table failed and the table holds nothing.
/// * on a table **with rows** it does not run. A StateError carries the plan
///   -- the class of each change and the expand/contract the planner offers --
///   and the statement, for someone to schedule. Rows can only be there from
///   outside the framework, or from a MySQL server not in strict mode, which
///   clamped each timestamp to 2,147,483,647 rather than refusing it.
///
/// Other adapters -- SQLite, the in-memory adapter, anything written outside
/// this package -- get the statement alone: SQLite's INTEGER is already 64
/// bits, and nothing here knows another server's catalogue.
Future<void> dvEnsureFrameworkTable(
  DVDatabaseAdapter adapter,
  String createSql,
) async {
  final ({String table, List<String> columns}) wanted = dvBigIntColumnsIn(
    createSql,
  );
  await adapter.execute(createSql);
  if (wanted.columns.isEmpty) return;

  final bool mysql = adapter is DVMySqlDatabaseAdapter;
  if (!mysql && adapter is! DVPostgresDatabaseAdapter) return;

  // Unquoted identifiers are folded to lower case by PostgreSQL, and the
  // framework's are lower case already.
  final String table = wanted.table.toLowerCase();
  final Set<String> columns = wanted.columns
      .map((String c) => c.toLowerCase())
      .toSet();
  final List<Map<String, Object?>> catalogue = await adapter.query(
    'SELECT column_name AS name, data_type AS type, is_nullable AS nullable '
    'FROM information_schema.columns '
    'WHERE table_schema = ${mysql ? 'DATABASE()' : 'current_schema()'} '
    'AND table_name = ?',
    <Object?>[table],
  );
  final List<({String name, String type, bool nullable})> narrow =
      <({String name, String type, bool nullable})>[
        for (final Map<String, Object?> row in catalogue)
          if (columns.contains('${row['name']}'.toLowerCase()) &&
              _narrowTypes.contains('${row['type']}'.toLowerCase()))
            (
              name: '${row['name']}'.toLowerCase(),
              type: '${row['type']}'.toLowerCase(),
              nullable: '${row['nullable']}'.toUpperCase() == 'YES',
            ),
      ];
  if (narrow.isEmpty) return;

  final String widen =
      dvWidenToBigIntSql(table, <({String name, bool nullable})>[
        for (final ({String name, String type, bool nullable}) c in narrow)
          (name: c.name, nullable: c.nullable),
      ], mysql: mysql);
  final DVSchemaPlan plan = await const DVSchemaPlanner()
      .planFor(adapter, <DVSchemaChange>[
        for (final ({String name, String type, bool nullable}) c in narrow)
          DVChangeColumnType(table, c.name, from: c.type, to: 'BIGINT'),
      ]);
  final bool holdsAnybody = plan.steps.any(
    (DVSchemaPlanStep step) => step.changeClass == DVSchemaChangeClass.blocking,
  );
  if (holdsAnybody) {
    final List<Map<String, Object?>> counted = await adapter.query(
      'SELECT COUNT(*) AS n FROM $table',
    );
    final int rows = int.parse('${counted.single['n']}');
    if (rows > 0) {
      throw StateError(
        '$table was created by an earlier release with ${narrow.length} '
        'column(s) 32 bits wide that the framework writes 64-bit values to '
        '(${narrow.map((c) => c.name).join(', ')}), so every write to it '
        'fails. Widening them rewrites the table, and it has $rows '
        'row${rows == 1 ? '' : 's'}, so it has not been run here.\n'
        '${plan.describe()}'
        'Schedule it, or run the expand/contract above:\n  $widen',
      );
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
