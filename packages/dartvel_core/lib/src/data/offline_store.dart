/// Offline-first models: a local store, an ordered mutation log, and replay
/// that resolves conflicts the way the model declared.
///
/// This is the runtime the specification's `# Offline-First Models`
/// describes. It sits on [DVRecordTable]: the local store is one, and the
/// conflict vocabulary is [DVConflict], the same enum the online case uses,
/// because the strategies are not different offline — only whether anybody is
/// present to be asked is.
library dartvel_core.data.offline_store;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../database/adapter.dart';
import '../database/framework_tables.dart';
import '../observability/logging.dart' show DVLogLevel;
import '../observability/observability.dart' show DVObservability;
import 'record_history.dart';

/// How a model behaves while the device is disconnected.
class DVOffline {
  const DVOffline({
    required this.strategy,
    this.encrypt = false,
    this.maxMutations = 10000,
    this.maxAge = const Duration(days: 7),
    this.maxClockSkew = const Duration(minutes: 5),
  });

  /// How a replayed write that finds the server row moved is resolved.
  final DVConflict strategy;

  /// Whether the whole model is encrypted at rest on the device.
  final bool encrypt;

  /// The most mutations the log holds before the next write is refused.
  final int maxMutations;

  /// How old the oldest queued mutation may be before the next write is
  /// refused.
  final Duration maxAge;

  /// How far the device clock may drift from the server's before it is
  /// reported (`DV-OFFLINE-004`).
  final Duration maxClockSkew;
}

/// A conflict strategy that cannot work offline was declared for an offline
/// model (`DV-HISTORY-002`).
class DVOfflineStrategyError implements Exception {
  DVOfflineStrategyError(this.strategy);

  final DVConflict strategy;
  final String code = 'DV-HISTORY-002';

  @override
  String toString() => '$code: $strategy is not an offline strategy. It '
      'refuses the write and waits for the writer to choose, and offline '
      'there is nobody present to choose. Declare lastWriteWins, serverWins, '
      'fieldMerge or a resolver.';
}

/// A write refused because the mutation log is at its bound
/// (`DV-OFFLINE-002`).
///
/// Refused rather than making room: dropping the oldest queued write would
/// keep the application feeling fine while discarding work somebody believed
/// was saved, and no later sync could bring it back.
class DVOfflineQueueFullError implements Exception {
  DVOfflineQueueFullError({
    required this.table,
    required this.pending,
    required this.limit,
    this.oldest,
    this.maxAge,
  });

  final String table;
  final int pending;
  final int limit;

  /// When the oldest queued mutation was made, when age is what refused it.
  final DateTime? oldest;
  final Duration? maxAge;

  final String code = 'DV-OFFLINE-002';

  bool get byAge => maxAge != null;

  @override
  String toString() => byAge
      ? '$code: $table cannot queue another write; its oldest unsynced write '
          'is from $oldest, older than the ${maxAge!.inHours}h the log holds. '
          'Reconnect to sync before writing more.'
      : '$code: $table cannot queue another write; $pending writes are '
          'waiting to sync and the log holds $limit. Reconnect to sync before '
          'writing more.';
}

/// Where a record stands relative to the server.
enum DVSyncState {
  /// Written on the device and not yet on the server.
  pending,

  /// Being sent now.
  syncing,

  /// The server holds what the device holds.
  synced,

  /// The server resolved a conflict, and holds something other than what the
  /// device wrote.
  conflicted,

  /// The server refused the write permanently; it is in the dead letters.
  rejected,
}

/// One write made on the device, waiting to reach the server.
class DVMutation {
  DVMutation({
    required this.mutationId,
    required this.sequence,
    required this.table,
    required this.op,
    required this.key,
    required Map<String, Object?> values,
    required this.deviceTime,
    required this.correctedTime,
    this.base,
    this.rejection,
  }) : values = Map<String, Object?>.unmodifiable(values);

  static const String opWrite = 'write';
  static const String opDelete = 'delete';

