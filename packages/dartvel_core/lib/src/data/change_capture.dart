/// Change data capture: a model's own writes as an ordered, replayable log,
/// delivered in order to destinations that are not databases.
///
/// This is the runtime the specification's `# Change Data Capture and
/// Warehouse Sync` describes. The log is written by [DVRecordTable] -- the
/// versioned write path every captured model goes through -- so it reads the
/// writes the application already makes rather than instrumenting anything
/// new, and it inherits their tenant and their sensitive-field declarations.
///
/// Every guard here is against a silent failure. A change from a transaction
/// that rolled back is never published, because publication happens after
/// commit. A crash between a delivery and its checkpoint redelivers the batch
/// under the same change ids rather than skipping it. A consumer that fell
/// behind the retention window is refused rather than handed a gap. Rows that
/// commit in a different order to the one they were written in carry their
/// record version, so a destination keeps the newest. A sensitive field is
/// never in the log's own storage, and an erasure removes the values the log
/// already held.
library dartvel_core.data.change_capture;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../dartvel.dart' show DVJobEnvelope, DVQueues;
import '../database/adapter.dart';
import '../observability/observability.dart';
import '../privacy/privacy.dart';
import '../tenancy/tenants.dart';
import '../transaction/transaction.dart';
import 'record_history.dart';

/// What a captured change did to its record.
enum DVCaptureOp {
  insert,
  update,

  /// The record stopped being live: removed, soft-deleted, or erased.
  delete,

  /// A soft-deleted record came back.
  restore,

  /// A backfill's copy of a record as it stands, not a write.
  snapshot,
}

/// Whether a schema change adds columns at a destination or removes them.
enum DVCaptureSchemaPhase { expand, contract }

/// One captured change to one record.
class DVCapturedChange {
  DVCapturedChange({
    required this.id,
    required this.sequence,
    required this.model,
    required this.key,
    required this.operation,
    required this.version,
    required this.occurredAt,
    Map<String, Object?> values = const <String, Object?>{},
    Set<String> redacted = const <String>{},
    this.tenant,
    this.transactionId,
    this.erased = false,
  })  : values = Map<String, Object?>.unmodifiable(values),
        redacted = Set<String>.unmodifiable(redacted);

  /// Stable across redelivery, so a destination can deduplicate on it.
  final String id;

  /// The change's place in the log. Increasing in commit order.
  final int sequence;

  /// The table the record lives in.
  final String model;
  final Object? key;
  final DVCaptureOp operation;

  /// The record's version after this change. Two changes to one record that
  /// committed out of order still compare correctly on it.
  final int version;
  final DateTime occurredAt;

  /// The record's non-sensitive values after the change; empty for a delete.
  final Map<String, Object?> values;

  /// Sensitive fields the model declares. Named, never valued.
  final Set<String> redacted;
  final String? tenant;
  final String? transactionId;

  /// Whether this change is an erasure, which supersedes every earlier change
  /// to the record however it arrives.
  final bool erased;

  @override
  String toString() =>
      'DVCapturedChange(#$sequence $model[$key] ${operation.name} v$version)';
}

/// A column change a destination applies before the rows that need it.
class DVCaptureSchemaChange {
  DVCaptureSchemaChange({
    required this.sequence,
    required this.model,
    required this.phase,
    required List<String> columns,
  }) : columns = List<String>.unmodifiable(columns);

  final int sequence;
  final String model;
  final DVCaptureSchemaPhase phase;

  /// The destination columns added or removed. Sensitive fields are never
  /// among them: a destination has no column to hold one.
  final List<String> columns;

  @override
  String toString() =>
      'DVCaptureSchemaChange(#$sequence $model ${phase.name} $columns)';
}

/// Changes handed to a destination together, in sequence order.
class DVCaptureBatch {
  DVCaptureBatch({
    required this.consumer,
    required List<DVCapturedChange> changes,
    required this.atLeastOnce,
  }) : changes = List<DVCapturedChange>.unmodifiable(changes);

  final String consumer;
  final List<DVCapturedChange> changes;

  /// True when the destination cannot deduplicate, so a redelivered batch
  /// lands twice (`DV-CDC-004`).
  final bool atLeastOnce;
}

/// A sync destination: a warehouse, a column store, files in object storage.
///
/// Not a database adapter. No model is stored in a destination and no query
/// is served from one; a capture stream is written to it.
abstract interface class DVCaptureSink {
  String get name;

  /// Whether applying a change twice leaves the same result. None promises
  /// exactly-once delivery; this is what makes at-least-once harmless.
  bool get deduplicates;

  /// Applies [batch]. Throwing leaves the checkpoint where it was, and the
  /// whole batch is delivered again (`DV-CDC-001`).
  Future<void> write(DVCaptureBatch batch);

  /// Adds or removes columns. Must be idempotent: a crash after it and before
  /// the checkpoint delivers it again.
  Future<void> evolve(DVCaptureSchemaChange change);

  /// Applies an erasure now, out of band, superseding every change to the
  /// same records with a lower sequence -- including one already in flight.
  Future<void> erase(List<DVCapturedChange> changes);

  /// A backfill copied every live row of [model] as of [throughSequence];
  /// anything the destination holds that the backfill did not touch and no
  /// later change wrote is gone from the source.
  Future<void> backfillComplete(
    String model,
    int throughSequence, {
    String? tenant,
  });
}

/// A captured change could not be written to the log, so the write it
/// recorded was undone rather than kept uncaptured.
class DVCaptureWriteError implements Exception {
  DVCaptureWriteError({
    required this.table,
    required this.key,
    required this.cause,
  });

  final String table;
  final Object key;
  final Object cause;

  @override
  String toString() => 'The captured change for $table[$key] could not be '
      'written, so the change was rolled back: $cause';
}

/// `DV-CDC-001`: a destination refused a batch; delivery is retrying.
class DVCaptureDeliveryError implements Exception {
  DVCaptureDeliveryError({
    required this.consumer,
    required this.sink,
    required this.checkpoint,
    required this.cause,
  });

  final String code = 'DV-CDC-001';
  final String consumer;
  final String sink;

  /// Where the consumer still stands.
  final int checkpoint;
  final Object cause;

  @override
  String toString() => '$code: $sink refused a batch for $consumer; it stays '
      'at #$checkpoint and the batch is delivered again: $cause';
}

/// `DV-CDC-002`: a consumer is behind the retention window and must backfill.
class DVCaptureBehindRetentionError implements Exception {
  DVCaptureBehindRetentionError({
    required this.consumer,
    required this.checkpoint,
    required this.prunedThrough,
  });

  final String code = 'DV-CDC-002';
  final String consumer;
  final int checkpoint;
  final int prunedThrough;

  @override
  String toString() => '$code: $consumer stands at #$checkpoint and the log '
      'has been pruned through #$prunedThrough. Replay cannot close that gap; '
      'run a backfill.';
}

