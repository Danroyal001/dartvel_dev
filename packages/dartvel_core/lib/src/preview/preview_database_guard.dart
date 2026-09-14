/// The one database a running preview may be configured with.
///
/// Installed by [DVPreviewServer.start] and checked by `DV.Database.configure`,
/// so application code that configures an adapter of its own inside a preview
/// -- a connection string copied from production's settings -- is refused
/// instead of reading real people's rows at a generated URL.
///
/// Not exported: this is the preview's to install, not the application's.
library;

import '../database/adapter.dart';
import '../database/mysql.dart';
import '../database/postgres.dart';

abstract final class DVPreviewDatabaseGuard {
  static String? _database;
  static String? _production;

  static void restrict({required String database, String? production}) {
    _database = database;
    _production = production;
  }

  static void release() {
    _database = null;
    _production = null;
  }

  /// Throws when [adapter] names a database other than the preview's own.
  ///
  /// Only server adapters name a database; a SQLite file or an in-memory
  /// adapter is the process's own and has nothing of production's to reach.
  static void check(DVDatabaseAdapter adapter) {
    final String? expected = _database;
    if (expected == null) return;
    final String? name = switch (adapter) {
      final DVPostgresDatabaseAdapter a => a.database,
      final DVMySqlDatabaseAdapter a => a.database,
      _ => null,
    };
    if (name == null || name == expected) return;
    throw StateError(
      name == _production
          ? 'This process is a preview and was configured with production\'s '
                'database, $name. A preview uses only its own database, '
                '$expected.'
          : 'This process is a preview and was configured with the database '
                '$name, which is not its own ($expected).',
    );
  }
}