  /// Sent with every attempt, so the server can tell a resend from a second
  /// write.
  final String mutationId;

  /// Order on this device. Replay follows it.
  final int sequence;
  final String table;

  /// [opWrite] or [opDelete].
  final String op;
  final Object key;
  final Map<String, Object?> values;

  /// The device clock when the write was made — what its user saw.
  final DateTime deviceTime;

  /// [deviceTime] corrected by the offset the device last observed from the
  /// server. This is the stamp a declared clock compares.
  final DateTime correctedTime;

  /// The server's record as this device last knew it, attached at replay so a
  /// queued write is checked against what the server acknowledged rather than
  /// against an earlier local write.
  final DVRecord? base;

  /// Why the server refused it, for a dead-lettered mutation.
  final String? rejection;

  bool get isDelete => op == opDelete;

  DVMutation withBase(DVRecord? base) => DVMutation(
        mutationId: mutationId,
        sequence: sequence,
        table: table,
        op: op,
        key: key,
        values: values,
        deviceTime: deviceTime,
        correctedTime: correctedTime,
        base: base,
        rejection: rejection,
      );

  @override
  String toString() => 'DVMutation(#$sequence $op $table[$key])';
}

/// What the server did with a replayed mutation.
class DVRemoteOutcome {
  const DVRemoteOutcome.applied(this.record,
      {this.conflict, this.discarded = false})
      : rejection = null;

  const DVRemoteOutcome.rejected(String this.rejection)
      : record = null,
        conflict = null,
        discarded = false;

  /// The server's record afterwards; null after a delete.
  final DVRecord? record;

  /// The conflict the declared strategy resolved, if any.
  final DVConflictError? conflict;

  /// Whether the device's change was discarded.
  final bool discarded;

  /// Why the server refused permanently; null when it applied.
  final String? rejection;

  bool get isRejected => rejection != null;
}

/// Where replayed mutations go.
///
/// [apply] must be idempotent by [DVMutation.mutationId]: replay resends a
/// mutation whose acknowledgement was lost, and the resend must not be a
/// second write. A thrown error is transient — the connection dropped — and
/// stops replay so later writes are not sent ahead of it; a permanent refusal
/// is returned as [DVRemoteOutcome.rejected].
abstract class DVOfflineRemote {
  Future<DVRemoteOutcome> apply(DVMutation mutation);
}

/// The server side of replay over a [DVRecordTable]: deduplicates by mutation
/// id and resolves by the declared strategy and clock.
class DVRecordTableRemote implements DVOfflineRemote {
  DVRecordTableRemote(
    this.table, {
    required this.strategy,
    this.authorize,
    this.validate,
    this.actor,
  }) {
    if (!strategy.allowedOffline) throw DVOfflineStrategyError(strategy);
  }

  final DVRecordTable table;
  final DVConflict strategy;

  /// Whether this mutation may be applied at all, asked before anything is
  /// written and before [validate].
  ///
  /// Replay is the one write path where the server is handed a change that
  /// nothing on the server decided to make: it was made on a device,
  /// possibly days ago, possibly by somebody whose access has since been
  /// withdrawn, and it names its own table and key. Applying it because it
  /// arrived is the same as having no authorization on the route that
  /// carries it.
  ///
  /// A generated `Model.offlineRemote` always supplies one, which asks the
  /// model's own policy -- the same policy an online write asks. This class
  /// is not in the barrel an application imports, so the only remotes
  /// without one are the framework's own and its tests'.
  ///
  /// An authorizer that throws refuses. A check that cannot reach its answer
  /// is not a yes.
  final Future<bool> Function(DVMutation mutation)? authorize;

  /// Returns false to refuse a write permanently, as failed validation would.
  ///
  /// Asked for a delete as well as a write. It used to be asked only on the
  /// write path, so a queued delete for any key in the table was applied
  /// unchecked.
  final bool Function(Map<String, Object?> values)? validate;
  final String? actor;

