/// SQLite-backed [DVDatabaseAdapter] for platforms with `dart:ffi`.
///
/// The spec makes SQLite the zero-config local database: fast, available by
/// default, and requiring no separate service for development and tests.
library dartvel_core.database.sqlite_ffi;

import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'adapter.dart';

/// A real SQLite adapter. Unlike [MemoryDVDatabaseAdapter] — which understands
/// only a handful of statement shapes — this executes arbitrary SQL.
class SqliteDVDatabaseAdapter implements DVDatabaseAdapter {
  final sqlite.Database _db;
  final String location;
  bool _closed = false;

  SqliteDVDatabaseAdapter._(this._db, this.location);

  /// In-memory database. Nothing is persisted; each instance is isolated.
  /// This is the adapter tests should use.
  factory SqliteDVDatabaseAdapter.memory() =>
      SqliteDVDatabaseAdapter._(sqlite.sqlite3.openInMemory(), ':memory:');

  /// File-backed database. Write-ahead logging is enabled where the platform
  /// supports it, and foreign keys are enforced.
  factory SqliteDVDatabaseAdapter.file(
    String path, {
    bool walMode = true,
    bool foreignKeys = true,
  }) {
    final db = sqlite.sqlite3.open(path);
    if (walMode) {
      // WAL is unavailable on some filesystems; SQLite reports the mode it
      // actually applied rather than failing, so this is best effort by design.
      db.execute('PRAGMA journal_mode = WAL;');
    }
    if (foreignKeys) {
      db.execute('PRAGMA foreign_keys = ON;');
    }
    return SqliteDVDatabaseAdapter._(db, path);
  }

  /// True when the connection applied write-ahead logging.
  bool get isWalEnabled {
    final rows = _db.select('PRAGMA journal_mode;');
    if (rows.isEmpty) return false;
    final mode = rows.first.values.first;
    return mode is String && mode.toLowerCase() == 'wal';
  }

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
