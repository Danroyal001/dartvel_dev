/// SQLite-backed [DVDatabaseAdapter] for platforms with `dart:ffi`.
///
/// The spec makes SQLite the zero-config local database: fast, available by
/// default, and requiring no separate service for development and tests.
library dartvel_core.database.sqlite_ffi;

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../schema/schema_change.dart';
import 'adapter.dart';

/// A real SQLite adapter. Unlike [MemoryDVDatabaseAdapter] — which interprets
/// the subset of SQL Dartvel itself issues — this executes arbitrary SQL.
class SqliteDVDatabaseAdapter
    implements DVDatabaseAdapter, DVSchemaClassifier {
  final sqlite.Database _db;
  final String location;

  /// What each schema change costs on the SQLite library this process linked.
  ///
  /// The linked library, not a version written down somewhere: a bundled
  /// SQLite and the system one differ, and it is the linked one that runs the
  /// statement.
  DVSqliteSchemaRules get schemaRules => DVSqliteSchemaRules(
        DVDatabaseServerVersion.parse(sqlite.sqlite3.version.libVersion),
      );

  @override
  DVSchemaChangeClass? classify(DVSchemaChange change) =>
      schemaRules.classify(change);
  bool _closed = false;

  SqliteDVDatabaseAdapter._(this._db, this.location);

  /// In-memory database. Nothing is persisted; each instance is isolated.
  /// This is the adapter tests should use.
  factory SqliteDVDatabaseAdapter.memory() =>
      SqliteDVDatabaseAdapter._(sqlite.sqlite3.openInMemory(), ':memory:');

  /// File-backed database. Write-ahead logging is enabled where the platform
  /// supports it, and foreign keys are enforced.
  ///
  /// A write that meets another connection's lock waits up to
  /// [busyTimeoutMilliseconds] for it rather than failing. Opening waits
  /// longer, up to [openTimeoutMilliseconds]: every process of a deployment
  /// opens the file as it starts, and the first one after a restart rebuilds
  /// the WAL index, which takes seconds on a large log.
  ///
  /// The `-wal` file is cut back to [journalSizeLimitBytes] after each
  /// checkpoint, so one large write does not leave a huge log behind for
  /// every later start to scan.
  factory SqliteDVDatabaseAdapter.file(
    String path, {
    bool walMode = true,
    bool foreignKeys = true,
    int busyTimeoutMilliseconds = 5000,
    int openTimeoutMilliseconds = 60000,
    int journalSizeLimitBytes = 64 * 1024 * 1024,
  }) {
    final db = sqlite.sqlite3.open(path);
    // Before anything else touches the file. A file is shared by every
    // process of a deployment that runs on one host -- the web process
    // dispatching, the worker reserving, two cron processes claiming one
    // occurrence -- and with no busy timeout a write that meets another
    // connection's lock fails at once with "database is locked" rather than
    // waiting the milliseconds the other write takes.
    final openWait = openTimeoutMilliseconds > busyTimeoutMilliseconds
        ? openTimeoutMilliseconds
        : busyTimeoutMilliseconds;
    db.execute('PRAGMA busy_timeout = $openWait;');
    try {
      if (walMode && !_journalModeIsWal(db)) {
        // WAL is unavailable on some filesystems; SQLite reports the mode it
        // actually applied rather than failing, so this is best effort by
        // design. A file already in WAL is left alone: asking again waits on
        // any recovery another process is running.
        db.execute('PRAGMA journal_mode = WAL;');
      }
      if (journalSizeLimitBytes >= 0) {
        db.execute('PRAGMA journal_size_limit = $journalSizeLimitBytes;');
      }
      if (foreignKeys) {
        db.execute('PRAGMA foreign_keys = ON;');
      }
    } catch (_) {
      db.dispose();
      rethrow;
    }
    db.execute('PRAGMA busy_timeout = $busyTimeoutMilliseconds;');
    return SqliteDVDatabaseAdapter._(db, path);
  }

  static bool _journalModeIsWal(sqlite.Database db) {
    final rows = db.select('PRAGMA journal_mode;');
    if (rows.isEmpty) return false;
    final mode = rows.first.values.first;
    return mode is String && mode.toLowerCase() == 'wal';
  }

  /// True when the connection applied write-ahead logging.
  bool get isWalEnabled => _journalModeIsWal(_db);

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    _assertOpen();
    final result = _db.select(sql, _bind(params));
    return List<Map<String, Object?>>.unmodifiable(<Map<String, Object?>>[
      for (final row in result)
        Map<String, Object?>.unmodifiable(<String, Object?>{
          for (final column in result.columnNames) column: row[column],
        }),
    ]);
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    _assertOpen();
    _db.execute(sql, _bind(params));
    return _db.updatedRows;
  }

  /// Row id assigned by the most recent insert on this connection.
  int get lastInsertRowId => _db.lastInsertRowId;

  void close() {
    if (_closed) return;
    _closed = true;
    _db.dispose();
  }

  void _assertOpen() {
    if (_closed) {
      throw StateError(
        'This SqliteDVDatabaseAdapter ($location) is closed.',
      );
    }
  }

  static List<Object?> _bind(List<Object?>? params) =>
      params == null ? const <Object?>[] : List<Object?>.of(params);
}