  DVDatabaseAdapter get _database => table.database;

  /// Mutation ids already applied, and what came of each.
  String get appliedTable => '${table.table}__applied';

  /// The declared clock of the last write that landed on each record.
  String get clockTable => '${table.table}__clock';

  Future<void> ensureSchema() async {
    await table.ensureSchema();
    await _database.execute(
      'CREATE TABLE IF NOT EXISTS $appliedTable (mutation_id TEXT, '
      'outcome TEXT)',
    );
    await dvEnsureFrameworkTable(
      _database,
      'CREATE TABLE IF NOT EXISTS $clockTable (record_key TEXT, '
      'at_micros BIGINT)',
    );
  }

  @override
  Future<DVRemoteOutcome> apply(DVMutation mutation) async {
    final List<Map<String, Object?>> seen = await _database.query(
      'SELECT outcome FROM $appliedTable WHERE mutation_id = ?',
      <Object?>[mutation.mutationId],
    );
    if (seen.isNotEmpty) {
      final Map<String, Object?> outcome =
          jsonDecode('${seen.first['outcome']}') as Map<String, Object?>;
      final Object? rejection = outcome['rejection'];
      if (rejection is String) return DVRemoteOutcome.rejected(rejection);
      return DVRemoteOutcome.applied(await table.read(mutation.key),
          discarded: outcome['discarded'] == true);
    }

    final DVRemoteOutcome outcome = await _applyOnce(mutation);
    await _database.execute(
      'INSERT INTO $appliedTable (mutation_id, outcome) VALUES (?, ?)',
      <Object?>[
        mutation.mutationId,
        jsonEncode(<String, Object?>{
          'discarded': outcome.discarded,
          if (outcome.rejection != null) 'rejection': outcome.rejection,
        }),
      ],
    );
    return outcome;
  }

  Future<DVRemoteOutcome> _applyOnce(DVMutation mutation) async {
    // Before anything is written, and before the shape of the values is
    // looked at: whether this change may be made at all.
    final Future<bool> Function(DVMutation)? asked = authorize;
    if (asked != null) {
      bool allowed;
      try {
        allowed = await asked(mutation);
      } catch (_) {
        // Default deny. A policy that could not decide is not a yes, and a
        // replayed write that landed because the policy engine was
        // unreachable is the failure nobody sees.
        allowed = false;
      }
      if (!allowed) {
        return const DVRemoteOutcome.rejected('refused by authorization');
      }
    }

    // Asked for a delete too. This ran on the write path only, so a queued
    // delete for any key in the table went through unchecked.
    final bool Function(Map<String, Object?>)? check = validate;
    if (check != null && !check(mutation.values)) {
      return const DVRemoteOutcome.rejected('refused by validation');
    }

    if (mutation.isDelete) {
      await table.delete(mutation.key, actor: actor);
      await _setClock(mutation.key, mutation.correctedTime);
      return const DVRemoteOutcome.applied(null);
    }

    final DVRecord? current = await table.read(mutation.key, withDeleted: true);
    final DateTime? lastAt = await _clock(mutation.key);

    // Last-write-wins by the declared clock. DVRecordTable's own
    // lastWriteWins lets the writer at hand win, which is right online; here
    // the writer at hand is simply the one that reconnected last, and letting
    // it win would resolve by arrival order.
    if (current != null &&
        strategy.name == DVConflict.lastWriteWins.name &&
        lastAt != null &&
        lastAt.isAfter(mutation.correctedTime)) {
      return DVRemoteOutcome.applied(
        current,
        conflict: DVConflictError(
          table: table.table,
          key: mutation.key,
          mine: mutation.values,
          theirs: current.values,
          base: mutation.base?.values,
          expectedVersion: mutation.base?.version,
          actualVersion: current.version,
        ),
        discarded: true,
      );
    }

    final DVWriteResult result = await table.write(
      mutation.values,
      base: mutation.base,
      onConflict: strategy,
      actor: actor,
    );
    if (!result.discarded) {
      await _setClock(mutation.key, mutation.correctedTime);
    }
    return DVRemoteOutcome.applied(result.record,
        conflict: result.conflict, discarded: result.discarded);
  }

