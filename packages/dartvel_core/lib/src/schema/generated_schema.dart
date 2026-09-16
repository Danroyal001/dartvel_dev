/// The generated models' tables, made and brought up to date in a database.
///
/// `dartvel routes` writes each model's table as a statement and a column
/// list. Two things apply them: `dartvel db migrate`, against the database
/// beside a project, and a web-server binary when it starts, against the
/// database it serves -- which, on a first run, it has just created. One
/// implementation for both, because a migration that makes one shape and a
/// server that expects another is the failure nothing reports.
library;

import '../database/adapter.dart';
import '../database/connection.dart' show DVDatabaseEngine;
import 'schema_change.dart';

/// The column a tenant-scoped model's rows carry.
///
/// One definition, because the generator writes it into the schema and every
/// predicate, and the migration adds it to a table that predates the
/// annotation. Two spellings is a migration that adds one column and queries
/// that read another, on a database that reports as migrated.
const String dvTenantColumn = 'dv_tenant';

/// What applying the generated schema did.
final class DVGeneratedSchemaReport {
  const DVGeneratedSchemaReport({
    required this.applied,
    this.created = const <String>[],
    this.added = const <String>[],
    this.needsTenant = const <String>[],
  });

  /// Tables whose statement ran.
  final List<String> applied;

  /// Tables that were not there before.
  final List<String> created;

  /// Columns added to a table that was already there, as `table.column`.
  ///
  /// CREATE TABLE IF NOT EXISTS is a no-op against a table that exists, so a
  /// model that gained a column since the table was made never got it, and
  /// every query naming that column failed.
  final List<String> added;

  /// Tables whose rows would be hidden by adding the tenant column, and
  /// which were left alone until somebody says whose those rows are.
  ///
  /// Rows written before the column existed belong to no tenant, and a
  /// predicate on every read hides all of them from everybody: the table
  /// reads as empty, which cannot be told apart from data loss.
  final List<String> needsTenant;
}

/// The column [column] of a generated [table], as the change that adds it.
///
/// Nullable TEXT unless the generator recorded a type for it under
/// `columnTypes` -- the record version, which has to arrive as `NOT NULL
/// DEFAULT 1` so the rows already there can be written at the version they
/// hold.
DVAddColumn dvAddColumnFor(Map<String, Object?> table, String column) {
  final Object? types = table['columnTypes'];
  final Object? spec = types is Map ? types[column] : null;
  if (spec is! Map) return DVAddColumn('${table['table']}', column);
  return DVAddColumn(
    '${table['table']}',
    column,
    type: '${spec['type'] ?? 'TEXT'}',
    nullable: spec['nullable'] != false,
    defaultSql: spec['default'] == null ? null : '${spec['default']}',
  );
}

/// The SQL that makes [change]. `IF NOT EXISTS` only where asked for: it is
/// PostgreSQL's, and SQLite and MySQL refuse it.
String dvAddColumnSql(DVAddColumn change, {bool ifNotExists = false}) =>
    'ALTER TABLE ${change.table} ADD COLUMN '
    '${ifNotExists ? 'IF NOT EXISTS ' : ''}${change.column} ${change.type}'
    '${change.nullable ? '' : ' NOT NULL'}'
    '${change.defaultSql == null ? '' : ' DEFAULT ${change.defaultSql}'}';

/// Makes the generated [tables] in [database] and adds the columns a table
/// made by an earlier release is missing.
///
/// On SQLite the table is asked what it has and each missing column is
/// added; a tenant column is not added to a table that has rows unless
/// [tenant] says whose they are or [orphanExistingRows] says nobody's. On
/// PostgreSQL every column is added with `IF NOT EXISTS`. On MySQL, which has
/// neither, the tables are created and nothing is added.
Future<DVGeneratedSchemaReport> dvApplyGeneratedSchema(
  DVDatabaseAdapter database,
  List<Map<String, Object?>> tables, {
  required DVDatabaseEngine engine,
  String? tenant,
  bool orphanExistingRows = false,
}) async {
  final List<String> applied = <String>[];
  final List<String> created = <String>[];
  final List<String> added = <String>[];
  final List<String> needsTenant = <String>[];

  for (final Map<String, Object?> table in tables) {
    final Object? create = table['createSql'];
    if (create is! String) continue;
    final String name = '${table['table']}';
    final List<String> want = <String>[
      for (final Object? column
          in (table['columns'] as List<Object?>? ?? const <Object?>[]))
        '$column',
    ];

    switch (engine) {
      case DVDatabaseEngine.sqlite:
        final List<String> before = await _sqliteColumns(database, name);
        await database.execute(create);
        applied.add(name);
        if (before.isEmpty) {
          created.add(name);
          continue;
        }
        final List<String> missing =
            want.where((String c) => !before.contains(c)).toList();
        if (missing.isEmpty) continue;
        if (missing.contains(dvTenantColumn) &&
            !orphanExistingRows &&
            tenant == null &&
            (await database.query('SELECT 1 FROM $name LIMIT 1')).isNotEmpty) {
          // Nothing altered: the application running the old code still
          // works, which is the point of stopping before half of it.
          needsTenant.add(name);
          continue;
        }
        for (final String column in missing) {
          await database.execute(dvAddColumnSql(dvAddColumnFor(table, column)));
          added.add('$name.$column');
        }
        if (missing.contains(dvTenantColumn) && tenant != null) {
          await database.execute(
            'UPDATE $name SET $dvTenantColumn = ? '
            'WHERE $dvTenantColumn IS NULL',
            <Object?>[tenant],
          );
        }
      case DVDatabaseEngine.postgres:
        await database.execute(create);
        applied.add(name);
        final Object? types = table['columnTypes'];
        if (types is Map) {
          for (final Object? column in types.keys) {
            await database.execute(dvAddColumnSql(
              dvAddColumnFor(table, '$column'),
              ifNotExists: true,
            ));
          }
        }
      case DVDatabaseEngine.mysql:
        await database.execute(create);
        applied.add(name);
    }
  }
  return DVGeneratedSchemaReport(
    applied: applied,
    created: created,
    added: added,
    needsTenant: needsTenant,
  );
}

Future<List<String>> _sqliteColumns(
  DVDatabaseAdapter database,
  String table,
) async {
  final List<Map<String, Object?>> rows =
      await database.query('PRAGMA table_info($table)');
  return rows
      .map((Map<String, Object?> row) => '${row['name']}')
      .toList(growable: false);
}
