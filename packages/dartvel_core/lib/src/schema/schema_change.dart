/// Schema changes and how much each one costs on a given server.
///
/// The class of a change -- instant, online or blocking -- comes from the
/// adapter connected to the server, never from rules inside the planner.
/// Adding a column with a default is instant on PostgreSQL 11 and a table
/// rewrite on 10, and a planner with that baked in is wrong the day a server
/// ships a new version and wrong for every adapter written outside this
/// package. So an adapter implements [DVSchemaClassifier], and the planner
/// only asks.
library dartvel_core.schema.change;

import 'dart:async';

import '../database/adapter.dart';

/// How much a schema change costs the table it touches.
enum DVSchemaChangeClass {
  /// Metadata only; the table is not rewritten and the lock is momentary.
  instant,

  /// The table stays readable and writable throughout.
  online,

  /// Readers or writers are held for the duration.
  blocking,
}

/// One change to a schema, described rather than written as SQL, so that an
/// adapter can say what it costs on its server.
sealed class DVSchemaChange {
  const DVSchemaChange(this.table);

  /// The table the change touches.
  final String table;

  /// A one-line description for a plan, e.g. `add column orders.note`.
  String get description;

  @override
  String toString() => description;
}

/// A new table. Nothing reads it and it holds no rows, so no server locks
/// anything that matters to create it.
final class DVCreateTable extends DVSchemaChange {
  const DVCreateTable(super.table, this.columns);

  final List<String> columns;

  @override
  String get description => 'create table $table (${columns.join(', ')})';
}

/// A column added to an existing table.
final class DVAddColumn extends DVSchemaChange {
  const DVAddColumn(
    super.table,
    this.column, {
    this.type = 'TEXT',
    this.nullable = true,
    this.defaultSql,
  });

  final String column;
  final String type;
  final bool nullable;

  /// The default as SQL, e.g. `'open'` or `0`; null for none.
  final String? defaultSql;

  @override
  String get description =>
      'add column $table.$column $type'
      '${nullable ? '' : ' NOT NULL'}'
      '${defaultSql == null ? '' : ' DEFAULT $defaultSql'}';
}

/// An index over one or more columns.
final class DVAddIndex extends DVSchemaChange {
  const DVAddIndex(super.table, this.columns, {this.name, this.unique = false});

  final List<String> columns;
  final String? name;
  final bool unique;

  @override
  String get description =>
      'add ${unique ? 'unique ' : ''}index on $table (${columns.join(', ')})';
}

/// `NOT NULL` added to an existing column.
final class DVAddNotNull extends DVSchemaChange {
  const DVAddNotNull(super.table, this.column);

  final String column;

  @override
  String get description => 'add NOT NULL to $table.$column';
}

/// An existing column given a different type.
final class DVChangeColumnType extends DVSchemaChange {
  const DVChangeColumnType(
    super.table,
    this.column, {
    required this.from,
    required this.to,
  });

  final String column;
  final String from;
  final String to;

  @override
  String get description => 'change type of $table.$column from $from to $to';
}

/// An existing column renamed.
///
/// Instant on most servers and still breaking for a client that reads the old
/// name: the cost of a change and its compatibility are separate questions,
/// and this class only answers the first.
final class DVRenameColumn extends DVSchemaChange {
  const DVRenameColumn(super.table, {required this.from, required this.to});

  final String from;
  final String to;

  @override
  String get description => 'rename column $table.$from to $to';
}

/// An existing column dropped.
final class DVDropColumn extends DVSchemaChange {
  const DVDropColumn(super.table, this.column);

  final String column;

  @override
  String get description => 'drop column $table.$column';
}

/// A statement written by hand, which no shipped adapter can classify.
///
/// Classified as `null` -- cannot say -- and the planner treats that as
/// blocking (`DV-SCHEMA-006`). Guessing cheap for an unknown statement is the
/// outage nobody predicted; guessing expensive is a plan somebody reads.
final class DVRawSchemaChange extends DVSchemaChange {
  const DVRawSchemaChange(super.table, this.statement);