  /// A write made on the server itself, at [at] by the declared clock.
  Future<DVRemoteOutcome> applyDirect(Map<String, Object?> values,
      {required DateTime at}) async {
    final Object key = values[table.key]!;
    final DVRecord? current = await table.read(key, withDeleted: true);
    final DVWriteResult result = await table.write(values,
        base: current, onConflict: DVConflict.lastWriteWins, actor: actor);
    await _setClock(key, at);
    return DVRemoteOutcome.applied(result.record);
  }

  Future<DateTime?> _clock(Object key) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT at_micros FROM $clockTable WHERE record_key = ?',
      <Object?>[jsonEncode(key)],
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMicrosecondsSinceEpoch(
        (rows.first['at_micros']! as num).toInt(),
        isUtc: true);
  }

  Future<void> _setClock(Object key, DateTime at) async {
    final DateTime? previous = await _clock(key);
    if (previous != null && previous.isAfter(at)) return;
    final String encoded = jsonEncode(key);
    if (previous == null) {
      await _database.execute(
        'INSERT INTO $clockTable (record_key, at_micros) VALUES (?, ?)',
        <Object?>[encoded, at.microsecondsSinceEpoch],
      );
    } else {
      await _database.execute(
        'UPDATE $clockTable SET at_micros = ? WHERE record_key = ?',
        <Object?>[at.microsecondsSinceEpoch, encoded],
      );
    }
  }
}

/// The device's clock, corrected by what the server says the time is.
///
/// A device offline for a week, or one whose owner changed the date, stamps
/// its writes with a time the server disagrees with, and last-write-wins
/// compares exactly those stamps — so a wrong clock would win every conflict.
class DVOfflineClock {
  DVOfflineClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Server time minus device time, as last observed.
  Duration offset = Duration.zero;

  Duration _tolerance = const Duration(minutes: 5);
  void Function(Duration offset)? _onSkew;
  bool _skewReported = false;

  DateTime get deviceNow => _now().toUtc();
  DateTime get correctedNow => deviceNow.add(offset);

  /// Records the server's time, as a sync learns it.
  void observeServerTime(DateTime server) {
    offset = server.toUtc().difference(deviceNow);
    if (!_skewReported && offset.abs() > _tolerance) {
      _skewReported = true;
      _onSkew?.call(offset);
    }
  }
}

/// The outcome of one replay.
class DVReplayResult {
  const DVReplayResult({
    this.applied = 0,
    this.rejected = 0,
    this.conflicted = 0,
    this.stopped = false,
  });

  /// Mutations the server accepted, whether as written or resolved.
  final int applied;

  /// Mutations the server refused permanently and that moved to dead letters.
  final int rejected;

  /// Accepted mutations the server resolved into something other than what the
  /// device wrote.
  final int conflicted;

  /// Whether a transient failure stopped replay with mutations still queued.
  final bool stopped;
}

/// A model's local store and mutation log.
///
/// Reads and writes go to the local store whether or not the device is
/// connected; writes are also appended to the log, and [replay] sends them to
/// the server in the order they were made.
class DVOfflineStore {
  DVOfflineStore({
    required this.table,
    required this.policy,
    DVOfflineClock? clock,
    bool? persistent,
  })  : clock = clock ?? DVOfflineClock(),
        persistent = persistent ?? table.database is! MemoryDVDatabaseAdapter {
    if (!policy.strategy.allowedOffline) {
      throw DVOfflineStrategyError(policy.strategy);
    }
    this.clock
      .._tolerance = policy.maxClockSkew
      .._onSkew = (Duration offset) => _report(
            'DV-OFFLINE-004',
            'The device clock is ${offset.inMinutes.abs()} minutes '
                '${offset.isNegative ? 'ahead of' : 'behind'} the server; '
                'writes are stamped with corrected time.',
            DVLogLevel.warn,
          );
  }

