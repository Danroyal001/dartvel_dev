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

import '../../dartvel.dart'
    show DVJobEnvelope, DVJobPayloadCodec, DVJobPayloadCodecs, DVQueues;
import '../database/adapter.dart';
import '../database/records.dart';
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

  /// What a queue shared between processes stores the job under.
  static const String codecName = 'dartvel.capture.delivery';

  static Map<String, Object?> encode(DVCaptureDeliveryJob job) =>
      <String, Object?>{'consumer': job.consumer};

  static DVCaptureDeliveryJob decode(Map<String, Object?> json) =>
      DVCaptureDeliveryJob('${json['consumer']}');
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

  /// What a queue shared between processes stores the job under.
  static const String codecName = 'dartvel.capture.backfill';

  static Map<String, Object?> encode(DVCaptureBackfillJob job) =>
      <String, Object?>{
        'consumer': job.consumer,
        'model': job.model,
        'chunkSize': job.chunkSize,
        'tenantColumn': job.tenantColumn,
        'queue': job.queue,
      };

  static DVCaptureBackfillJob decode(Map<String, Object?> json) =>
      DVCaptureBackfillJob(
        consumer: '${json['consumer']}',
        model: '${json['model']}',
        chunkSize: (json['chunkSize'] as num?)?.toInt() ?? 500,
        tenantColumn: json['tenantColumn'] as String?,
        queue: '${json['queue'] ?? 'default'}',
      );
}

final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

String _checkIdentifier(String name) {
  if (!_identifier.hasMatch(name)) {
    throw ArgumentError.value(name, 'name', 'not a plain SQL identifier');
  }
  return name;
}

/// The fields of the log, each change one record.
const Map<String, DVFieldType> _logFields = <String, DVFieldType>{
  // Sequences and the write order are 64 bits: the log outlives any 32-bit
  // count, and the write order is microseconds times a thousand. Keys, rows
  // and times are JSON or ISO-8601 text; flags are 0 or 1.
  'change_id': DVFieldType.text,
  'change_seq': DVFieldType.integer,
  'model': DVFieldType.text,
  'record_key': DVFieldType.text,
  'operation': DVFieldType.text,
  'record_version': DVFieldType.integer,
  'tenant': DVFieldType.text,
  'transaction_id': DVFieldType.text,
  'occurred_at': DVFieldType.text,
  'write_order': DVFieldType.integer,
  'published_at': DVFieldType.text,
  'row_values': DVFieldType.text,
  'redacted': DVFieldType.text,
  'erased': DVFieldType.integer,
  'purged': DVFieldType.integer,
};

/// The capture log for one database.
///
/// Stored through the record operations every engine implements
/// ([DVRecordAdapter]), never through SQL, so the log lives wherever the
/// application's data does: a SQL table, or a document database's
/// collection.
class DVCapture {
  static DVCapture? _configured;
  /// How long a published change is kept when nothing declared a retention.
  static const Duration defaultRetention = Duration(days: 7);

  /// The log a model declared `@DVModel(capture: true)` writes to, or null
  /// when this process configured none.
  ///
  /// Configured once, the way the database is, because a model that says it
  /// is captured should not also have to be handed the machinery.
  static DVCapture? get configured => _configured;

  /// Records every captured model in this process to [log].
  static void configure(DVCapture log) => _configured = log;

  /// Leaves the process with no log. A captured model then writes normally
  /// and records nothing, rather than failing on the first save: a change
  /// nobody is consuming is not a reason to refuse the write.
  static void unconfigure() => _configured = null;

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

  /// Called after changes are published, with how many. The framework's
  /// delivery runtime uses it to send them on without waiting for its next
  /// tick; a failure in it never reaches the write that published.
  void Function(int published)? onPublished;

  final DateTime Function() _clock;

  final Map<String, DVRecordTable> _tables = <String, DVRecordTable>{};
  final Map<String, DVCaptureConsumer> _consumers =
      <String, DVCaptureConsumer>{};

  /// Changes staged by transactions still open in this process, in write
  /// order, by transaction id.
  final Map<String, List<String>> _staged = <String, List<String>>{};