/// `DV-CDC-005`: a destination's schema could not be evolved to match the
/// source. Delivery stops before the change rather than sending rows the
/// destination has no columns for.
class DVCaptureSchemaError implements Exception {
  DVCaptureSchemaError({
    required this.consumer,
    required this.sink,
    required this.change,
    required this.cause,
  });

  final String code = 'DV-CDC-005';
  final String consumer;
  final String sink;
  final DVCaptureSchemaChange change;
  final Object cause;

  @override
  String toString() => '$code: $sink could not apply $change for $consumer; '
      'delivery is stopped before it: $cause';
}

/// The outcome of one delivery run.
class DVCaptureDelivery {
  DVCaptureDelivery({
    required this.delivered,
    required this.checkpoint,
    List<String> codes = const <String>[],
    this.read = 0,
  }) : codes = List<String>.unmodifiable(codes);

  /// Changes handed to the destination.
  final int delivered;

  /// Where the consumer stands afterwards.
  final int checkpoint;
  final List<String> codes;

  /// Log entries read, delivered or not.
  final int read;
}

/// How far a consumer is behind what has been captured.
class DVCaptureLag {
  DVCaptureLag({
    required this.changes,
    required this.age,
    List<String> codes = const <String>[],
  }) : codes = List<String>.unmodifiable(codes);

  /// Captured changes not yet delivered.
  final int changes;

  /// How long ago the oldest undelivered change happened: how stale the
  /// destination is. Zero when caught up.
  final Duration age;
  final List<String> codes;
}

/// Where a backfill stands.
class DVCaptureBackfillProgress {
  const DVCaptureBackfillProgress({
    required this.model,
    required this.throughSequence,
    required this.rows,
    required this.done,
  });

  final String model;

  /// The log position the copy is as of; the stream resumes after it.
  final int throughSequence;

  /// Rows copied so far, across every run.
  final int rows;
  final bool done;
}

/// The job that delivers a consumer's pending changes.
class DVCaptureDeliveryJob {
  const DVCaptureDeliveryJob(this.consumer);
  final String consumer;
}

/// The job that copies one chunk of a model's rows to a consumer, and queues
/// the next until the copy is done.
class DVCaptureBackfillJob {
  const DVCaptureBackfillJob({
    required this.consumer,
    required this.model,
    this.chunkSize = 500,
    this.tenantColumn,
    this.queue = 'default',
  });

  final String consumer;
  final String model;
  final int chunkSize;
  final String? tenantColumn;
  final String queue;
}

final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

String _checkIdentifier(String name) {
  if (!_identifier.hasMatch(name)) {
    throw ArgumentError.value(name, 'name', 'not a plain SQL identifier');
  }
  return name;
}

/// The capture log for one database.
class DVCapture {
  DVCapture({
    required this.database,
    required this.retention,
    DateTime Function()? clock,
    this.lease = const Duration(seconds: 30),
    this.strandedAfter = const Duration(minutes: 5),
  }) : _clock = clock ?? DateTime.now {
    if (retention <= Duration.zero) {
      throw ArgumentError.value(
          retention, 'retention', 'must be a positive, declared bound');
    }
  }

  static const String logTable = 'dv_capture_log';
  static const String stateTable = 'dv_capture_state';
  static const String schemaTable = 'dv_capture_schemas';
  static const String checkpointTable = 'dv_capture_checkpoints';
  static const String backfillTable = 'dv_capture_backfills';

  static const String _stateId = 'log';

  final DVDatabaseAdapter database;

  /// How long a published change is kept. Bounded and declared: a consumer
  /// further behind than this is told to backfill (`DV-CDC-002`).
  final Duration retention;

  /// How long a publisher may hold a range of sequences before another
  /// process treats it as dead and moves past it.
  final Duration lease;

  /// How old a staged change must be before [publishStranded] treats the
  /// transaction that staged it as gone.
  final Duration strandedAfter;

  final DateTime Function() _clock;

  final Map<String, DVRecordTable> _tables = <String, DVRecordTable>{};
  final Map<String, DVCaptureConsumer> _consumers =
      <String, DVCaptureConsumer>{};

  /// Changes staged by transactions still open in this process, in write
  /// order, by transaction id.
  final Map<String, List<String>> _staged = <String, List<String>>{};

  Future<void> _publishing = Future<void>.value();