  /// The local store.
  final DVRecordTable table;
  final DVOffline policy;
  final DVOfflineClock clock;

  /// Whether the local store survives the application closing. A memory
  /// adapter does not, and says so (`DV-OFFLINE-001`).
  final bool persistent;

  /// Codes reported this session, in order.
  final List<String> reported = <String>[];

  final Map<Object, DVSyncState> _states = <Object, DVSyncState>{};
  final StreamController<(Object, DVSyncState)> _changes =
      StreamController<(Object, DVSyncState)>.broadcast();
  final math.Random _random = math.Random();
  int _sequence = 0;
  Future<DVReplayResult>? _replaying;

  DVDatabaseAdapter get _database => table.database;

  String get logTable => '${table.table}__mutations';

  /// The server's record for each key as this device last saw it.
  String get serverTable => '${table.table}__server';

  Future<void> ensureSchema() async {
    await table.ensureSchema();
    await dvEnsureFrameworkTable(
      _database,
      'CREATE TABLE IF NOT EXISTS $logTable (seq BIGINT, mutation_id TEXT, '
      'op TEXT, record_key TEXT, payload TEXT, state TEXT, rejection TEXT)',
    );
    await _database.execute(
      'CREATE TABLE IF NOT EXISTS $serverTable (record_key TEXT, '
      'version INTEGER, payload TEXT)',
    );
    final List<Map<String, Object?>> last = await _database
        .query('SELECT seq FROM $logTable ORDER BY seq DESC LIMIT 1');
    _sequence = last.isEmpty ? 0 : (last.first['seq']! as num).toInt();
    for (final DVMutation m in await pending()) {
      _states[m.key] = DVSyncState.pending;
    }
    for (final DVMutation m in await rejected()) {
      _states[m.key] = DVSyncState.rejected;
    }
    if (!persistent) {
      _report(
        'DV-OFFLINE-001',
        '${table.table} has no writable storage on this device; its offline '
            'store is memory-backed and will not survive the application '
            'closing.',
        DVLogLevel.warn,
      );
    }
  }

  // --- reads ----------------------------------------------------------------

  Future<DVRecord?> read(Object id) => table.read(id);

  Future<List<DVRecord>> all() => table.all();

  /// Writes waiting to reach the server, oldest first.
  Future<List<DVMutation>> pending() => _mutations('pending');

  /// Writes the server refused permanently.
  Future<List<DVMutation>> rejected() => _mutations('rejected');

  DVSyncState syncStateOf(Object id) => _states[id] ?? DVSyncState.synced;

  /// Each change to [id]'s sync state.
  Stream<DVSyncState> watchSyncState(Object id) => _changes.stream
      .where(((Object, DVSyncState) change) => change.$1 == id)
      .map(((Object, DVSyncState) change) => change.$2);

  // --- writes ---------------------------------------------------------------

  /// Stores [values] locally and queues them for the server.
  Future<DVRecord> write(Map<String, Object?> values) async {
    final Object? id = values[table.key];
    if (id == null) {
      throw ArgumentError.value(values, 'values', 'has no ${table.key}');
    }
    await _ensureCapacity();
    final DVRecord? local = await table.read(id);
    final DVWriteResult result = await table.write(values,
        base: local, onConflict: DVConflict.lastWriteWins);
    await _append(DVMutation.opWrite, id, values);
    return result.record;
  }

  /// Deletes locally and queues the delete for the server.
  Future<void> delete(Object id) async {
    await _ensureCapacity();
    await table.delete(id);
    await _append(DVMutation.opDelete, id, const <String, Object?>{});
  }

  /// Takes the server's [record] as this device's copy and as the base its
  /// next writes are checked against.
  Future<void> adoptServer(DVRecord record) async {
    await _setServer(record);
    final DVRecord? local = await table.read(record.key);
    await table.write(record.values,
        base: local, onConflict: DVConflict.lastWriteWins);
  }