  Future<void> _publishing = Future<void>.value();

  DVRecordAdapter get _records => DVRecordAdapter.over(database);

  Future<void>? _ready;

  /// The log's collections, made once per process before the first use.
  Future<void> _ensureReady() => _ready ??= ensureSchema().catchError(
        (Object error, StackTrace stack) {
          _ready = null;
          Error.throwWithStackTrace(error, stack);
        },
      );

  Future<void> ensureSchema() async {
    final DVRecordAdapter records = _records;
    await records.ensure(const DVRecordShape(
      collection: logTable,
      fields: _logFields,
    ));
    await records.ensure(const DVRecordShape(
      collection: stateTable,
      fields: <String, DVFieldType>{
        'id': DVFieldType.text,
        'allocated_through': DVFieldType.integer,
        'published_through': DVFieldType.integer,
        'pruned_through': DVFieldType.integer,
        'lease_until': DVFieldType.text,
      },
    ));
    await records.ensure(const DVRecordShape(
      collection: schemaTable,
      fields: <String, DVFieldType>{
        'model': DVFieldType.text,
        'columns': DVFieldType.text,
      },
    ));
    await records.ensure(const DVRecordShape(
      collection: checkpointTable,
      fields: <String, DVFieldType>{
        'consumer': DVFieldType.text,
        'change_seq': DVFieldType.integer,
        'updated_at': DVFieldType.text,
      },
    ));
    await records.ensure(const DVRecordShape(
      collection: backfillTable,
      fields: <String, DVFieldType>{
        'consumer': DVFieldType.text,
        'model': DVFieldType.text,
        'through_seq': DVFieldType.integer,
        'after_key': DVFieldType.text,
        'rows_done': DVFieldType.integer,
        'done': DVFieldType.integer,
      },
    ));
    final List<Map<String, Object?>> state = await records.find(
      stateTable,
      where: DVFilter.equals('id', _stateId),
      fields: const <String>['id'],
    );
    if (state.isEmpty) {
      await records.insert(stateTable, <String, Object?>{
        'id': _stateId,
        'allocated_through': 0,
        'published_through': 0,
        'pruned_through': 0,
        'lease_until': _stamp(DateTime.utc(1970)),
      });
    }
    _ready ??= Future<void>.value();
  }

  /// Makes [table] known to backfill jobs. [DVRecordTable] calls it, and so
  /// does the framework for every captured model it starts with.
  void track(DVRecordTable table) => _tables[table.table] = table;

  /// The captured tables this log knows, by name.
  Map<String, DVRecordTable> get tracked =>
      Map<String, DVRecordTable>.unmodifiable(_tables);