  Future<void> ensureSchema() async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $logTable (change_id, change_seq, model, '
      'record_key, operation, record_version, tenant, transaction_id, '
      'occurred_at, write_order, published_at, row_values, redacted, erased, '
      'purged)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $stateTable (id, allocated_through, '
      'published_through, pruned_through, lease_until)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $schemaTable (model, columns)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $checkpointTable (consumer, change_seq, '
      'updated_at)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $backfillTable (consumer, model, '
      'through_seq, after_key, rows_done, done)',
    );
    final List<Map<String, Object?>> state = await database.query(
      'SELECT id FROM $stateTable WHERE id = ?',
      <Object?>[_stateId],
    );
    if (state.isEmpty) {
      await database.execute(
        'INSERT INTO $stateTable (id, allocated_through, published_through, '
        'pruned_through, lease_until) VALUES (?, ?, ?, ?, ?)',
        <Object?>[_stateId, 0, 0, 0, _stamp(DateTime.utc(1970))],
      );
    }
  }

  /// Makes [table] known to backfill jobs. [DVRecordTable] calls it.
  void track(DVRecordTable table) => _tables[table.table] = table;

  /// A consumer: one destination's position in the log.
  ///
  /// [tenant] delivers only that tenant's changes, filtered here at the
  /// source; a change with no tenant never reaches a tenant destination.
  DVCaptureConsumer consumer(
    String name, {
    required DVCaptureSink sink,
    String? tenant,
    Set<String>? models,
    int batchSize = 500,
    Duration? lagThreshold,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (batchSize < 1) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be at least 1');
    }
    final DVCaptureConsumer created = DVCaptureConsumer._(
      this,
      name,
      sink: sink,
      tenant: tenant,
      models: models == null ? null : Set<String>.unmodifiable(models),
      batchSize: batchSize,
      lagThreshold: lagThreshold,
    );
    _consumers[name] = created;
    return created;
  }

  // --- capture --------------------------------------------------------------

  /// Captures one write. Called by [DVRecordTable] after the row is written.
  ///
  /// Inside `DV.transaction` the change is staged and published after commit;
  /// a rollback removes it unpublished, so no consumer can read it while the
  /// transaction is open nor after it has been undone. Outside a transaction
  /// it is published at once. Throws only when the change could not be
  /// written at all, so the caller can undo the write.
  Future<String> record({
    required DVRecordTable table,
    required DVCaptureOp operation,
    required Object key,
    required int version,
    required Map<String, Object?> values,
    String? tenant,
    bool erased = false,
  }) async {
    track(table);
    final DVContext? transaction = DVTransactionRunner.activeContext;
    final String id = _newId('chg');
    final bool carriesRow =
        operation != DVCaptureOp.delete && operation != DVCaptureOp.snapshot;
    // Sensitive fields are left out here, before the log is written: a log
    // that holds a value and trusts every consumer to drop it has already
    // leaked it to its own storage and its backups.
    final Map<String, Object?>? row = carriesRow
        ? <String, Object?>{
            for (final String column in table.columns)
              if (!table.sensitive.contains(column))
                column: _jsonSafe(values[column]),
          }
        : null;
    final String? resolvedTenant = tenant ??
        (DVTenants.hasScope ? const DVTenants().currentTenant : null);
    final DateTime now = _clock();
    await database.execute(
      'INSERT INTO $logTable (change_id, change_seq, model, record_key, '
      'operation, record_version, tenant, transaction_id, occurred_at, '
      'write_order, published_at, row_values, redacted, erased, purged) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        id,
        null,
        table.table,
        jsonEncode(_jsonSafe(key)),
        operation.name,
        version,
        resolvedTenant,
        transaction?.transactionId,
        _stamp(now),
        _writeOrder(now),
        null,
        row == null ? null : jsonEncode(row),
        jsonEncode(table.sensitive.toList()..sort()),
        erased ? 1 : 0,
        0,
      ],
    );

    if (transaction == null) {
      await _publishQuietly(<String>[id]);
      return id;
    }

    final String transactionId = transaction.transactionId;
    final List<String>? staged = _staged[transactionId];
    if (staged == null) {
      _staged[transactionId] = <String>[id];
      transaction.afterCommit(() async {
        final List<String> ids = _staged.remove(transactionId) ?? <String>[];
        await _publishQuietly(ids);
      });
    } else {
      staged.add(id);
    }
    transaction.compensate(() async {
      final List<String>? open = _staged[transactionId];
      open?.remove(id);
      if (open != null && open.isEmpty) _staged.remove(transactionId);
      await database.execute(
        'DELETE FROM $logTable WHERE change_id = ? AND change_seq IS NULL',
        <Object?>[id],
      );
    });
    return id;
  }

  /// Publishes changes a crash left staged: written, never given a sequence.
  ///
  /// The rows they describe are in the database -- a compensation-based
  /// transaction that dies before compensating leaves its writes in place --
  /// so the honest thing is to publish what the store holds. Changes of a
  /// transaction still open in this process are left alone.
  Future<int> publishStranded() async {
    final String cutoff = _stamp(_clock().subtract(strandedAfter));
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT change_id, transaction_id, write_order FROM $logTable '
      'WHERE change_seq IS NULL AND occurred_at < ? ORDER BY write_order ASC',
      <Object?>[cutoff],
    );
    final List<String> ids = <String>[
      for (final Map<String, Object?> row in rows)
        if (!_staged.containsKey(row['transaction_id'])) '${row['change_id']}',
    ];
    if (ids.isEmpty) return 0;
    return _publish(ids);
  }

  Future<void> _publishQuietly(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _publish(ids);
    } on Object catch (error) {
      // The write already happened and cannot be refused now. The change
      // stays staged, where publishStranded finds it.
      DVObservability.log(
        'Captured changes could not be published and stay staged until '
        'DVCapture.publishStranded runs: $error',
        level: DVLogLevel.warn,
        context: <String, Object?>{'changes': ids.length},
      );
    }
  }

  /// Gives staged changes their sequences, in the order given, with any
  /// schema change a destination needs placed before the first row that
  /// needs it.
  Future<int> _publish(List<String> ids) {
    final Future<int> run = _publishing.then((_) => _publishSerially(ids));
    _publishing = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<int> _publishSerially(List<String> ids) async {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final String id in ids) {
      final List<Map<String, Object?>> found = await database.query(
        'SELECT * FROM $logTable WHERE change_id = ? AND change_seq IS NULL',
        <Object?>[id],
      );
      rows.addAll(found);
    }
    if (rows.isEmpty) return 0;

    final Map<String, List<String>?> schemas = <String, List<String>?>{};
    final Set<String> changedModels = <String>{};
    final List<Object> plan = <Object>[];
    for (final Map<String, Object?> row in rows) {
      final String model = '${row['model']}';
      final Object? raw = row['row_values'];
      if (raw is String && row['purged'] != 1) {
        final List<String> columns =
            (jsonDecode(raw) as Map<String, Object?>).keys.toList();
        if (!schemas.containsKey(model)) {
          schemas[model] = await _loadSchema(model);
        }
        final List<String> known = schemas[model] ?? const <String>[];
        final List<String> added = <String>[
          for (final String c in columns)
            if (!known.contains(c)) c,
        ];
        final List<String> removed = <String>[
          for (final String c in known)
            if (!columns.contains(c)) c,
        ];
        if (added.isNotEmpty) {
          plan.add((model, DVCaptureSchemaPhase.expand, added));
        }
        if (removed.isNotEmpty) {
          plan.add((model, DVCaptureSchemaPhase.contract, removed));
        }
        if (added.isNotEmpty || removed.isNotEmpty) {
          schemas[model] = columns;
          changedModels.add(model);
        }
      }
      plan.add(row);
    }

    final int first = await _allocate(plan.length);
    final String published = _stamp(_clock());
    for (int i = 0; i < plan.length; i++) {
      final Object entry = plan[i];
      final int sequence = first + i;
      if (entry is (String, DVCaptureSchemaPhase, List<String>)) {
        await database.execute(
          'INSERT INTO $logTable (change_id, change_seq, model, record_key, '
          'operation, record_version, tenant, transaction_id, occurred_at, '
          'write_order, published_at, row_values, redacted, erased, purged) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            _newId('sch'),
            sequence,
            entry.$1,
            null,
            entry.$2.name,
            0,
            null,
            null,
            published,
            _writeOrder(_clock()),
            published,
            jsonEncode(<String, Object?>{'columns': entry.$3}),
            '[]',
            0,
            0,
          ],
        );
      } else {
        await database.execute(
          'UPDATE $logTable SET change_seq = ?, published_at = ? '
          'WHERE change_id = ? AND change_seq IS NULL',
          <Object?>[
            sequence,
            published,
            (entry as Map<String, Object?>)['change_id'],
          ],
        );
      }
    }
    for (final String model in changedModels) {
      await _saveSchema(model, schemas[model]!);
    }
    await database.execute(
      'UPDATE $stateTable SET published_through = ? WHERE id = ? '
      'AND allocated_through = ? AND published_through = ?',
      <Object?>[first + plan.length - 1, _stateId, first + plan.length - 1,
          first - 1],
    );
    return rows.length;
  }

  /// Takes [count] consecutive sequences.
  ///
  /// A range is only handed out while nothing else is being published, so a
  /// reader bounded by `published_through` can never see a higher sequence
  /// before a lower one exists. A publisher that died holding a range is
  /// moved past once its lease runs out: the numbers it never used are holes,
  /// and the changes it did not publish stay staged for [publishStranded].
  Future<int> _allocate(int count) async {
    for (int attempt = 0;; attempt++) {
      final _State state = await _state();
      if (state.allocated == state.published) {
        final int taken = await database.execute(
          'UPDATE $stateTable SET allocated_through = ?, lease_until = ? '
          'WHERE id = ? AND allocated_through = ? AND published_through = ?',
          <Object?>[
            state.allocated + count,
            _stamp(_clock().add(lease)),
            _stateId,
            state.allocated,
            state.published,
          ],
        );
        if (taken == 1) return state.allocated + 1;
      } else if (state.leaseUntil.isBefore(_clock())) {
        await database.execute(
          'UPDATE $stateTable SET published_through = ? WHERE id = ? '
          'AND allocated_through = ? AND published_through = ?',
          <Object?>[state.allocated, _stateId, state.allocated, state.published],
        );
        continue;
      }
      if (attempt >= 400) {
        throw StateError(
          'The capture log stayed locked by another publisher for longer than '
          'its lease; nothing was published.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<_State> _state() async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT * FROM $stateTable WHERE id = ?',
      <Object?>[_stateId],
    );
    if (rows.isEmpty) {
      throw StateError('The capture log has no state; run ensureSchema first.');
    }
    final Map<String, Object?> row = rows.first;
    return _State(
      allocated: _asInt(row['allocated_through']),
      published: _asInt(row['published_through']),
      pruned: _asInt(row['pruned_through']),
      leaseUntil: DateTime.parse('${row['lease_until']}'),
    );
  }

  Future<List<String>?> _loadSchema(String model) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT columns FROM $schemaTable WHERE model = ?',
      <Object?>[model],
    );
    if (rows.isEmpty) return null;
    return (jsonDecode('${rows.first['columns']}') as List<Object?>)
        .map((Object? c) => '$c')
        .toList();
  }

  Future<void> _saveSchema(String model, List<String> columns) async {
    final int updated = await database.execute(
      'UPDATE $schemaTable SET columns = ? WHERE model = ?',
      <Object?>[jsonEncode(columns), model],
    );
    if (updated == 0) {
      await database.execute(
        'INSERT INTO $schemaTable (model, columns) VALUES (?, ?)',
        <Object?>[model, jsonEncode(columns)],
      );
    }
  }

  // --- reading --------------------------------------------------------------

  /// The newest published sequence.
  Future<int> head() async => (await _state()).published;

  /// Published record changes after [after], oldest first. Schema changes are
  /// not included; changes an erasure purged are.
  Future<List<DVCapturedChange>> changes({int after = 0, int? limit}) async {
    final _State state = await _state();
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT * FROM $logTable WHERE change_seq IS NOT NULL '
      'AND change_seq > ? AND change_seq <= ? AND record_key IS NOT NULL '
      'ORDER BY change_seq ASC${limit == null ? '' : ' LIMIT ${math.max(0, limit)}'}',
      <Object?>[after, state.published],
    );
    return rows.map(_changeFromRow).toList(growable: false);
  }

  // --- retention ------------------------------------------------------------

  /// Removes published changes older than [retention], returning how many.
  ///
  /// The pruned position is recorded before anything is deleted, so a
  /// consumer reading while this runs is refused rather than silently reading
  /// past the rows that vanished under it.
  Future<int> prune() async {
    final String cutoff = _stamp(_clock().subtract(retention));
    final List<Map<String, Object?>> newest = await database.query(
      'SELECT change_seq FROM $logTable WHERE change_seq IS NOT NULL '
      'AND published_at < ? ORDER BY change_seq DESC LIMIT 1',
      <Object?>[cutoff],
    );
    if (newest.isEmpty) return 0;
    final int through = _asInt(newest.first['change_seq']);
    await database.execute(
      'UPDATE $stateTable SET pruned_through = ? WHERE id = ? '
      'AND pruned_through < ?',
      <Object?>[through, _stateId, through],
    );
    return database.execute(
      'DELETE FROM $logTable WHERE change_seq IS NOT NULL AND change_seq <= ?',
      <Object?>[through],
    );
  }

  // --- erasure --------------------------------------------------------------

  /// Removes every value the log holds for one record, and captures what an
  /// erasure left of it: a delete when it is gone, or its anonymized values
  /// when a retention kept it. Returns that change, published.
  Future<DVCapturedChange> eraseRecord(DVRecordTable table, Object key) async {
    await database.execute(
      'UPDATE $logTable SET row_values = ?, purged = ? '
      'WHERE model = ? AND record_key = ?',
      <Object?>[null, 1, table.table, jsonEncode(_jsonSafe(key))],
    );
    final DVRecord? current = await table.read(key, withDeleted: true);
    final bool live = current != null && current.deletedAt == null;
    final String id = await record(
      table: table,
      operation: live ? DVCaptureOp.update : DVCaptureOp.delete,
      key: key,
      version: current?.version ?? 0,
      values: live ? current.values : const <String, Object?>{},
      erased: true,
    );
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT * FROM $logTable WHERE change_id = ? AND change_seq IS NOT NULL',
      <Object?>[id],
    );
    if (rows.isEmpty) {
      throw StateError(
        'The erasure of ${table.table}[$key] was captured but not published; '
        'destinations were not reached.',
      );
    }
    return _changeFromRow(rows.first);
  }

  // --- jobs -----------------------------------------------------------------

  /// Registers delivery and backfill on the durable job layer. A refused
  /// batch throws, so the queue retries it with its backoff.
  void registerJobs(DVQueues queues) {
    queues
      ..register<DVCaptureDeliveryJob>((DVCaptureDeliveryJob job) async {
        await _consumer(job.consumer).deliverAll();
      })
      ..register<DVCaptureBackfillJob>((DVCaptureBackfillJob job) async {
        final DVRecordTable? table = _tables[job.model];
        if (table == null) {
          throw StateError('${job.model} is not a captured table here.');
        }
        final DVCaptureBackfillProgress progress =
            await _consumer(job.consumer).backfill(
          table,
          chunkSize: job.chunkSize,
          maxChunks: 1,
          tenantColumn: job.tenantColumn,
        );
        // One chunk per run is the rate limit: the queue's own pacing sits
        // between chunks, and the work never holds a worker for the whole
        // table.
        if (!progress.done) {
          await queues.dispatch<DVCaptureBackfillJob>(job, queue: job.queue);
        }
      });
  }

  Future<DVJobEnvelope<DVCaptureDeliveryJob>> dispatchDelivery(
    String consumer, {
    DVQueues queues = const DVQueues(),
    String queue = 'default',
  }) =>
      queues.dispatch<DVCaptureDeliveryJob>(
        DVCaptureDeliveryJob(consumer),
        queue: queue,
      );

  Future<DVJobEnvelope<DVCaptureBackfillJob>> dispatchBackfill(
    DVCaptureBackfillJob job, {
    DVQueues queues = const DVQueues(),
  }) =>
      queues.dispatch<DVCaptureBackfillJob>(job, queue: job.queue);

  DVCaptureConsumer _consumer(String name) {
    final DVCaptureConsumer? found = _consumers[name];
    if (found == null) {
      throw StateError('No capture consumer named $name is registered.');
    }
    return found;
  }

  DVCapturedChange _changeFromRow(Map<String, Object?> row) {
    final Object? raw = row['row_values'];
    final Object? redacted = row['redacted'];
    return DVCapturedChange(
      id: '${row['change_id']}',
      sequence: _asInt(row['change_seq']),
      model: '${row['model']}',
      key: jsonDecode('${row['record_key']}'),
      operation: DVCaptureOp.values.byName('${row['operation']}'),
      version: _asInt(row['record_version']),
      occurredAt: DateTime.parse('${row['occurred_at']}'),
      values: raw is String && row['purged'] != 1
          ? (jsonDecode(raw) as Map<String, Object?>)
          : const <String, Object?>{},
      redacted: redacted is String
          ? <String>{
              for (final Object? f in jsonDecode(redacted) as List<Object?>)
                '$f',
            }
          : const <String>{},
      tenant: row['tenant'] as String?,
      transactionId: row['transaction_id'] as String?,
      erased: row['erased'] == 1,
    );
  }

  static int _orderCounter = 0;

  static int _writeOrder(DateTime now) {
    _orderCounter = (_orderCounter + 1) % 1000;
    return now.microsecondsSinceEpoch * 1000 + _orderCounter;
  }
}

