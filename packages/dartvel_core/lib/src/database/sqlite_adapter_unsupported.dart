/// Web stand-in for [SqliteDVDatabaseAdapter].
///
/// SQLite needs `dart:ffi`, which the web target does not provide. Rather than
/// silently degrading to a fake database, construction fails and names the
/// adapter to use instead.
library dartvel_core.database.sqlite_unsupported;

import 'adapter.dart';

class SqliteDVDatabaseAdapter implements DVDatabaseAdapter {
  final String location;

  SqliteDVDatabaseAdapter._(this.location) {
    throw UnsupportedError(
      'SqliteDVDatabaseAdapter needs dart:ffi and is unavailable on this '
      'target. Configure MemoryDVDatabaseAdapter, or a remote database '
      'adapter, for web builds.',
    );
  }

  factory SqliteDVDatabaseAdapter.memory() =>
      SqliteDVDatabaseAdapter._(':memory:');

  factory SqliteDVDatabaseAdapter.file(
    String path, {
    bool walMode = true,
    bool foreignKeys = true,
  }) =>
      SqliteDVDatabaseAdapter._(path);

  bool get isWalEnabled => false;

  int get lastInsertRowId => 0;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async =>
      const <Map<String, Object?>>[];

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async => 0;

  void close() {}
}