  /// Empties the local store and the log, as signing out does.
  Future<void> clear() async {
    await _database.execute('DELETE FROM ${table.table}');
    await _database.execute('DELETE FROM $logTable');
    await _database.execute('DELETE FROM $serverTable');
    _states.clear();
  }

  // --- replay ---------------------------------------------------------------

  /// Sends queued mutations to [remote], in order.
  ///
  /// Two calls at once share one run: a reconnect that fires twice must not
  /// send the log twice.
  Future<DVReplayResult> replay(DVOfflineRemote remote) {
    return _replaying ??=
        _replay(remote).whenComplete(() => _replaying = null);
  }

  Future<DVReplayResult> _replay(DVOfflineRemote remote) async {
    int applied = 0;
    int rejectedCount = 0;
    int conflicted = 0;
    final List<DVMutation> queue = await pending();

    for (int i = 0; i < queue.length; i++) {
      final DVMutation mutation = queue[i];
      _setState(mutation.key, DVSyncState.syncing);

      final DVRemoteOutcome outcome;
      try {
        outcome = await remote.apply(mutation.withBase(await _server(mutation.key)));
      } on Object {
        // Transient. Stop here: sending the next one would apply it ahead of
        // this one.
        _setState(mutation.key, DVSyncState.pending);
        return DVReplayResult(
          applied: applied,
          rejected: rejectedCount,
          conflicted: conflicted,
          stopped: true,
        );
      }

      final bool laterForKey = queue
          .skip(i + 1)
          .any((DVMutation later) => later.key == mutation.key);

      if (outcome.isRejected) {
        await _database.execute(
          'UPDATE $logTable SET state = ?, rejection = ? WHERE mutation_id = ?',
          <Object?>['rejected', outcome.rejection, mutation.mutationId],
        );
        rejectedCount++;
        _report(
          'DV-OFFLINE-003',
          'The server refused ${table.table}[${mutation.key}] '
              '(${outcome.rejection}); the write is in the dead letters.',
          DVLogLevel.warn,
        );
        _setState(mutation.key, DVSyncState.rejected);
        continue;
      }

      await _database.execute(
        'DELETE FROM $logTable WHERE mutation_id = ?',
        <Object?>[mutation.mutationId],
      );
      applied++;

      final DVRecord? record = outcome.record;
      bool differs = outcome.discarded;
      if (record == null) {
        await _database.execute(
          'DELETE FROM $serverTable WHERE record_key = ?',
          <Object?>[jsonEncode(mutation.key)],
        );
      } else {
        await _setServer(record);
        differs = differs || !_sameValues(record.values, mutation.values);
        // The device copy follows what the server kept — unless a later write
        // to the same record is still queued, which the device must go on
        // showing until it too has been replayed.
        if (differs && !laterForKey) {
          final DVRecord? local = await table.read(record.key);
          await table.write(record.values,
              base: local, onConflict: DVConflict.lastWriteWins);
        }
      }
      if (differs) conflicted++;
      _setState(
        mutation.key,
        laterForKey
            ? DVSyncState.pending
            : differs
                ? DVSyncState.conflicted
                : DVSyncState.synced,
      );
    }

    return DVReplayResult(
        applied: applied, rejected: rejectedCount, conflicted: conflicted);
  }

  // --- internals ------------------------------------------------------------

  Future<void> _ensureCapacity() async {
    final List<Map<String, Object?>> counted = await _database.query(
      'SELECT COUNT(*) AS n FROM $logTable WHERE state = ?',
      <Object?>['pending'],
    );
    final int count = (counted.first['n']! as num).toInt();
    if (count >= policy.maxMutations) {
      final DVOfflineQueueFullError error = DVOfflineQueueFullError(
          table: table.table, pending: count, limit: policy.maxMutations);
      _report(error.code, error.toString(), DVLogLevel.error);
      throw error;
    }
    final List<DVMutation> oldest = await _mutations('pending', limit: 1);
    if (oldest.isNotEmpty &&
        clock.deviceNow.difference(oldest.first.deviceTime) > policy.maxAge) {
      final DVOfflineQueueFullError error = DVOfflineQueueFullError(
        table: table.table,
        pending: count,
        limit: policy.maxMutations,
        oldest: oldest.first.deviceTime,
        maxAge: policy.maxAge,
      );
      _report(error.code, error.toString(), DVLogLevel.error);
      throw error;
    }
  }