class _State {
  const _State({
    required this.allocated,
    required this.published,
    required this.pruned,
    required this.leaseUntil,
  });

  final int allocated;
  final int published;
  final int pruned;
  final DateTime leaseUntil;
}

/// One destination's position in the log, and the delivery that moves it.
class DVCaptureConsumer {
  DVCaptureConsumer._(
    this.capture,
    this.name, {
    required this.sink,
    required this.tenant,
    required this.models,
    required this.batchSize,
    required this.lagThreshold,
  });

  final DVCapture capture;
  final String name;
  final DVCaptureSink sink;
  final String? tenant;
  final Set<String>? models;
  final int batchSize;

  /// Past this, [lag] reports `DV-CDC-003`.
  final Duration? lagThreshold;

  bool _toldAtLeastOnce = false;
  Future<void> _running = Future<void>.value();

  DVDatabaseAdapter get _db => capture.database;

  /// The last sequence this consumer has delivered, or 0.
  Future<int> checkpoint() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'SELECT change_seq FROM ${DVCapture.checkpointTable} WHERE consumer = ?',
      <Object?>[name],
    );
    return rows.isEmpty ? 0 : _asInt(rows.first['change_seq']);
  }

  Future<void> _saveCheckpoint(int sequence) async {
    final String now = _stamp(capture._clock());
    final int updated = await _db.execute(
      'UPDATE ${DVCapture.checkpointTable} SET change_seq = ?, updated_at = ? '
      'WHERE consumer = ?',
      <Object?>[sequence, now, name],
    );
    if (updated == 0) {
      await _db.execute(
        'INSERT INTO ${DVCapture.checkpointTable} (consumer, change_seq, '
        'updated_at) VALUES (?, ?, ?)',
        <Object?>[name, sequence, now],
      );
    }
  }

  Future<T> _serially<T>(Future<T> Function() body) {
    final Future<T> run = _running.then((_) => body());
    _running = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  void _checkRetention(int checkpoint, _State state) {
    if (checkpoint < state.pruned) {
      final DVCaptureBehindRetentionError error = DVCaptureBehindRetentionError(
        consumer: name,
        checkpoint: checkpoint,
        prunedThrough: state.pruned,
      );
      DVObservability.log(error.toString(),
          level: DVLogLevel.error, code: error.code);
      throw error;
    }
  }

  bool _wants(String model) => models == null || models!.contains(model);

  /// Delivers up to [batchSize] log entries after the checkpoint.
  ///
  /// The checkpoint moves only after the destination has accepted what came
  /// before it, so a crash in between redelivers rather than skips.
  Future<DVCaptureDelivery> deliverOnce() => _serially(_deliverOnce);

  Future<DVCaptureDelivery> _deliverOnce() async {
    final List<String> codes = <String>[];
    if (!sink.deduplicates && !_toldAtLeastOnce) {
      _toldAtLeastOnce = true;
      codes.add('DV-CDC-004');
      DVObservability.log(
        '${sink.name} cannot deduplicate; delivery to $name is at-least-once '
        'and a redelivered batch lands twice.',
        level: DVLogLevel.info,
        code: 'DV-CDC-004',
      );
    }

    final int start = await checkpoint();
    final _State state = await capture._state();
    _checkRetention(start, state);
    final List<Map<String, Object?>> rows = await _db.query(
      'SELECT * FROM ${DVCapture.logTable} WHERE change_seq IS NOT NULL '
      'AND change_seq > ? AND change_seq <= ? ORDER BY change_seq ASC '
      'LIMIT $batchSize',
      <Object?>[start, state.published],
    );
    // Pruning may have run between the check and the read; the rows it
    // removed would otherwise be skipped without a word.
    _checkRetention(start, await capture._state());

    int saved = start;
    int last = start;
    int delivered = 0;
    final List<DVCapturedChange> batch = <DVCapturedChange>[];

    Future<void> flush() async {
      if (batch.isNotEmpty) {
        try {
          await sink.write(DVCaptureBatch(
            consumer: name,
            changes: List<DVCapturedChange>.of(batch),
            atLeastOnce: !sink.deduplicates,
          ));
        } on Object catch (cause) {
          final DVCaptureDeliveryError error = DVCaptureDeliveryError(
            consumer: name,
            sink: sink.name,
            checkpoint: saved,
            cause: cause,
          );
          DVObservability.log(error.toString(),
              level: DVLogLevel.warn, code: error.code);
          throw error;
        }
        delivered += batch.length;
        batch.clear();
      }
      if (last > saved) {
        await _saveCheckpoint(last);
        saved = last;
      }
    }

    for (final Map<String, Object?> row in rows) {
      final int sequence = _asInt(row['change_seq']);
      final String model = '${row['model']}';
      final String operation = '${row['operation']}';
      if (operation == DVCaptureSchemaPhase.expand.name ||
          operation == DVCaptureSchemaPhase.contract.name) {
        if (_wants(model)) {
          await flush();
          final DVCaptureSchemaChange change = DVCaptureSchemaChange(
            sequence: sequence,
            model: model,
            phase: DVCaptureSchemaPhase.values.byName(operation),
            columns: <String>[
              for (final Object? c in (jsonDecode('${row['row_values']}')
                  as Map<String, Object?>)['columns']! as List<Object?>)
                '$c',
            ],
          );
          try {
            await sink.evolve(change);
          } on Object catch (cause) {
            final DVCaptureSchemaError error = DVCaptureSchemaError(
              consumer: name,
              sink: sink.name,
              change: change,
              cause: cause,
            );
            DVObservability.log(error.toString(),
                level: DVLogLevel.error, code: error.code);
            throw error;
          }
        }
        last = sequence;
        continue;
      }
      if (row['purged'] != 1 &&
          _wants(model) &&
          (tenant == null || row['tenant'] == tenant)) {
        batch.add(capture._changeFromRow(row));
      }
      last = sequence;
    }
    await flush();
    return DVCaptureDelivery(
      delivered: delivered,
      checkpoint: saved,
      codes: codes,
      read: rows.length,
    );
  }

  /// Delivers until the consumer has reached the head of the log.
  Future<DVCaptureDelivery> deliverAll() async {
    final List<String> codes = <String>[];
    int delivered = 0;
    int read = 0;
    while (true) {
      final DVCaptureDelivery run = await deliverOnce();
      codes.addAll(run.codes);
      delivered += run.delivered;
      read += run.read;
      if (run.read < batchSize) {
        return DVCaptureDelivery(
          delivered: delivered,
          checkpoint: run.checkpoint,
          codes: codes,
          read: read,
        );
      }
    }
  }

  /// How far behind this consumer is, recorded as the gauges
  /// `dv_capture_lag_seconds` and `dv_capture_lag_changes`.
  ///
  /// Measured rather than assumed: the failure here is not an error but a
  /// destination quietly hours old while everyone reads it as current.
  Future<DVCaptureLag> lag() async {
    final int at = await checkpoint();
    final int head = await capture.head();
    final List<Map<String, Object?>> pending = await _db.query(
      'SELECT occurred_at FROM ${DVCapture.logTable} WHERE change_seq IS NOT NULL '
      'AND change_seq > ? AND change_seq <= ? AND record_key IS NOT NULL '
      'ORDER BY change_seq ASC',
      <Object?>[at, head],
    );
    final Duration age = pending.isEmpty
        ? Duration.zero
        : capture._clock().difference(
            DateTime.parse('${pending.first['occurred_at']}'));
    final Duration measured = age.isNegative ? Duration.zero : age;
    final Map<String, String> labels = <String, String>{'consumer': name};
    DVObservability.metrics
        .gauge('dv_capture_lag_seconds', labels,
            'Age of the oldest captured change not yet delivered')
        .set(measured.inSeconds.toDouble());
    DVObservability.metrics
        .gauge('dv_capture_lag_changes', labels,
            'Captured changes not yet delivered')
        .set(pending.length.toDouble());
    final List<String> codes = <String>[];
    final Duration? threshold = lagThreshold;
    if (threshold != null && measured > threshold) {
      codes.add('DV-CDC-003');
      DVObservability.log(
        '$name is ${measured.inMinutes} minutes behind the capture log, past '
        'its ${threshold.inMinutes}-minute threshold.',
        level: DVLogLevel.warn,
        code: 'DV-CDC-003',
        context: <String, Object?>{'changes': pending.length},
      );
    }
    return DVCaptureLag(changes: pending.length, age: measured, codes: codes);
  }

  /// Copies [table]'s live rows to the destination, [chunkSize] at a time,
  /// resuming where an earlier run stopped.
  ///
  /// The copy is as of the log's head when it began: the consumer's
  /// checkpoint moves there, so the stream resumes after it and every change
  /// the copy might have missed still arrives. Rows land as
  /// [DVCaptureOp.snapshot] carrying their record version, so a destination
  /// keeps whichever of the copy and the stream is newer. A tenant consumer
  /// needs [tenantColumn]: a row with no tenant on it cannot be shown to
  /// belong to that tenant.
  Future<DVCaptureBackfillProgress> backfill(
    DVRecordTable table, {
    int chunkSize = 500,
    int? maxChunks,
    String? tenantColumn,
  }) =>
      _serially(() => _backfill(table, chunkSize, maxChunks, tenantColumn));

  Future<DVCaptureBackfillProgress> _backfill(
    DVRecordTable table,
    int chunkSize,
    int? maxChunks,
    String? tenantColumn,
  ) async {
    if (chunkSize < 1) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be at least 1');
    }
    if (tenant != null && tenantColumn == null) {
      throw ArgumentError.value(
        null,
        'tenantColumn',
        '$name serves tenant $tenant, and ${table.table} rows carry no '
            'tenant without one',
      );
    }
    if (tenantColumn != null && !table.columns.contains(tenantColumn)) {
      throw ArgumentError.value(
          tenantColumn, 'tenantColumn', 'is not a column of ${table.table}');
    }
    if (!_wants(table.table)) {
      throw ArgumentError.value(
          table.table, 'table', 'is not one of the models $name delivers');
    }

    final String model = table.table;
    List<Map<String, Object?>> state = await _db.query(
      'SELECT * FROM ${DVCapture.backfillTable} WHERE consumer = ? AND model = ?',
      <Object?>[name, model],
    );
    if (state.isEmpty || state.first['done'] == 1) {
      final int through = await capture.head();
      if (state.isEmpty) {
        await _db.execute(
          'INSERT INTO ${DVCapture.backfillTable} (consumer, model, '
          'through_seq, after_key, rows_done, done) VALUES (?, ?, ?, ?, ?, ?)',
          <Object?>[name, model, through, null, 0, 0],
        );
      } else {
        await _db.execute(
          'UPDATE ${DVCapture.backfillTable} SET through_seq = ?, '
          'after_key = ?, rows_done = ?, done = ? WHERE consumer = ? AND model = ?',
          <Object?>[through, null, 0, 0, name, model],
        );
      }
      if (await checkpoint() < through) await _saveCheckpoint(through);
      final DVCaptureSchemaChange shape = DVCaptureSchemaChange(
        sequence: through,
        model: model,
        phase: DVCaptureSchemaPhase.expand,
        columns: <String>[
          for (final String c in table.columns)
            if (!table.sensitive.contains(c)) c,
        ],
      );
      try {
        await sink.evolve(shape);
      } on Object catch (cause) {
        final DVCaptureSchemaError error = DVCaptureSchemaError(
            consumer: name, sink: sink.name, change: shape, cause: cause);
        DVObservability.log(error.toString(),
            level: DVLogLevel.error, code: error.code);
        throw error;
      }
      state = await _db.query(
        'SELECT * FROM ${DVCapture.backfillTable} WHERE consumer = ? AND model = ?',
        <Object?>[name, model],
      );
    }

    final int through = _asInt(state.first['through_seq']);
    Object? after = state.first['after_key'] == null
        ? null
        : jsonDecode('${state.first['after_key']}');
    int rowsDone = _asInt(state.first['rows_done']);
    final DVDatabaseAdapter source = table.database;
    int chunks = 0;

    while (true) {
      final List<Map<String, Object?>> rows = after == null
          ? await source.query(
              'SELECT * FROM $model ORDER BY ${table.key} ASC LIMIT $chunkSize')
          : await source.query(
              'SELECT * FROM $model WHERE ${table.key} > ? '
              'ORDER BY ${table.key} ASC LIMIT $chunkSize',
              <Object?>[after]);
      final List<DVCapturedChange> changes = <DVCapturedChange>[];
      for (final Map<String, Object?> row in rows) {
        if (row[DVRecordTable.deletedColumn] != null) continue;
        final String? rowTenant =
            tenantColumn == null ? null : row[tenantColumn] as String?;
        if (tenant != null && rowTenant != tenant) continue;
        changes.add(DVCapturedChange(
          id: 'snap-$name-$through-${jsonEncode(_jsonSafe(row[table.key]))}',
          sequence: through,
          model: model,
          key: row[table.key],
          operation: DVCaptureOp.snapshot,
          version: _asInt(row[DVRecordTable.versionColumn]),
          occurredAt: capture._clock(),
          values: <String, Object?>{
            for (final String c in table.columns)
              if (!table.sensitive.contains(c)) c: _jsonSafe(row[c]),
          },
          redacted: table.sensitive,
          tenant: rowTenant,
        ));
      }
      if (changes.isNotEmpty) {
        try {
          await sink.write(DVCaptureBatch(
            consumer: name,
            changes: changes,
            atLeastOnce: !sink.deduplicates,
          ));
        } on Object catch (cause) {
          final DVCaptureDeliveryError error = DVCaptureDeliveryError(
              consumer: name, sink: sink.name, checkpoint: through, cause: cause);
          DVObservability.log(error.toString(),
              level: DVLogLevel.warn, code: error.code);
          throw error;
        }
      }
      rowsDone += changes.length;
      final bool done = rows.length < chunkSize;
      if (rows.isNotEmpty) after = rows.last[table.key];
      if (done) {
        await sink.backfillComplete(model, through, tenant: tenant);
      }
      await _db.execute(
        'UPDATE ${DVCapture.backfillTable} SET after_key = ?, rows_done = ?, '
        'done = ? WHERE consumer = ? AND model = ?',
        <Object?>[
          after == null ? null : jsonEncode(_jsonSafe(after)),
          rowsDone,
          done ? 1 : 0,
          name,
          model,
        ],
      );
      chunks++;
      if (done || (maxChunks != null && chunks >= maxChunks)) {
        return DVCaptureBackfillProgress(
          model: model,
          throughSequence: through,
          rows: rowsDone,
          done: done,
        );
      }
    }
  }
}

