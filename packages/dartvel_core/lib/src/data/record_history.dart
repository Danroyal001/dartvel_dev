/// Record history and optimistic concurrency: versioned writes, change logs,
/// revert, and soft delete, over any [DVDatabaseAdapter].
///
/// This is the runtime the specification's `# Record History and Optimistic
/// Concurrency` describes. A generated model reaches it through its table; it
/// is also usable directly, which is how it is tested.
library dartvel_core.data.record_history;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../database/adapter.dart';
import '../transaction/transaction.dart';
import 'change_capture.dart';

/// How a write that finds its row moved since it was read is resolved.
///
/// One vocabulary for the online case and the offline one: the difference is
/// not the strategies, it is whether anybody is present to ask. [ask] refuses
/// the write and hands both versions back, which is only possible when the
/// writer is there -- so it is the online default and not a legal offline
/// strategy (`DV-HISTORY-002`).
final class DVConflict {
  const DVConflict._(this.name, {this.allowedOffline = true}) : _resolve = null;

  const DVConflict._resolver(this._resolve)
      : name = 'resolver',
        allowedOffline = true;

  /// Refuse the write and hand both versions to the caller.
  static const DVConflict ask = DVConflict._('ask', allowedOffline: false);

  /// The later write replaces the whole record.
  static const DVConflict lastWriteWins = DVConflict._('lastWriteWins');

  /// The row keeps what it holds; the local change is discarded and reported.
  static const DVConflict serverWins = DVConflict._('serverWins');

  /// Per field: a field this writer changed from what it read takes this
  /// writer's value, and every other field keeps the row's.
  static const DVConflict fieldMerge = DVConflict._('fieldMerge');

  /// A resolver the application writes, given both versions, returning the
  /// values to store.
  factory DVConflict.resolver(
    Map<String, Object?> Function(DVConflictError conflict) resolve,
  ) =>
      DVConflict._resolver(resolve);

  final String name;

  /// Whether a device can use this strategy while disconnected, where nobody
  /// is present at the moment of the merge.
  final bool allowedOffline;

  final Map<String, Object?> Function(DVConflictError conflict)? _resolve;

  @override
  String toString() => 'DVConflict.$name';
}

/// A write refused because the record changed since it was read
/// (`DV-HISTORY-001`).
class DVConflictError implements Exception {
  DVConflictError({
    required this.table,
    required this.key,
    required Map<String, Object?> mine,
    required Map<String, Object?> theirs,
    required Map<String, Object?>? base,
    required this.expectedVersion,
    required this.actualVersion,
  })  : mine = Map<String, Object?>.unmodifiable(mine),
        theirs = Map<String, Object?>.unmodifiable(theirs),
        base = base == null ? null : Map<String, Object?>.unmodifiable(base);

  final String code = 'DV-HISTORY-001';
  final String table;
  final Object key;

  /// What this session wrote.
  final Map<String, Object?> mine;

  /// What the row holds now.
  final Map<String, Object?> theirs;

  /// What this session read, or null when it wrote without reading -- which
  /// is the lost update with extra steps, and refused for the same reason.
  final Map<String, Object?>? base;

  /// The version this session read, or null when it read none.
  final int? expectedVersion;

  /// The version the row holds.
  final int actualVersion;

  @override
  String toString() => '$code: $table[$key] changed since it was read '
      '(read version ${expectedVersion ?? 'none'}, row is at $actualVersion). '
      'Reload it, or resolve with a DVConflict strategy.';
}

/// A history entry could not be written, so the change it recorded was
/// undone rather than kept unrecorded (`DV-HISTORY-005`).
class DVHistoryWriteError implements Exception {
  DVHistoryWriteError({
    required this.table,
    required this.key,
    required this.cause,
  });

  final String code = 'DV-HISTORY-005';
  final String table;
  final Object key;
  final Object cause;

  @override
  String toString() => '$code: the history entry for $table[$key] could not '
      'be written, so the change was rolled back: $cause';
}

/// A restore refused because a live record holds a unique field the deleted
/// one would claim (`DV-HISTORY-006`).
class DVRestoreConflictError implements Exception {
  DVRestoreConflictError({
    required this.table,
    required this.key,
    required Set<String> fields,
  }) : fields = Set<String>.unmodifiable(fields);