  /// The consumers registered here, by name.
  Map<String, DVCaptureConsumer> get consumers =>
      Map<String, DVCaptureConsumer>.unmodifiable(_consumers);

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
    await _ensureReady();
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
    await _records.insert(logTable, <String, Object?>{
      'change_id': id,
      'change_seq': null,
      'model': table.table,
      'record_key': jsonEncode(_jsonSafe(key)),
      'operation': operation.name,
      'record_version': version,
      'tenant': resolvedTenant,
      'transaction_id': transaction?.transactionId,
      'occurred_at': _stamp(now),
      'write_order': _writeOrder(now),
      'published_at': null,
      'row_values': row == null ? null : jsonEncode(row),
      'redacted': jsonEncode(table.sensitive.toList()..sort()),
      'erased': erased ? 1 : 0,
      'purged': 0,
    });

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
      await _records.delete(
        logTable,
        where: DVFilter.all(<DVFilter>[
          DVFilter.equals('change_id', id),
          const DVFilter.isNull('change_seq'),
        ]),
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
    await _ensureReady();
    final String cutoff = _stamp(_clock().subtract(strandedAfter));
    final List<Map<String, Object?>> rows = await _records.find(
      logTable,
      where: DVFilter.all(<DVFilter>[
        const DVFilter.isNull('change_seq'),
        DVFilter.compare('occurred_at', DVCompare.less, cutoff),
      ]),
      orderBy: const <DVSort>[DVSort('write_order')],
      fields: const <String>['change_id', 'transaction_id', 'write_order'],
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
    return run.then((int published) {
      if (published > 0) {
        try {
          onPublished?.call(published);
        } on Object {
          // Sending on is delivery's business; the changes are published.
        }
      }
      return published;
    });
  }

  Future<int> _publishSerially(List<String> ids) async {
    final DVRecordAdapter records = _records;
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final String id in ids) {
      final List<Map<String, Object?>> found = await records.find(
        logTable,
        where: DVFilter.all(<DVFilter>[
          DVFilter.equals('change_id', id),
          const DVFilter.isNull('change_seq'),
        ]),
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
      if (raw is String && _asInt(row['purged']) != 1) {
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
        await records.insert(logTable, <String, Object?>{
          'change_id': _newId('sch'),
          'change_seq': sequence,
          'model': entry.$1,
          'record_key': null,
          'operation': entry.$2.name,
          'record_version': 0,
          'tenant': null,
          'transaction_id': null,
          'occurred_at': published,
          'write_order': _writeOrder(_clock()),
          'published_at': published,
          'row_values': jsonEncode(<String, Object?>{'columns': entry.$3}),
          'redacted': '[]',
          'erased': 0,
          'purged': 0,
        });
      } else {
        await records.update(
          logTable,
          <String, Object?>{'change_seq': sequence, 'published_at': published},
          where: DVFilter.all(<DVFilter>[
            DVFilter.equals(
              'change_id',
              (entry as Map<String, Object?>)['change_id'],
            ),
            const DVFilter.isNull('change_seq'),
          ]),
        );
      }
    }
    for (final String model in changedModels) {
      await _saveSchema(model, schemas[model]!);
    }
    final int last = first + plan.length - 1;
    await records.update(
      stateTable,
      <String, Object?>{'published_through': last},
      where: DVFilter.all(<DVFilter>[
        DVFilter.equals('id', _stateId),
        DVFilter.equals('allocated_through', last),
        DVFilter.equals('published_through', first - 1),
      ]),
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
        final int taken = await _records.update(
          stateTable,
          <String, Object?>{
            'allocated_through': state.allocated + count,
            'lease_until': _stamp(_clock().add(lease)),
          },
          where: DVFilter.all(<DVFilter>[
            DVFilter.equals('id', _stateId),
            DVFilter.equals('allocated_through', state.allocated),
            DVFilter.equals('published_through', state.published),
          ]),
        );
        if (taken == 1) return state.allocated + 1;
      } else if (state.leaseUntil.isBefore(_clock())) {
        await _records.update(
          stateTable,
          <String, Object?>{'published_through': state.allocated},
          where: DVFilter.all(<DVFilter>[
            DVFilter.equals('id', _stateId),
            DVFilter.equals('allocated_through', state.allocated),
            DVFilter.equals('published_through', state.published),
          ]),
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
    await _ensureReady();
    final List<Map<String, Object?>> rows = await _records.find(
      stateTable,
      where: DVFilter.equals('id', _stateId),
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
    final List<Map<String, Object?>> rows = await _records.find(
      schemaTable,
      where: DVFilter.equals('model', model),
      fields: const <String>['columns'],
    );
    if (rows.isEmpty) return null;
    return (jsonDecode('${rows.first['columns']}') as List<Object?>)
        .map((Object? c) => '$c')
        .toList();
  }

  Future<void> _saveSchema(String model, List<String> columns) async {
    final int updated = await _records.update(
      schemaTable,
      <String, Object?>{'columns': jsonEncode(columns)},
      where: DVFilter.equals('model', model),
    );
    if (updated == 0) {
      await _records.insert(schemaTable, <String, Object?>{
        'model': model,
        'columns': jsonEncode(columns),
      });
    }
  }

  /// Published entries after [after] and through [through], oldest first,
  /// at most [limit]. With [recordsOnly], schema entries are left out.
  Future<List<Map<String, Object?>>> _published({
    required int after,
    required int through,
    int? limit,
    bool recordsOnly = false,
    List<String>? fields,
  }) =>
      _records.find(
        logTable,
        where: DVFilter.all(<DVFilter>[
          DVFilter.isNotNull('change_seq'),
          DVFilter.compare('change_seq', DVCompare.greater, after),
          DVFilter.compare('change_seq', DVCompare.lessOrEqual, through),
          if (recordsOnly) DVFilter.isNotNull('record_key'),
        ]),
        orderBy: const <DVSort>[DVSort('change_seq')],
        limit: limit == null ? null : math.max(0, limit),
        fields: fields,
      );

  // --- reading --------------------------------------------------------------

  /// The newest published sequence.
  Future<int> head() async => (await _state()).published;

  /// Published record changes after [after], oldest first. Schema changes are
  /// not included; changes an erasure purged are.
  Future<List<DVCapturedChange>> changes({int after = 0, int? limit}) async {
    final _State state = await _state();
    final List<Map<String, Object?>> rows = await _published(
      after: after,
      through: state.published,
      limit: limit,
      recordsOnly: true,
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
    await _ensureReady();
    final String cutoff = _stamp(_clock().subtract(retention));
    final List<Map<String, Object?>> newest = await _records.find(
      logTable,
      where: DVFilter.all(<DVFilter>[
        DVFilter.isNotNull('change_seq'),
        DVFilter.compare('published_at', DVCompare.less, cutoff),
      ]),
      orderBy: const <DVSort>[DVSort('change_seq', descending: true)],
      limit: 1,
      fields: const <String>['change_seq'],
    );
    if (newest.isEmpty) return 0;
    final int through = _asInt(newest.first['change_seq']);
    await _records.update(
      stateTable,
      <String, Object?>{'pruned_through': through},
      where: DVFilter.all(<DVFilter>[
        DVFilter.equals('id', _stateId),
        DVFilter.compare('pruned_through', DVCompare.less, through),
      ]),
    );
    return _records.delete(
      logTable,
      where: DVFilter.all(<DVFilter>[
        DVFilter.isNotNull('change_seq'),
        DVFilter.compare('change_seq', DVCompare.lessOrEqual, through),
      ]),
    );
  }

  // --- erasure --------------------------------------------------------------

  /// Removes every value the log holds for one record, and captures what an
  /// erasure left of it: a delete when it is gone, or its anonymized values
  /// when a retention kept it. Returns that change, published.
  Future<DVCapturedChange> eraseRecord(DVRecordTable table, Object key) async {
    final String id = await recordErasure(table, key);
    final List<Map<String, Object?>> rows = await _records.find(
      logTable,
      where: DVFilter.all(<DVFilter>[
        DVFilter.equals('change_id', id),
        DVFilter.isNotNull('change_seq'),
      ]),
    );
    if (rows.isEmpty) {
      throw StateError(
        'The erasure of ${table.table}[$key] was captured but not published; '
        'destinations were not reached.',
      );
    }
    return _changeFromRow(rows.first);
  }

  /// Purges every value the log holds for one record and captures what a
  /// removal left of it, returning the change id: published at once, or
  /// staged and published after commit inside `DV.transaction`.
  ///
  /// This is what a row removed or anonymized beside [DVRecordTable] -- by an
  /// erasure, a retention sweep or a replayed erasure -- owes the log. A
  /// record that is gone is captured as a delete one version past the newest
  /// the log or [version], the version the caller removed, knows of; a
  /// destination applies changes by version, and a delete at a version it
  /// already holds is one it rightly ignores.
  Future<String> recordErasure(
    DVRecordTable table,
    Object key, {
    int? version,
  }) async {
    await _ensureReady();
    final String recordKey = jsonEncode(_jsonSafe(key));
    final DVFilter thisRecord = DVFilter.all(<DVFilter>[
      DVFilter.equals('model', table.table),
      DVFilter.equals('record_key', recordKey),
    ]);
    final List<Map<String, Object?>> newest = await _records.find(
      logTable,
      where: thisRecord,
      orderBy: const <DVSort>[DVSort('record_version', descending: true)],
      limit: 1,
      fields: const <String>['record_version'],
    );
    await _records.update(
      logTable,
      <String, Object?>{'row_values': null, 'purged': 1},
      where: thisRecord,
    );
    final DVRecord? current = await table.read(key, withDeleted: true);
    final bool live = current != null && current.deletedAt == null;
    final int known = math.max(
      version ?? 0,
      newest.isEmpty ? 0 : _asInt(newest.first['record_version']),
    );
    return record(
      table: table,
      operation: live ? DVCaptureOp.update : DVCaptureOp.delete,
      key: key,
      version: current?.version ?? known + 1,
      values: live ? current.values : const <String, Object?>{},
      erased: true,
    );
  }

  // --- jobs -----------------------------------------------------------------

  /// Registers delivery and backfill on the durable job layer, with the
  /// codecs a queue shared between processes stores them under. A refused
  /// batch throws, so the queue retries it with its backoff.
  void registerJobs(DVQueues queues) {
    const DVJobPayloadCodecs()
      ..register<DVCaptureDeliveryJob>(
        const DVJobPayloadCodec<DVCaptureDeliveryJob>(
          name: DVCaptureDeliveryJob.codecName,
          encode: DVCaptureDeliveryJob.encode,
          decode: DVCaptureDeliveryJob.decode,
        ),
      )
      ..register<DVCaptureBackfillJob>(
        const DVJobPayloadCodec<DVCaptureBackfillJob>(
          name: DVCaptureBackfillJob.codecName,
          encode: DVCaptureBackfillJob.encode,
          decode: DVCaptureBackfillJob.decode,
        ),
      );
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
      values: raw is String && _asInt(row['purged']) != 1
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
      erased: _asInt(row['erased']) == 1,
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

  DVRecordAdapter get _records => capture._records;

  DVFilter get _mine => DVFilter.equals('consumer', name);

  /// The last sequence this consumer has delivered, or 0.
  Future<int> checkpoint() async => (await position()) ?? 0;

  /// The last sequence this consumer has delivered, or null when it has
  /// never delivered anything: a destination with no position yet, which
  /// has none of the history and needs a backfill.
  Future<int?> position() async {
    await capture._ensureReady();
    final List<Map<String, Object?>> rows = await _records.find(
      DVCapture.checkpointTable,
      where: _mine,
      fields: const <String>['change_seq'],
    );
    return rows.isEmpty ? null : _asInt(rows.first['change_seq']);
  }

  Future<void> _saveCheckpoint(int sequence) async {
    final String now = _stamp(capture._clock());
    final int updated = await _records.update(
      DVCapture.checkpointTable,
      <String, Object?>{'change_seq': sequence, 'updated_at': now},
      where: _mine,
    );
    if (updated == 0) {
      await _records.insert(DVCapture.checkpointTable, <String, Object?>{
        'consumer': name,
        'change_seq': sequence,
        'updated_at': now,
      });
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
    final List<Map<String, Object?>> rows = await capture._published(
      after: start,
      through: state.published,
      limit: batchSize,
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
      if (_asInt(row['purged']) != 1 &&
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
    final List<Map<String, Object?>> pending = await capture._published(
      after: at,
      through: head,
      recordsOnly: true,
      fields: const <String>['occurred_at'],
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

  /// Where the backfill of [model] stands, or null when none has started.
  Future<DVCaptureBackfillProgress?> backfillProgress(String model) async {
    await capture._ensureReady();
    final List<Map<String, Object?>> rows = await _records.find(
      DVCapture.backfillTable,
      where: _backfillOf(model),
    );
    if (rows.isEmpty) return null;
    return DVCaptureBackfillProgress(
      model: model,
      throughSequence: _asInt(rows.first['through_seq']),
      rows: _asInt(rows.first['rows_done']),
      done: _asInt(rows.first['done']) == 1,
    );
  }

  DVFilter _backfillOf(String model) => DVFilter.all(<DVFilter>[
        _mine,
        DVFilter.equals('model', model),
      ]);

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
    List<Map<String, Object?>> state = await _records.find(
      DVCapture.backfillTable,
      where: _backfillOf(model),
    );
    if (state.isEmpty || _asInt(state.first['done']) == 1) {
      final int through = await capture.head();
      if (state.isEmpty) {
        await _records.insert(DVCapture.backfillTable, <String, Object?>{
          'consumer': name,
          'model': model,
          'through_seq': through,
          'after_key': null,
          'rows_done': 0,
          'done': 0,
        });
      } else {
        await _records.update(
          DVCapture.backfillTable,
          <String, Object?>{
            'through_seq': through,
            'after_key': null,
            'rows_done': 0,
            'done': 0,
          },
          where: _backfillOf(model),
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
      state = await _records.find(
        DVCapture.backfillTable,
        where: _backfillOf(model),
      );
    }

    final int through = _asInt(state.first['through_seq']);
    Object? after = state.first['after_key'] == null
        ? null
        : jsonDecode('${state.first['after_key']}');
    int rowsDone = _asInt(state.first['rows_done']);
    // The model's own rows, read through the record operations its engine
    // implements.
    final DVRecordAdapter source = DVRecordAdapter.over(table.database);
    int chunks = 0;

    while (true) {
      final List<Map<String, Object?>> rows = await source.find(
        model,
        where: after == null
            ? null
            : DVFilter.compare(table.key, DVCompare.greater, after),
        orderBy: <DVSort>[DVSort(table.key)],
        limit: chunkSize,
      );
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
      await _records.update(
        DVCapture.backfillTable,
        <String, Object?>{
          'after_key': after == null ? null : jsonEncode(_jsonSafe(after)),
          'rows_done': rowsDone,
          'done': done ? 1 : 0,
        },
        where: _backfillOf(model),
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

/// The reference store destination: one collection per model in any
/// database Dartvel runs on -- a SQL table or a document collection --
/// holding each record's newest state.
///
/// Written through the record operations every engine implements, never
/// SQL, so a destination is another store the application could have used,
/// configured by where it is rather than by what language it speaks.
///
/// What it demonstrates is the contract a real warehouse adapter has to keep,
/// not a storage engine: changes applied by record version so out-of-order
/// commits leave the newest row, deletes that remove rows, a key reused after
/// a delete treated as a new record, erasures that no in-flight change can
/// undo, and idempotent schema evolution. Rows land as they were written;
/// there is no transformation.
///
/// A capture carries field names, not types. A field is stored as
/// [fieldType] says, or else as its first value is: a whole number, a
/// fraction, a flag, or text.
class DVWarehouseSink implements DVCaptureSink {
  DVWarehouseSink({
    required this.database,
    this.name = 'warehouse',
    this.fieldType,
  });

  static const String tombstoneTable = 'dv_warehouse_tombstones';

  /// The sink's own fields. Sequences and incarnations are 64 bits, as in
  /// the log they come from.
  static const Map<String, DVFieldType> _meta = <String, DVFieldType>{
    '_dv_key': DVFieldType.text,
    '_dv_version': DVFieldType.integer,
    '_dv_seq': DVFieldType.integer,
    '_dv_incarnation': DVFieldType.integer,
    '_dv_change_id': DVFieldType.text,
    '_dv_tenant': DVFieldType.text,
    '_dv_transaction_id': DVFieldType.text,
    '_dv_occurred_at': DVFieldType.text,
    '_dv_backfilled': DVFieldType.integer,
  };

  final DVDatabaseAdapter database;

  /// How [field] of [model] is stored; inferred from its values when null.
  final DVFieldType Function(String model, String field)? fieldType;

  @override
  final String name;

  /// Applying a change twice is a no-op, because it is applied by version.
  @override
  bool get deduplicates => true;

  DVRecordAdapter get _records => DVRecordAdapter.over(database);

  /// The data fields each model's collection has been given in this
  /// process, with how they are stored.
  final Map<String, Map<String, DVFieldType>> _fields =
      <String, Map<String, DVFieldType>>{};

  Future<void> _ensureTombstones() => _records.ensure(const DVRecordShape(
        collection: tombstoneTable,
        fields: <String, DVFieldType>{
          'model': DVFieldType.text,
          'record_key': DVFieldType.text,
          'record_version': DVFieldType.integer,
          'change_seq': DVFieldType.integer,
          'incarnation': DVFieldType.integer,
          'erased': DVFieldType.integer,
        },
      ));

  /// The model's collection, with its bookkeeping and every data field
  /// known here plus [add].
  Future<void> _ensureModel(
    String model, [
    Map<String, DVFieldType> add = const <String, DVFieldType>{},
  ]) async {
    _checkIdentifier(model);
    await _ensureTombstones();
    final Map<String, DVFieldType> known =
        _fields.putIfAbsent(model, () => <String, DVFieldType>{});
    for (final MapEntry<String, DVFieldType> field in add.entries) {
      known.putIfAbsent(field.key, () => field.value);
    }
    await _records.ensure(DVRecordShape(
      collection: model,
      key: '_dv_key',
      fields: <String, DVFieldType>{..._meta, ...known},
    ));
  }

  /// Ensures what [values] names that the collection may not have yet, typed
  /// by [fieldType] or by the value, and answers the fields left unset: one
  /// whose type is unknown and whose value is null waits for a value to
  /// decide it, and a record written without it holds nothing there either.
  Future<Set<String>> _ensureFields(
    String model,
    Map<String, Object?> values,
  ) async {
    final Map<String, DVFieldType> known =
        _fields.putIfAbsent(model, () => <String, DVFieldType>{});
    final Map<String, DVFieldType> add = <String, DVFieldType>{};
    final Set<String> unset = <String>{};
    for (final MapEntry<String, Object?> e in values.entries) {
      _checkField(e.key);
      if (known.containsKey(e.key)) continue;
      final DVFieldType? type =
          fieldType?.call(model, e.key) ?? _inferred(e.value);
      if (type == null) {
        unset.add(e.key);
      } else {
        add[e.key] = type;
      }
    }
    await _ensureModel(model, add);
    return unset;
  }

  static DVFieldType? _inferred(Object? value) => switch (value) {
        null => null,
        bool() => DVFieldType.boolean,
        int() => DVFieldType.integer,
        double() => DVFieldType.real,
        _ => DVFieldType.text,
      };

  static void _checkField(String field) {
    _checkIdentifier(field);
    if (field.startsWith('_dv_')) {
      throw ArgumentError.value(field, 'field', 'is reserved');
    }
  }

  @override
  Future<void> evolve(DVCaptureSchemaChange change) async {
    for (final String field in change.columns) {
      _checkField(field);
    }
    if (change.phase == DVCaptureSchemaPhase.expand) {
      // Added now when the type is declared; otherwise the first value
      // decides, and the field is added with it.
      await _ensureModel(change.model, <String, DVFieldType>{
        if (fieldType != null)
          for (final String field in change.columns)
            field: fieldType!(change.model, field),
      });
      return;
    }
    // A store has no column to drop, so what the source no longer declares
    // is removed from every copy instead: its values, which is what a
    // dropped column took with it. A field that became sensitive leaves the
    // destination this way too.
    await _ensureModel(change.model, <String, DVFieldType>{
      for (final String field in change.columns)
        if (!(_fields[change.model]?.containsKey(field) ?? false))
          field: DVFieldType.text,
    });
    for (final String field in change.columns) {
      await _records.update(
        change.model,
        <String, Object?>{field: null},
        where: DVFilter.isNotNull(field),
      );
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
      await _apply(change, force: true);
    }
  }

  @override
  Future<void> backfillComplete(
    String model,
    int throughSequence, {
    String? tenant,
  }) async {
    await _ensureModel(model);
    final List<DVFilter> scope = <DVFilter>[
      DVFilter.compare('_dv_seq', DVCompare.lessOrEqual, throughSequence),
      if (tenant != null) DVFilter.equals('_dv_tenant', tenant),
    ];
    await _records.delete(
      model,
      where: DVFilter.all(<DVFilter>[
        ...scope,
        const DVFilter.isNull('_dv_backfilled'),
      ]),
    );
    await _records.delete(
      model,
      where: DVFilter.all(<DVFilter>[
        ...scope,
        DVFilter.compare('_dv_backfilled', DVCompare.less, throughSequence),
      ]),
    );
  }

  DVFilter _tombstoneOf(String model, Object? key) => DVFilter.all(<DVFilter>[
        DVFilter.equals('model', model),
        DVFilter.equals('record_key', jsonEncode(_jsonSafe(key))),
      ]);

  Future<void> _apply(DVCapturedChange x, {required bool force}) async {
    final String model = _checkIdentifier(x.model);
    final Map<String, Object?> carried = <String, Object?>{
      for (final MapEntry<String, Object?> e in x.values.entries)
        if (!x.redacted.contains(e.key)) e.key: e.value,
    };
    final Set<String> unset = await _ensureFields(model, carried);
    carried.removeWhere((String field, Object? _) => unset.contains(field));
    final String key = '${x.key}';
    final List<Map<String, Object?>> rows = await _records.find(
      model,
      where: DVFilter.equals('_dv_key', key),
      fields: const <String>['_dv_version', '_dv_seq', '_dv_incarnation'],
    );
    final List<Map<String, Object?>> tombs = await _records.find(
      tombstoneTable,
      where: _tombstoneOf(model, x.key),
    );
    final Map<String, Object?>? row = rows.isEmpty ? null : rows.first;
    final Map<String, Object?>? tomb = tombs.isEmpty ? null : tombs.first;

    // Nothing written before an erasure may land after it.
    if (!force &&
        tomb != null &&
        _asInt(tomb['erased']) == 1 &&
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
          await _upsert(x, carried,
              exists: true, incarnation: since, backfilled: true);
        } else {
          await _records.update(
            model,
            <String, Object?>{'_dv_backfilled': x.sequence},
            where: DVFilter.equals('_dv_key', key),
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

    Future<void> entomb({required bool erased}) async {
      await _records.delete(tombstoneTable, where: _tombstoneOf(model, x.key));
      await _records.insert(tombstoneTable, <String, Object?>{
        'model': model,
        'record_key': jsonEncode(_jsonSafe(x.key)),
        'record_version': x.version,
        'change_seq': x.sequence,
        'incarnation': incarnation,
        'erased': erased ? 1 : 0,
      });
    }

    if (x.operation == DVCaptureOp.delete) {
      await _records.delete(model, where: DVFilter.equals('_dv_key', key));
      await entomb(erased: x.erased || _asInt(tomb?['erased']) == 1);
      return;
    }

    if (tomb != null && _asInt(tomb['erased']) != 1) {
      await _records.delete(tombstoneTable, where: _tombstoneOf(model, x.key));
    }
    if (force && x.erased) await entomb(erased: true);
    await _upsert(x, carried,
        exists: row != null,
        incarnation: incarnation,
        backfilled: x.operation == DVCaptureOp.snapshot);
  }

  Future<void> _upsert(
    DVCapturedChange x,
    Map<String, Object?> carried, {
    required bool exists,
    required int incarnation,
    required bool backfilled,
  }) async {
    final String key = '${x.key}';
    final Map<String, Object?> values = <String, Object?>{
      ...carried,
      '_dv_version': x.version,
      '_dv_seq': x.sequence,
      '_dv_incarnation': incarnation,
      '_dv_change_id': x.id,
      '_dv_tenant': x.tenant,
      '_dv_transaction_id': x.transactionId,
      '_dv_occurred_at': x.occurredAt.toUtc().toIso8601String(),
      if (backfilled) '_dv_backfilled': x.sequence,
    };
    if (exists) {
      await _records.update(
        x.model,
        values,
        where: DVFilter.equals('_dv_key', key),
      );
    } else {
      await _records.insert(x.model, <String, Object?>{
        '_dv_key': key,
        ...values,
      });
    }
  }
}

/// Erasure for the capture log and the destinations it feeds.
///
/// Given the rows an erasure reached, it removes every value the log holds
/// for them, captures what the erasure left -- a delete, or a retained row's
/// anonymized values -- so a consumer that is behind receives that and never
/// the earlier values, and applies the same changes to each destination
/// directly. Without it [DVPrivacy] still purges the log and captures the
/// removal for every captured model, so delivery reaches every destination;
/// what this adds is reaching [sinks] now, and knowing when one was not. A
/// destination that cannot be reached makes the erasure incomplete
/// (`DV-PRIVACY-009`) rather than waiting on delivery that may never run.
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
  if (value is bool) return value ? 1 : 0;
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