/// The reference warehouse sink: one table per model in any SQL database
/// that can add and drop a column, holding each record's newest state.
///
/// What it demonstrates is the contract a real warehouse adapter has to keep,
/// not a storage engine: changes applied by record version so out-of-order
/// commits leave the newest row, deletes that remove rows, a key reused after
/// a delete treated as a new record, erasures that no in-flight change can
/// undo, and idempotent schema evolution. Rows land as they were written;
/// there is no transformation.
class DVWarehouseSink implements DVCaptureSink {
  DVWarehouseSink({required this.database, this.name = 'warehouse'});

  static const String tombstoneTable = 'dv_warehouse_tombstones';

  static const List<String> _meta = <String>[
    '_dv_key',
    '_dv_version',
    '_dv_seq',
    '_dv_incarnation',
    '_dv_change_id',
    '_dv_tenant',
    '_dv_transaction_id',
    '_dv_occurred_at',
    '_dv_backfilled',
  ];

  final DVDatabaseAdapter database;

  @override
  final String name;

  /// Applying a change twice is a no-op, because it is applied by version.
  @override
  bool get deduplicates => true;

  Future<void> _ensureTables(String model) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $tombstoneTable (model, record_key, '
      'record_version, change_seq, incarnation, erased)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS ${_checkIdentifier(model)} '
      '(${_meta.join(', ')})',
    );
  }

  Future<bool> _hasColumn(String model, String column) async {
    try {
      await database.query('SELECT $column FROM $model LIMIT 1');
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> evolve(DVCaptureSchemaChange change) async {
    await _ensureTables(change.model);
    for (final String column in change.columns) {
      _checkIdentifier(column);
      if (column.startsWith('_dv_')) {
        throw ArgumentError.value(column, 'column', 'is reserved');
      }
      final bool exists = await _hasColumn(change.model, column);
      if (change.phase == DVCaptureSchemaPhase.expand && !exists) {
        await database.execute(
            'ALTER TABLE ${change.model} ADD COLUMN $column');
      } else if (change.phase == DVCaptureSchemaPhase.contract && exists) {
        await database.execute(
            'ALTER TABLE ${change.model} DROP COLUMN $column');
      }
    }
  }

  @override
  Future<void> write(DVCaptureBatch batch) async {
    for (final DVCapturedChange change in batch.changes) {
      await _apply(change, force: false);
    }
  }

  @override
  Future<void> erase(List<DVCapturedChange> changes) async {
    for (final DVCapturedChange change in changes) {
      await _ensureTables(change.model);
      await _apply(change, force: true);
    }
  }

  @override
  Future<void> backfillComplete(
    String model,
    int throughSequence, {
    String? tenant,
  }) async {
    _checkIdentifier(model);
    final String scope = tenant == null ? '' : ' AND _dv_tenant = ?';
    await database.execute(
      'DELETE FROM $model WHERE _dv_seq <= ? AND _dv_backfilled IS NULL$scope',
      <Object?>[throughSequence, if (tenant != null) tenant],
    );
    await database.execute(
      'DELETE FROM $model WHERE _dv_seq <= ? AND _dv_backfilled < ?$scope',
      <Object?>[throughSequence, throughSequence, if (tenant != null) tenant],
    );
  }

  Future<void> _apply(DVCapturedChange x, {required bool force}) async {
    final String model = _checkIdentifier(x.model);
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT _dv_version, _dv_seq, _dv_incarnation FROM $model '
      'WHERE _dv_key = ?',
      <Object?>[x.key],
    );
    final List<Map<String, Object?>> tombs = await database.query(
      'SELECT * FROM $tombstoneTable WHERE model = ? AND record_key = ?',
      <Object?>[model, jsonEncode(_jsonSafe(x.key))],
    );
    final Map<String, Object?>? row = rows.isEmpty ? null : rows.first;
    final Map<String, Object?>? tomb = tombs.isEmpty ? null : tombs.first;

    // Nothing written before an erasure may land after it.
    if (!force &&
        tomb != null &&
        tomb['erased'] == 1 &&
        x.sequence <= _asInt(tomb['change_seq'])) {
      return;
    }

    final int incarnation;
    if (force) {
      incarnation = row != null
          ? _asInt(row['_dv_incarnation'])
          : _asInt(tomb?['incarnation']);
    } else if (row != null) {
      final int version = _asInt(row['_dv_version']);
      final int since = _asInt(row['_dv_incarnation']);
      if (x.operation == DVCaptureOp.snapshot) {
        // The source still holds the record: mark it so the sweep keeps it,
        // and take the copy's values only when they are not older.
        if (x.version >= version) {
          await _upsert(x, exists: true, incarnation: since, backfilled: true);
        } else {
          await database.execute(
            'UPDATE $model SET _dv_backfilled = ? WHERE _dv_key = ?',
            <Object?>[x.sequence, x.key],
          );
        }
        return;
      }
      // A change from before this record's current incarnation -- the key
      // was deleted and used again since -- belongs to a different record.
      if (x.sequence <= since) return;
      if (x.version <= version) return;
      incarnation = since;
    } else if (tomb != null) {
      final int tombSeq = _asInt(tomb['change_seq']);
      if (x.operation == DVCaptureOp.insert) {
        if (x.sequence <= tombSeq) return;
        incarnation = x.sequence;
      } else if (x.operation == DVCaptureOp.snapshot) {
        if (x.sequence <= tombSeq) return;
        incarnation = 0;
      } else {
        if (x.sequence <= _asInt(tomb['incarnation'])) return;
        if (x.version <= _asInt(tomb['record_version'])) return;
        incarnation = _asInt(tomb['incarnation']);
      }
    } else {
      incarnation = x.operation == DVCaptureOp.insert ? x.sequence : 0;
    }

    if (x.operation == DVCaptureOp.delete) {
      await database.execute('DELETE FROM $model WHERE _dv_key = ?',
          <Object?>[x.key]);
      await database.execute(
        'DELETE FROM $tombstoneTable WHERE model = ? AND record_key = ?',
        <Object?>[model, jsonEncode(_jsonSafe(x.key))],
      );
      await database.execute(
        'INSERT INTO $tombstoneTable (model, record_key, record_version, '
        'change_seq, incarnation, erased) VALUES (?, ?, ?, ?, ?, ?)',
        <Object?>[
          model,
          jsonEncode(_jsonSafe(x.key)),
          x.version,
          x.sequence,
          incarnation,
          x.erased || tomb?['erased'] == 1 ? 1 : 0,
        ],
      );
      return;
    }

    if (tomb != null && tomb['erased'] != 1) {
      await database.execute(
        'DELETE FROM $tombstoneTable WHERE model = ? AND record_key = ?',
        <Object?>[model, jsonEncode(_jsonSafe(x.key))],
      );
    }
    if (force && x.erased) {
      await database.execute(
        'DELETE FROM $tombstoneTable WHERE model = ? AND record_key = ?',
        <Object?>[model, jsonEncode(_jsonSafe(x.key))],
      );
      await database.execute(
        'INSERT INTO $tombstoneTable (model, record_key, record_version, '
        'change_seq, incarnation, erased) VALUES (?, ?, ?, ?, ?, ?)',
        <Object?>[
          model,
          jsonEncode(_jsonSafe(x.key)),
          x.version,
          x.sequence,
          incarnation,
          1,
        ],
      );
    }
    await _upsert(x,
        exists: row != null,
        incarnation: incarnation,
        backfilled: x.operation == DVCaptureOp.snapshot);
  }

  Future<void> _upsert(
    DVCapturedChange x, {
    required bool exists,
    required int incarnation,
    required bool backfilled,
  }) async {
    final Map<String, Object?> values = <String, Object?>{
      for (final MapEntry<String, Object?> e in x.values.entries)
        if (!x.redacted.contains(e.key)) _checkIdentifier(e.key): e.value,
      '_dv_version': x.version,
      '_dv_seq': x.sequence,
      '_dv_incarnation': incarnation,
      '_dv_change_id': x.id,
      '_dv_tenant': x.tenant,
      '_dv_transaction_id': x.transactionId,
      '_dv_occurred_at': x.occurredAt.toUtc().toIso8601String(),
      if (backfilled) '_dv_backfilled': x.sequence,
    };
    final List<String> columns = values.keys.toList();
    if (exists) {
      await database.execute(
        'UPDATE ${x.model} SET '
        '${columns.map((String c) => '$c = ?').join(', ')} WHERE _dv_key = ?',
        <Object?>[for (final String c in columns) values[c], x.key],
      );
    } else {
      await database.execute(
        'INSERT INTO ${x.model} (_dv_key, ${columns.join(', ')}) '
        'VALUES (?, ${List<String>.filled(columns.length, '?').join(', ')})',
        <Object?>[x.key, for (final String c in columns) values[c]],
      );
    }
  }
}