  final String code = 'DV-HISTORY-006';
  final String table;
  final Object key;

  /// The unique fields a live record already holds.
  final Set<String> fields;

  @override
  String toString() => '$code: $table[$key] cannot be restored; a live record '
      'already holds ${fields.join(', ')}.';
}

/// Whether a model keeps a change log, and for how long.
///
/// Opt-in, with retention declared beside it: a change log is a second copy
/// of the data with a different lifetime, and keeping it for every model
/// would double storage quietly and put values somewhere retention was never
/// applied.
class DVHistory {
  const DVHistory({this.keep});

  /// How long entries are kept; null keeps them until removed deliberately.
  final Duration? keep;
}

/// A stored record: its values, the version they are at, and whether it is
/// soft-deleted.
class DVRecord {
  DVRecord({
    required this.key,
    required this.version,
    required Map<String, Object?> values,
    this.deletedAt,
  }) : values = Map<String, Object?>.unmodifiable(values);

  final Object key;
  final int version;
  final Map<String, Object?> values;

  /// When the record was soft-deleted, or null when it is live.
  final DateTime? deletedAt;

  @override
  String toString() => 'DVRecord($key v$version${deletedAt == null ? '' : ' deleted'})';
}

/// The outcome of a write.
class DVWriteResult {
  const DVWriteResult(this.record, {this.conflict, this.discarded = false});

  /// The record as stored after the write.
  final DVRecord record;

  /// The conflict a strategy resolved, or null when there was none.
  final DVConflictError? conflict;

  /// Whether the local change was discarded, as [DVConflict.serverWins] does.
  final bool discarded;
}

/// How one field changed in one history entry.
class DVFieldChange {
  const DVFieldChange({this.from, this.to}) : redacted = false;

  /// A sensitive field: that it changed, and nothing about what to.
  const DVFieldChange.redacted()
      : from = null,
        to = null,
        redacted = true;

  final Object? from;
  final Object? to;

  /// Whether the values were withheld because the field is sensitive.
  final bool redacted;

  Map<String, Object?> toJson() => redacted
      ? const <String, Object?>{'redacted': true}
      : <String, Object?>{'from': from, 'to': to};

  factory DVFieldChange.fromJson(Map<String, Object?> json) =>
      json['redacted'] == true
          ? const DVFieldChange.redacted()
          : DVFieldChange(from: json['from'], to: json['to']);
}

/// One change to one record: who, when, in which transaction, and what.
class DVHistoryEntry {
  DVHistoryEntry({
    required this.id,
    required this.key,
    required this.version,
    required this.at,
    required Map<String, DVFieldChange> changes,
    this.actor,
    this.tenant,
    this.transactionId,
    this.deleted = false,
    this.restored = false,
  }) : changes = Map<String, DVFieldChange>.unmodifiable(changes);

  final String id;
  final Object key;

  /// The record's version after this change.
  final int version;
  final DateTime at;
  final Map<String, DVFieldChange> changes;
  final String? actor;
  final String? tenant;
  final String? transactionId;

  /// Whether this change deleted the record.
  final bool deleted;

  /// Whether this change restored a deleted record.
  final bool restored;
}

/// The outcome of a revert.
class DVRevertResult {
  DVRevertResult(this.record, {Set<String> unrestored = const <String>{}})
      : unrestored = Set<String>.unmodifiable(unrestored);

  /// The record as stored after the revert.
  final DVRecord record;

  /// Sensitive fields the revert could not put back, because history records
  /// that they changed and never what they held. Left as they are, to be set
  /// deliberately.
  final Set<String> unrestored;

  /// `DV-HISTORY-003` when fields could not be restored, otherwise null.
  String? get code => unrestored.isEmpty ? null : 'DV-HISTORY-003';
}