  final String statement;

  @override
  String get description => 'statement on $table: $statement';
}

/// Answers what a change costs on one server.
///
/// Implemented by a database adapter, which is the thing that knows the server
/// and its version. `null` means the adapter cannot classify the change.
abstract interface class DVSchemaClassifier {
  FutureOr<DVSchemaChangeClass?> classify(DVSchemaChange change);
}

/// `DVDatabaseAdapter.classify(change)`.
///
/// An extension rather than a new abstract member on the adapter contract:
/// every adapter written outside this package `implements` that contract, and
/// adding a member to it would stop all of them compiling for a question that
/// has a safe answer when they do not know it. An adapter that can classify
/// implements [DVSchemaClassifier]; one that does not answers `null`, which
/// the planner treats as blocking.
extension DVDatabaseAdapterSchemaClassification on DVDatabaseAdapter {
  Future<DVSchemaChangeClass?> classify(DVSchemaChange change) async {
    final DVDatabaseAdapter self = this;
    if (self is DVSchemaClassifier) {
      return (self as DVSchemaClassifier).classify(change);
    }
    return null;
  }
}

/// A server's version, compared numerically.
final class DVDatabaseServerVersion
    implements Comparable<DVDatabaseServerVersion> {
  const DVDatabaseServerVersion(this.major, [this.minor = 0, this.patch = 0]);

  final int major;
  final int minor;
  final int patch;

  static final RegExp _leading = RegExp(r'^\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?');

  /// The leading `major[.minor[.patch]]` of what a server reports, or null
  /// when there is none.
  ///
  /// Null rather than zero: zero reads as a very old server and quietly picks
  /// a rule for it.
  static DVDatabaseServerVersion? tryParse(String reported) {
    final RegExpMatch? match = _leading.firstMatch(reported);
    if (match == null) return null;
    return DVDatabaseServerVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2) ?? '0'),
      int.parse(match.group(3) ?? '0'),
    );
  }

  static DVDatabaseServerVersion parse(String reported) {
    final DVDatabaseServerVersion? version = tryParse(reported);
    if (version == null) {
      throw FormatException('Not a server version', reported);
    }
    return version;
  }

  @override
  int compareTo(DVDatabaseServerVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(DVDatabaseServerVersion other) => compareTo(other) < 0;
  bool operator >=(DVDatabaseServerVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is DVDatabaseServerVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// What PostgreSQL does with each change, by server version.
final class DVPostgresSchemaRules implements DVSchemaClassifier {
  const DVPostgresSchemaRules(this.version);

  final DVDatabaseServerVersion version;

  @override
  DVSchemaChangeClass? classify(DVSchemaChange change) => switch (change) {
    DVCreateTable() => DVSchemaChangeClass.instant,
    DVAddColumn(nullable: true, defaultSql: null) =>
      DVSchemaChangeClass.instant,
    // A NOT NULL column with no default fails on a table with rows, and
    // making it succeed means filling every row first.
    DVAddColumn(nullable: false, defaultSql: null) =>
      DVSchemaChangeClass.blocking,
    // 11 stores a constant default in the catalogue; 10 rewrites the table.
    DVAddColumn() =>
      version >= const DVDatabaseServerVersion(11)
          ? DVSchemaChangeClass.instant
          : DVSchemaChangeClass.blocking,
    // CREATE INDEX CONCURRENTLY.
    DVAddIndex() => DVSchemaChangeClass.online,
    // From 12, SET NOT NULL skips its scan when a validated CHECK already
    // proves it, and the check validates without holding writers.
    DVAddNotNull() =>
      version >= const DVDatabaseServerVersion(12)
          ? DVSchemaChangeClass.online
          : DVSchemaChangeClass.blocking,
    DVChangeColumnType() => DVSchemaChangeClass.blocking,
    DVRenameColumn() => DVSchemaChangeClass.instant,
    DVDropColumn() => DVSchemaChangeClass.instant,
    DVRawSchemaChange() => null,
  };

  @override
  String toString() => 'PostgreSQL $version';
}

/// What MySQL 8 does with each change, by server version.
///
/// Only MySQL 8 is described. A 5.7 server, and MariaDB -- which reports
/// `5.5.5-` followed by its own version -- have different rules, and neither
/// is guessed at: both answer `null`, which the planner treats as blocking.
final class DVMySqlSchemaRules implements DVSchemaClassifier {
  const DVMySqlSchemaRules(this.version, {this.mariaDb = false});

  /// Rules for the version string a server reports.
  factory DVMySqlSchemaRules.forServer(String reported) {
    final DVDatabaseServerVersion? version = DVDatabaseServerVersion.tryParse(
      reported,
    );
    return DVMySqlSchemaRules(
      version ?? const DVDatabaseServerVersion(0),
      mariaDb: version == null || reported.toLowerCase().contains('mariadb'),
    );
  }

  final DVDatabaseServerVersion version;
  final bool mariaDb;

  bool _atLeast(int patch) => version >= DVDatabaseServerVersion(8, 0, patch);

  @override
  DVSchemaChangeClass? classify(DVSchemaChange change) {
    if (mariaDb || version.major != 8) return null;
    return switch (change) {
      DVCreateTable() => DVSchemaChangeClass.instant,
      DVAddColumn(nullable: false, defaultSql: null) =>
        DVSchemaChangeClass.blocking,
      // ALGORITHM=INSTANT for ADD COLUMN arrived in 8.0.12; before it the
      // table is rebuilt in place with concurrent DML allowed.
      DVAddColumn() =>
        _atLeast(12) ? DVSchemaChangeClass.instant : DVSchemaChangeClass.online,
      DVAddIndex() => DVSchemaChangeClass.online,
      // MODIFY ... NOT NULL copies the table.
      DVAddNotNull() => DVSchemaChangeClass.blocking,
      DVChangeColumnType() => DVSchemaChangeClass.blocking,
      DVRenameColumn() =>
        _atLeast(28) ? DVSchemaChangeClass.instant : DVSchemaChangeClass.online,
      DVDropColumn() =>
        _atLeast(29) ? DVSchemaChangeClass.instant : DVSchemaChangeClass.online,
      DVRawSchemaChange() => null,
    };
  }

  @override
  String toString() => mariaDb ? 'MariaDB' : 'MySQL $version';
}

/// What SQLite -- and Turso and other libSQL builds -- does with each change.
final class DVSqliteSchemaRules implements DVSchemaClassifier {
  const DVSqliteSchemaRules(this.version);

  final DVDatabaseServerVersion version;

  @override
  DVSchemaChangeClass? classify(DVSchemaChange change) => switch (change) {
    DVCreateTable() => DVSchemaChangeClass.instant,
    // SQLite refuses a NOT NULL column without a default outright; the only
    // way to one is rebuilding the table.
    DVAddColumn(nullable: false, defaultSql: null) =>
      DVSchemaChangeClass.blocking,
    DVAddColumn() => DVSchemaChangeClass.instant,
    // One writer at a time, and CREATE INDEX holds the write lock throughout.
    DVAddIndex() => DVSchemaChangeClass.blocking,
    DVAddNotNull() => DVSchemaChangeClass.blocking,
    DVChangeColumnType() => DVSchemaChangeClass.blocking,
    // RENAME COLUMN is 3.25; before it, a rename is a rebuild.
    DVRenameColumn() =>
      version >= const DVDatabaseServerVersion(3, 25)
          ? DVSchemaChangeClass.instant
          : DVSchemaChangeClass.blocking,
    // DROP COLUMN rewrites the table's content.
    DVDropColumn() => DVSchemaChangeClass.blocking,
    DVRawSchemaChange() => null,
  };

  @override
  String toString() => 'SQLite $version';
}