/// Erasure for the capture log and the destinations it feeds.
///
/// Given the rows an erasure reached, it removes every value the log holds
/// for them, captures what the erasure left -- a delete, or a retained row's
/// anonymized values -- so a consumer that is behind receives that and never
/// the earlier values, and applies the same changes to each destination
/// directly. A destination that cannot be reached makes the erasure
/// incomplete (`DV-PRIVACY-009`) rather than waiting on delivery that may
/// never run.
class DVCapturePrivacyAdapter implements DVPrivacyRecordAdapter {
  DVCapturePrivacyAdapter({
    required this.capture,
    List<DVCaptureSink> sinks = const <DVCaptureSink>[],
    this.name = 'change-capture',
  }) : sinks = List<DVCaptureSink>.unmodifiable(sinks);

  final DVCapture capture;
  final List<DVCaptureSink> sinks;

  @override
  final String name;

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
    throw StateError(
      '$name erases the records an erasure reached, and was not told which; '
      'DVPrivacy passes them through eraseRecords.',
    );
  }

  @override
  Future<void> eraseRecords(
    DVPrivacySubjectRef subject,
    List<DVErasedRecord> records,
  ) async {
    final List<DVCapturedChange> changes = <DVCapturedChange>[
      for (final DVErasedRecord record in records)
        if (identical(record.table.capture, capture))
          await capture.eraseRecord(record.table, record.key),
    ];
    if (changes.isEmpty) return;
    final List<String> failures = <String>[];
    for (final DVCaptureSink sink in sinks) {
      try {
        await sink.erase(changes);
      } on Object catch (error) {
        failures.add('${sink.name}: $error');
      }
    }
    if (failures.isNotEmpty) {
      throw StateError(
          'destinations not reached: ${failures.join('; ')}');
    }
  }

  /// A destination holds copies of the same rows the database export already
  /// covers, so it contributes nothing further.
  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      const <String, Object?>{};
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

String _stamp(DateTime time) => DateTime.fromMillisecondsSinceEpoch(
      time.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();

final math.Random _random = math.Random();
int _counter = 0;

String _newId(String prefix) {
  _counter = (_counter + 1) & 0xFFFFFF;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_counter.toRadixString(36)}-'
      '${_random.nextInt(0x7FFFFFFF).toRadixString(36)}';
}
