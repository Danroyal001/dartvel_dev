/// Where a device keeps its offline data models: their local copies and the
/// writes waiting to reach the server.
///
/// The framework's, and not in the barrel an application imports. A data
/// model that declares `offline:` is read and written like any other, and
/// which store is underneath is decided here, per platform:
///
/// | Platform | Store |
/// |---|---|
/// | Android, iOS, macOS, Windows, Linux, embedded, TV | a SQLite file in the application's data directory |
/// | Web | IndexedDB |
/// | none of those, or under `flutter test` | memory, reported as `DV-OFFLINE-001` |
library dartvel_core.data.offline_database;

import 'dart:async';
import 'dart:convert';

import '../database/adapter.dart';
import 'offline_database_memory.dart'
    if (dart.library.io) 'offline_database_io.dart'
    if (dart.library.js_interop) 'offline_database_web.dart' as platform;

/// Named snapshots that outlive the process holding them: one per table.
///
/// IndexedDB in a browser. Kept to three operations so the adapter over it
/// can be tested without one.
abstract class DVTableSnapshots {
  /// Every snapshot, by table name.
  Future<Map<String, String>> readAll();

  /// Replaces [table]'s snapshot.
  Future<void> write(String table, String snapshot);

  /// Forgets [table].
  Future<void> remove(String table);
}

/// The development database, kept in [DVTableSnapshots] so it survives the
/// application closing.
///
/// This is how the web gets a persistent offline store. There is no SQLite
/// in a browser, and the only database that ran there was the in-memory one:
/// a store that worked for the whole session and was empty after the tab
/// closed, with every write made offline in that session gone and nothing
/// saying so.
///
/// Each write saves the table it touched before it returns, so a write that
/// has returned has been kept. Reads save nothing.
class DVSnapshotDatabaseAdapter implements DVDatabaseAdapter {
  DVSnapshotDatabaseAdapter._(this._snapshots);

  final DVTableSnapshots _snapshots;
  final MemoryDVDatabaseAdapter _memory = MemoryDVDatabaseAdapter();
  Future<void> _saving = Future<void>.value();

  /// Opens the database [snapshots] holds.
  static Future<DVSnapshotDatabaseAdapter> open(
    DVTableSnapshots snapshots,
  ) async {
    final DVSnapshotDatabaseAdapter adapter =
        DVSnapshotDatabaseAdapter._(snapshots);
    final Map<String, String> saved = await snapshots.readAll();
    for (final MapEntry<String, String> table in saved.entries) {
      adapter._memory.importTable(
        table.key,
        jsonDecode(table.value) as Map<String, Object?>,
      );
    }
    return adapter;
  }

  static final RegExp _writes = RegExp(
    r'^\s*(?:insert\s+into|update|delete\s+from|'
    r'create\s+table(?:\s+if\s+not\s+exists)?|'
    r'drop\s+table(?:\s+if\s+exists)?)\s+([A-Za-z_]\w*)',
    caseSensitive: false,
  );

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) =>
      _memory.query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    final int changed = await _memory.execute(sql, params);
    final String? table = _writes.firstMatch(sql)?.group(1);
    if (table != null) await _save(table);
    return changed;
  }

  Future<void> _save(String table) {
    // Taken now, in the order the writes happened, and written in that
    // order: a later snapshot overtaken by an earlier one would put back the
    // table as it was before the later write.
    final Map<String, Object?>? exported = _memory.exportTable(table);
    final String? snapshot = exported == null
        ? null
        : jsonEncode(exported, toEncodable: (Object? value) => '$value');
    return _saving = _saving.then((_) => snapshot == null
        ? _snapshots.remove(table)
        : _snapshots.write(table, snapshot));
  }
}

/// Opens this device's store for [appId]'s offline data models.
///
/// A SQLite file in [directory], or in the application's data directory for
/// this platform, where there is `dart:io`; IndexedDB in a browser; memory
/// under `flutter test`, where an application's widget tests would otherwise
/// write into the developer's own data directory, and wherever the platform
/// gives nowhere that survives a restart. A memory-backed store reports
/// itself (`DV-OFFLINE-001`).
///
/// `DARTVEL_OFFLINE_DIR` in [environment] names the directory everywhere.
Future<DVDatabaseAdapter> dvLocalOfflineDatabase(
  String appId, {
  String? directory,
  String? os,
  Map<String, String>? environment,
  String? androidStateDirectory,
}) {
  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(appId) ||
      appId == '.' ||
      appId == '..') {
    throw ArgumentError.value(appId, 'appId', 'must be a plain name');
  }
  return platform.dvOpenLocalOfflineDatabase(
    appId,
    directory: directory,
    os: os,
    environment: environment,
    androidStateDirectory: androidStateDirectory,
  );
}