/// A versioned table with optional history and soft delete.
///
/// Every write carries the version it read and is applied with a conditional
/// update, so a write against a row that has moved is refused rather than
/// silently replacing the change that moved it. When history is enabled the
/// entry is written alongside the change, and a change whose entry cannot be
/// written is undone -- a change log that can miss entries is not a record of
/// anything. Inside `DV.transaction` every write registers its own inverse, so
/// a failure later in the unit of work takes the write and its entry with it.
class DVRecordTable {
  DVRecordTable({
    required this.table,
    required this.key,
    required List<String> columns,
    Set<String> sensitive = const <String>{},
    Set<String> unique = const <String>{},
    DVHistory? history,
    this.versioned = true,
    this.softDelete = false,
    this.capture,
    DVDatabaseAdapter? database,
  })  : historyPolicy = history,
        columns = List<String>.unmodifiable(columns),
        sensitive = Set<String>.unmodifiable(sensitive),
        unique = Set<String>.unmodifiable(unique),
        _database = database {
    // Names are interpolated into SQL, so they are checked rather than
    // trusted; a value never is -- values are always bound parameters.
    for (final String name in <String>[table, key, ...columns]) {
      if (!_identifier.hasMatch(name)) {
        throw ArgumentError.value(name, 'name', 'not a plain SQL identifier');
      }
    }
    if (!columns.contains(key)) {
      throw ArgumentError.value(key, 'key', 'is not one of the columns');
    }
    for (final String name in <String>{...sensitive, ...unique}) {
      if (!columns.contains(name)) {
        throw ArgumentError.value(name, 'field', 'is not one of the columns');
      }
    }
    capture?.track(this);
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// The column holding each row's version.
  static const String versionColumn = '_dv_version';

  /// The column holding when a row was soft-deleted.
  static const String deletedColumn = '_dv_deleted_at';

  final String table;
  final String key;
  final List<String> columns;

  /// Fields recorded as changed, never as values.
  final Set<String> sensitive;

  /// Fields a restore must not duplicate among live records.
  final Set<String> unique;

  /// Null when this table keeps no change log.
  final DVHistory? historyPolicy;

  /// Whether writes are checked against the version they read. `false` is for
  /// append-only data where writes never contend, and says so where the table
  /// is declared.
  final bool versioned;

  /// Whether delete marks the row rather than removing it.
  final bool softDelete;

  /// The change capture log every write is recorded to, or null when the
  /// model is not captured. Sensitive fields are left out of it.
  final DVCapture? capture;

  final DVDatabaseAdapter? _database;

  /// Where the rows live: the adapter given, or the configured database.
  DVDatabaseAdapter get database => _database ?? const _ConfiguredDatabase();

  /// Where the change log lives.
  String get historyTable => '${table}__history';

  List<String> get _storedColumns =>
      <String>[...columns, versionColumn, deletedColumn];

  /// Creates the table, and its history table when history is enabled.
  ///
  /// Columns carry no declared type. SQLite would otherwise apply a type
  /// affinity and hand back `'1'` for a stored `1`, and every diff after that
  /// would report a change that did not happen.
  Future<void> ensureSchema() async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $table (${_storedColumns.join(', ')})',
    );
    if (historyPolicy != null) {
      await database.execute(
        'CREATE TABLE IF NOT EXISTS $historyTable (entry_id, record_key, '
        'record_version, actor, tenant, transaction_id, occurred_at, changes, '
        'deleted, restored)',
      );
    }
  }

  /// The record with [id], or null. A soft-deleted record is null unless
  /// [withDeleted].
  Future<DVRecord?> read(Object id, {bool withDeleted = false}) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT * FROM $table WHERE $key = ?',
      <Object?>[id],
    );
    if (rows.isEmpty) return null;
    final DVRecord record = _fromRow(rows.first);
    if (!withDeleted && record.deletedAt != null) return null;
    return record;
  }

  /// Every record, excluding soft-deleted ones unless [withDeleted].
  Future<List<DVRecord>> all({bool withDeleted = false}) async {
    final List<Map<String, Object?>> rows = await database.query(
      withDeleted || !softDelete
          ? 'SELECT * FROM $table'
          : 'SELECT * FROM $table WHERE $deletedColumn IS NULL',
    );
    return <DVRecord>[
      for (final Map<String, Object?> row in rows)
        if (withDeleted || _fromRow(row).deletedAt == null) _fromRow(row),
    ];
  }

  /// Stores [values]: inserts a new record, or updates an existing one
  /// checked against [base], the record as this writer read it.
  ///
  /// An update with no [base] is refused under [DVConflict.ask]: a writer that
  /// never read the row cannot know what it is replacing.
  Future<DVWriteResult> write(
    Map<String, Object?> values, {
    DVRecord? base,
    DVConflict onConflict = DVConflict.ask,
    String? actor,
    String? tenant,
  }) async {
    final Map<String, Object?> mine = _normalize(values);
    final Object? id = mine[key];
    if (id == null) {
      throw ArgumentError.value(values, 'values', 'has no $key');
    }

    final DVRecord? current = await read(id, withDeleted: true);
    if (current == null) {
      return DVWriteResult(await _insert(id, mine, actor, tenant));
    }

    if (versioned && base?.version != current.version) {
      final DVConflictError conflict = DVConflictError(
        table: table,
        key: id,
        mine: mine,
        theirs: current.values,
        base: base?.values,
        expectedVersion: base?.version,
        actualVersion: current.version,
      );
      final Map<String, Object?> target;
      switch (onConflict.name) {
        case 'ask':
          throw conflict;
        case 'serverWins':
          return DVWriteResult(current, conflict: conflict, discarded: true);
        case 'lastWriteWins':
          target = mine;
        case 'fieldMerge':
          final Map<String, Object?>? read = base?.values;
          if (read == null) throw conflict;
          target = <String, Object?>{
            for (final String column in columns)
              column: _same(mine[column], read[column])
                  ? current.values[column]
                  : mine[column],
          };
        default:
          target = _normalize(onConflict._resolve!(conflict));
      }
      final DVRecord record = await _update(
        current,
        <String, Object?>{...target, key: id},
        deletedAt: current.deletedAt,
        actor: actor,
        tenant: tenant,
      );
      return DVWriteResult(record, conflict: conflict);
    }

    return DVWriteResult(
      await _update(current, mine,
          deletedAt: current.deletedAt, actor: actor, tenant: tenant),
    );
  }

  /// Deletes the record: marks it when [softDelete], removes it otherwise.
  Future<void> delete(Object id, {String? actor, String? tenant}) async {
    final DVRecord? current = await read(id, withDeleted: true);
    if (current == null) return;

    if (softDelete) {
      if (current.deletedAt != null) return;
      await _update(current, current.values,
          deletedAt: _now(), actor: actor, tenant: tenant, deleted: true);
      return;
    }

    await database.execute(
      'DELETE FROM $table WHERE $key = ? AND $versionColumn = ?',
      <Object?>[id, current.version],
    );
    final String? entry;
    try {
      entry = await _log(
        id,
        current.version + 1,
        _diff(current.values, const <String, Object?>{}),
        actor: actor,
        tenant: tenant,
        deleted: true,
      );
    } catch (error) {
      await _insertRow(current);
      throw DVHistoryWriteError(table: table, key: id, cause: error);
    }
    try {
      await capture?.record(
        table: this,
        operation: DVCaptureOp.delete,
        key: id,
        version: current.version + 1,
        values: const <String, Object?>{},
        tenant: tenant,
      );
    } catch (error) {
      await _insertRow(current);
      await _unlog(entry);
      throw DVCaptureWriteError(table: table, key: id, cause: error);
    }
    DVTransactionRunner.activeContext?.compensate(() async {
      await _insertRow(current);
      await _unlog(entry);
    });
  }

  /// Restores a soft-deleted record.
  ///
  /// Refused rather than forced when a live record holds one of its [unique]
  /// fields, because the alternative is two live rows claiming one value.
  Future<DVRecord> restore(Object id, {String? actor, String? tenant}) async {
    final DVRecord? current = await read(id, withDeleted: true);
    if (current == null) {
      throw StateError('$table[$id] does not exist, so it cannot be restored.');
    }
    if (current.deletedAt == null) return current;

    final Set<String> taken = <String>{};
    for (final String field in unique) {
      final Object? value = current.values[field];
      if (value == null) continue;
      final List<Map<String, Object?>> holders = await database.query(
        'SELECT $key FROM $table WHERE $field = ? AND $deletedColumn IS NULL',
        <Object?>[value],
      );
      if (holders.any((Map<String, Object?> row) => !_same(row[key], id))) {
        taken.add(field);
      }
    }
    if (taken.isNotEmpty) {
      throw DVRestoreConflictError(table: table, key: id, fields: taken);
    }

    return _update(current, current.values,
        deletedAt: null, actor: actor, tenant: tenant, restored: true);
  }

  /// The record's change log, oldest first. Empty when history is off.
  Future<List<DVHistoryEntry>> history(Object id) async {
    if (historyPolicy == null) return const <DVHistoryEntry>[];
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT * FROM $historyTable WHERE record_key = ? '
      'ORDER BY record_version ASC',
      <Object?>[id],
    );
    return rows.map(_entryFromRow).toList(growable: false);
  }

  /// Puts the record back as it was after [to], as a new change.
  ///
  /// A revert adds to the history rather than rewinding it: the entries in
  /// between are the audit. It takes the same version check as any write when
  /// [base] is given, and inside `DV.transaction` rolls back with it.
  /// Sensitive fields changed since [to] cannot be put back -- history holds
  /// that they changed, not what they held -- and are reported in
  /// [DVRevertResult.unrestored].
  Future<DVRevertResult> revert(
    Object id, {
    required DVHistoryEntry to,
    DVRecord? base,
    String? actor,
    String? tenant,
  }) async {
    final DVRecord? current = await read(id, withDeleted: true);
    if (current == null) {
      throw StateError('$table[$id] does not exist, so it cannot be reverted.');
    }

    final List<DVHistoryEntry> entries = await history(id);
    final Map<String, Object?> state = Map<String, Object?>.of(current.values);
    final Set<String> unrestored = <String>{};
    for (final DVHistoryEntry entry in entries.reversed) {
      if (entry.version <= to.version) break;
      entry.changes.forEach((String field, DVFieldChange change) {
        if (change.redacted) {
          unrestored.add(field);
        } else {
          state[field] = change.from;
        }
      });
    }

    if (versioned && base != null && base.version != current.version) {
      throw DVConflictError(
        table: table,
        key: id,
        mine: state,
        theirs: current.values,
        base: base.values,
        expectedVersion: base.version,
        actualVersion: current.version,
      );
    }

    final DVRecord record = await _update(current, state,
        deletedAt: current.deletedAt, actor: actor, tenant: tenant);
    return DVRevertResult(record, unrestored: unrestored);
  }

  /// Removes history entries older than [DVHistory.keep] (`DV-HISTORY-004`),
  /// returning how many. Never touches the records themselves.
  Future<int> prune({DateTime? now}) async {
    final Duration? keep = historyPolicy?.keep;
    if (keep == null) return 0;
    final String cutoff = _stamp((now ?? DateTime.now()).subtract(keep));
    return database.execute(
      'DELETE FROM $historyTable WHERE occurred_at < ?',
      <Object?>[cutoff],
    );
  }

  // --- writes ---------------------------------------------------------------

  Future<DVRecord> _insert(
    Object id,
    Map<String, Object?> values,
    String? actor,
    String? tenant,
  ) async {
    final DVRecord record = DVRecord(key: id, version: 1, values: values);
    await _insertRow(record);
    final String? entry;
    try {
      entry = await _log(
        id,
        1,
        _diff(const <String, Object?>{}, values),
        actor: actor,
        tenant: tenant,
      );
    } catch (error) {
      await database.execute(
        'DELETE FROM $table WHERE $key = ? AND $versionColumn = ?',
        <Object?>[id, 1],
      );
      throw DVHistoryWriteError(table: table, key: id, cause: error);
    }
    try {
      await capture?.record(
        table: this,
        operation: DVCaptureOp.insert,
        key: id,
        version: 1,
        values: values,
        tenant: tenant,
      );
    } catch (error) {
      await database.execute(
        'DELETE FROM $table WHERE $key = ? AND $versionColumn = ?',
        <Object?>[id, 1],
      );
      await _unlog(entry);
      throw DVCaptureWriteError(table: table, key: id, cause: error);
    }
    DVTransactionRunner.activeContext?.compensate(() async {
      await database.execute(
        'DELETE FROM $table WHERE $key = ? AND $versionColumn = ?',
        <Object?>[id, 1],
      );
      await _unlog(entry);
    });
    return record;
  }

  Future<void> _insertRow(DVRecord record) => database.execute(
        'INSERT INTO $table (${_storedColumns.join(', ')}) '
        'VALUES (${List<String>.filled(_storedColumns.length, '?').join(', ')})',
        <Object?>[
          for (final String column in columns) record.values[column],
          record.version,
          record.deletedAt == null ? null : _stamp(record.deletedAt!),
        ],
      );

  /// Moves [current] to [values] at the next version, conditional on the row
  /// still being at [current]'s version, with its history entry.
  Future<DVRecord> _update(
    DVRecord current,
    Map<String, Object?> values, {
    required DateTime? deletedAt,
    String? actor,
    String? tenant,
    bool deleted = false,
    bool restored = false,
  }) async {
    final Map<String, DVFieldChange> changes = _diff(current.values, values);
    final bool deletionChanged = (deletedAt == null) != (current.deletedAt == null);
    if (changes.isEmpty && !deletionChanged) return current;

    final int next = current.version + 1;
    final DVRecord record = DVRecord(
      key: current.key,
      version: next,
      values: values,
      deletedAt: deletedAt,
    );
    final int affected = await _setRow(record, expected: current.version);
    if (affected != 1) {
      final DVRecord? now = await read(current.key, withDeleted: true);
      throw DVConflictError(
        table: table,
        key: current.key,
        mine: values,
        theirs: now?.values ?? const <String, Object?>{},
        base: current.values,
        expectedVersion: current.version,
        actualVersion: now?.version ?? -1,
      );
    }

    final String? entry;
    try {
      entry = await _log(current.key, next, changes,
          actor: actor, tenant: tenant, deleted: deleted, restored: restored);
    } catch (error) {
      await _setRow(current, expected: next);
      throw DVHistoryWriteError(table: table, key: current.key, cause: error);
    }
    try {
      await capture?.record(
        table: this,
        operation: deleted
            ? DVCaptureOp.delete
            : restored
                ? DVCaptureOp.restore
                : DVCaptureOp.update,
        key: current.key,
        version: next,
        values: deleted ? const <String, Object?>{} : values,
        tenant: tenant,
      );
    } catch (error) {
      await _setRow(current, expected: next);
      await _unlog(entry);
      throw DVCaptureWriteError(table: table, key: current.key, cause: error);
    }

    DVTransactionRunner.activeContext?.compensate(() async {
      await _setRow(current, expected: next);
      await _unlog(entry);
    });
    return record;
  }

  /// Writes [record] over the row, if the row is at version [expected].
  Future<int> _setRow(DVRecord record, {required int expected}) {
    final String assignments =
        _storedColumns.map((String column) => '$column = ?').join(', ');
    return database.execute(
      'UPDATE $table SET $assignments WHERE $key = ? AND $versionColumn = ?',
      <Object?>[
        for (final String column in columns) record.values[column],
        record.version,
        record.deletedAt == null ? null : _stamp(record.deletedAt!),
        record.key,
        expected,
      ],
    );
  }

  // --- history --------------------------------------------------------------

  Future<String?> _log(
    Object id,
    int version,
    Map<String, DVFieldChange> changes, {
    String? actor,
    String? tenant,
    bool deleted = false,
    bool restored = false,
  }) async {
    if (historyPolicy == null) return null;
    final String entry = _newEntryId();
    await database.execute(
      'INSERT INTO $historyTable (entry_id, record_key, record_version, actor, '
      'tenant, transaction_id, occurred_at, changes, deleted, restored) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        entry,
        id,
        version,
        actor,
        tenant,
        DVTransactionRunner.activeContext?.transactionId,
        _stamp(_now()),
        jsonEncode(<String, Object?>{
          for (final MapEntry<String, DVFieldChange> change in changes.entries)
            change.key: change.value.toJson(),
        }),
        deleted ? 1 : 0,
        restored ? 1 : 0,
      ],
    );
    return entry;
  }

  Future<void> _unlog(String? entry) async {
    if (entry == null) return;
    await database.execute(
      'DELETE FROM $historyTable WHERE entry_id = ?',
      <Object?>[entry],
    );
  }

  /// What changed from [before] to [after], with sensitive fields recorded as
  /// changed and never as values -- copying one into a change log would defeat
  /// its exclusion from logs and traces in the one place nobody looks.
  Map<String, DVFieldChange> _diff(
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) =>
      <String, DVFieldChange>{
        for (final String column in columns)
          if (!_same(before[column], after[column]))
            column: sensitive.contains(column)
                ? const DVFieldChange.redacted()
                : DVFieldChange(
                    from: _jsonSafe(before[column]),
                    to: _jsonSafe(after[column]),
                  ),
      };

  DVHistoryEntry _entryFromRow(Map<String, Object?> row) {
    final Object? raw = row['changes'];
    final Map<String, Object?> decoded = raw is String && raw.isNotEmpty
        ? (jsonDecode(raw) as Map<String, Object?>)
        : const <String, Object?>{};
    return DVHistoryEntry(
      id: '${row['entry_id']}',
      key: row['record_key'] ?? '',
      version: _asInt(row['record_version']),
      at: DateTime.parse('${row['occurred_at']}'),
      changes: <String, DVFieldChange>{
        for (final MapEntry<String, Object?> change in decoded.entries)
          change.key:
              DVFieldChange.fromJson(change.value! as Map<String, Object?>),
      },
      actor: row['actor'] as String?,
      tenant: row['tenant'] as String?,
      transactionId: row['transaction_id'] as String?,
      deleted: _asBool(row['deleted']),
      restored: _asBool(row['restored']),
    );
  }

  // --- values ---------------------------------------------------------------

  Map<String, Object?> _normalize(Map<String, Object?> values) {
    final Iterable<String> unknown =
        values.keys.where((String name) => !columns.contains(name));
    if (unknown.isNotEmpty) {
      // Refused rather than dropped: a field silently not stored reads back as
      // a save that worked.
      throw ArgumentError.value(
          unknown.join(', '), 'values', 'are not columns of $table');
    }
    return <String, Object?>{
      for (final String column in columns) column: values[column],
    };
  }

  DVRecord _fromRow(Map<String, Object?> row) {
    final Object? deleted = row[deletedColumn];
    return DVRecord(
      key: row[key] ?? '',
      version: _asInt(row[versionColumn]),
      values: <String, Object?>{
        for (final String column in columns) column: row[column],
      },
      deletedAt: deleted == null ? null : DateTime.parse('$deleted'),
    );
  }
}

/// The database `DV.Database` is configured with, as an adapter.
class _ConfiguredDatabase implements DVDatabaseAdapter {
  const _ConfiguredDatabase();

  @override
  Future<List<Map<String, Object?>>> query(String sql,
          [List<Object?>? params]) =>
      const DVDatabase().query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) =>
      const DVDatabase().execute(sql, params);
}

bool _same(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  return a == b;
}

Object? _jsonSafe(Object? value) =>
    value == null || value is num || value is String || value is bool
        ? value
        : '$value';

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

bool _asBool(Object? value) => value == true || value == 1 || value == '1';

DateTime _now() => DateTime.now().toUtc();

/// A timestamp at millisecond precision in UTC, so stored stamps compare
/// correctly as strings: Dart omits microseconds when they are zero, and
/// `.123Z` sorts after `.123456Z`.
String _stamp(DateTime time) => DateTime.fromMillisecondsSinceEpoch(
      time.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();

final math.Random _entryRandom = math.Random();
int _entryCounter = 0;

String _newEntryId() {
  _entryCounter = (_entryCounter + 1) & 0xFFFFFF;
  return 'h-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_entryCounter.toRadixString(36)}-'
      '${_entryRandom.nextInt(0x7FFFFFFF).toRadixString(36)}';
}