  Future<void> _append(String op, Object key, Map<String, Object?> values) async {
    final int sequence = ++_sequence;
    final DateTime device = clock.deviceNow;
    final DateTime corrected = device.add(clock.offset);
    final String id = '${device.microsecondsSinceEpoch}-$sequence-'
        '${_random.nextInt(1 << 32).toRadixString(16)}';
    await _database.execute(
      'INSERT INTO $logTable '
      '(seq, mutation_id, op, record_key, payload, state, rejection) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        sequence,
        id,
        op,
        jsonEncode(key),
        jsonEncode(<String, Object?>{
          'values': values,
          'device': device.microsecondsSinceEpoch,
          'corrected': corrected.microsecondsSinceEpoch,
        }),
        'pending',
        null,
      ],
    );
    _setState(key, DVSyncState.pending);
  }

  Future<List<DVMutation>> _mutations(String state, {int? limit}) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT * FROM $logTable WHERE state = ? ORDER BY seq'
      '${limit == null ? '' : ' LIMIT $limit'}',
      <Object?>[state],
    );
    return <DVMutation>[
      for (final Map<String, Object?> row in rows) _fromRow(row),
    ];
  }

  DVMutation _fromRow(Map<String, Object?> row) {
    final Map<String, Object?> payload =
        jsonDecode('${row['payload']}') as Map<String, Object?>;
    return DVMutation(
      mutationId: '${row['mutation_id']}',
      sequence: (row['seq']! as num).toInt(),
      table: table.table,
      op: '${row['op']}',
      key: jsonDecode('${row['record_key']}') as Object,
      values: (payload['values']! as Map<String, Object?>),
      deviceTime: DateTime.fromMicrosecondsSinceEpoch(
          (payload['device']! as num).toInt(),
          isUtc: true),
      correctedTime: DateTime.fromMicrosecondsSinceEpoch(
          (payload['corrected']! as num).toInt(),
          isUtc: true),
      rejection: row['rejection'] as String?,
    );
  }

  Future<DVRecord?> _server(Object key) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT version, payload FROM $serverTable WHERE record_key = ?',
      <Object?>[jsonEncode(key)],
    );
    if (rows.isEmpty) return null;
    return DVRecord(
      key: key,
      version: (rows.first['version']! as num).toInt(),
      values: jsonDecode('${rows.first['payload']}') as Map<String, Object?>,
    );
  }

  Future<void> _setServer(DVRecord record) async {
    final String encoded = jsonEncode(record.key);
    await _database.execute(
        'DELETE FROM $serverTable WHERE record_key = ?', <Object?>[encoded]);
    await _database.execute(
      'INSERT INTO $serverTable (record_key, version, payload) VALUES (?, ?, ?)',
      <Object?>[encoded, record.version, jsonEncode(record.values)],
    );
  }

  void _setState(Object key, DVSyncState state) {
    _states[key] = state;
    _changes.add((key, state));
  }

  void _report(String code, String message, DVLogLevel level) {
    if (code == 'DV-OFFLINE-001' && reported.contains(code)) return;
    reported.add(code);
    DVObservability.log(message,
        level: level,
        code: code,
        context: <String, Object?>{'table': table.table});
  }

  static bool _sameValues(Map<String, Object?> a, Map<String, Object?> b) {
    for (final String key in <String>{...a.keys, ...b.keys}) {
      if ('${a[key]}' != '${b[key]}') return false;
    }
    return true;
  }
}
