/// The backfill phase of an expand/contract, and its verification.
///
/// Existing rows are copied from the old column to the new one in chunks by
/// key, and every chunk is recorded as it is copied: which keys it covered and
/// how many rows. That record is what makes the job resumable -- a restart
/// carries on after the last recorded chunk -- and it is what verification
/// walks, so the chunks compared are the chunks the backfill used.
///
/// Verification hashes each chunk on both shapes. Not a count: counts agree
/// while values differ, which is the failure worth catching. Not one hash over
/// the table: that can only say something somewhere is wrong. A per-chunk hash
/// names the chunk (`DV-SCHEMA-004`), so it can be read, fixed and verified
/// again alone.
library dartvel_core.schema.backfill;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../dartvel.dart' show DVQueues;
import '../database/adapter.dart';
import 'schema_planner.dart' show DVSchemaFinding;

/// How big the database is, which sets where a backfill's rate starts.
enum DVDatabaseTier {
  small(500),
  standard(2000),
  large(10000);

  const DVDatabaseTier(this.startingRate);

  /// Rows per second a backfill starts at. A starting point only.
  final int startingRate;
}

/// `dartvel.database.tier` and `dartvel.database.backfill`.
final class DVBackfillSettings {
  const DVBackfillSettings({
    this.tier = DVDatabaseTier.standard,
    this.targetReplicaLag = const Duration(seconds: 5),
    this.maxWriteLatencyIncrease = 0.10,
    this.floorRate,
    this.patience = const Duration(minutes: 15),
  });

  /// Reads the `dartvel.database` section of `pubspec.yaml`.
  ///
  /// A tier it does not know is refused rather than defaulted: `huge` read as
  /// `standard` would start a large database's backfill at a smaller one's
  /// pace and nobody would know why it took a week.
  factory DVBackfillSettings.fromConfig(Map<Object?, Object?>? database) {
    const DVBackfillSettings defaults = DVBackfillSettings();
    if (database == null) return defaults;
    final Object? tierName = database['tier'];
    DVDatabaseTier tier = defaults.tier;
    if (tierName != null) {
      tier = DVDatabaseTier.values.firstWhere(
        (DVDatabaseTier t) => t.name == '$tierName',
        orElse: () => throw FormatException(
          'dartvel.database.tier is small, standard or large.',
          '$tierName',
        ),
      );
    }
    final Object? backfill = database['backfill'];
    final Map<Object?, Object?> section = backfill is Map
        ? backfill
        : const <Object?, Object?>{};
    return DVBackfillSettings(
      tier: tier,
      targetReplicaLag: section['targetReplicaLag'] == null
          ? defaults.targetReplicaLag
          : dvParseSchemaDuration('${section['targetReplicaLag']}'),
      maxWriteLatencyIncrease: section['maxWriteLatencyIncrease'] == null
          ? defaults.maxWriteLatencyIncrease
          : _fraction(section['maxWriteLatencyIncrease']!),
      floorRate: (section['floorRate'] as num?)?.toDouble(),
      patience: section['patience'] == null
          ? defaults.patience
          : dvParseSchemaDuration('${section['patience']}'),
    );
  }

  final DVDatabaseTier tier;

  /// Replica lag above which the backfill halves its rate.
  final Duration targetReplicaLag;

  /// Write latency increase, as a fraction, above which it halves its rate.
  final double maxWriteLatencyIncrease;

  /// Rows per second below which the backfill counts as stuck. Defaults to a
  /// tenth of the tier's starting rate.
  ///
  /// The specification names the floor and the patience in `DV-SCHEMA-003`
  /// and gives neither a key; these are read from `dartvel.database.backfill`
  /// as `floorRate` and `patience`.
  final double? floorRate;

  /// How long it may stay below [floor] before that is reported
  /// (`DV-SCHEMA-003`).
  final Duration patience;

  double get floor => floorRate ?? tier.startingRate / 10;

  static double _fraction(Object value) {
    if (value is num) return value.toDouble();
    final String text = '$value'.trim();
    final bool percent = text.endsWith('%');
    final double? parsed = double.tryParse(
      percent ? text.substring(0, text.length - 1) : text,
    );
    if (parsed == null) throw FormatException('Not a percentage', text);
    return percent ? parsed / 100 : parsed;
  }
}

/// `5s`, `500ms`, `2m`, `1h`, `1d`.
Duration dvParseSchemaDuration(String text) {
  final RegExpMatch? match = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s*(ms|s|m|h|d)\s*$',
  ).firstMatch(text);
  if (match == null) throw FormatException('Not a duration', text);
  final double amount = double.parse(match.group(1)!);
  const Map<String, int> micros = <String, int>{
    'ms': 1000,
    's': 1000000,
    'm': 60000000,
    'h': 3600000000,
    'd': 86400000000,
  };
  return Duration(microseconds: (amount * micros[match.group(2)]!).round());
}

/// What the database is doing, measured by whoever can measure it.
final class DVBackfillLoad {
  const DVBackfillLoad({this.replicaLag, this.writeLatencyIncrease});

  final Duration? replicaLag;

  /// Write latency now against before the backfill, as a fraction.
  final double? writeLatencyIncrease;
}

/// Paces a backfill against the database rather than at a fixed speed.
///
/// Halves the rate when replica lag or write latency crosses its budget and
/// steps back up by a tenth of the starting rate while both stay under it, so
/// the backfill finds the speed the database can take and gives it back when
/// traffic arrives.
final class DVBackfillThrottle {
  DVBackfillThrottle(this.settings)
    : _rate = settings.tier.startingRate.toDouble();

  final DVBackfillSettings settings;
  double _rate;
  DateTime? _belowFloorSince;
  bool _reported = false;

  /// Rows per second.
  double get rate => _rate;

  /// Adjusts the rate for [load]; returns `DV-SCHEMA-003` once, when the rate
  /// has stayed below the floor for longer than the patience.
  DVSchemaFinding? observe(DVBackfillLoad load, DateTime now) {
    final Duration? lag = load.replicaLag;
    final double? latency = load.writeLatencyIncrease;
    final bool over =
        (lag != null && lag > settings.targetReplicaLag) ||
        (latency != null && latency > settings.maxWriteLatencyIncrease);
    _rate = over
        ? math.max(1, _rate / 2)
        : _rate + settings.tier.startingRate / 10;

    if (_rate >= settings.floor) {
      _belowFloorSince = null;
      _reported = false;
      return null;
    }
    final DateTime since = _belowFloorSince ??= now;
    if (_reported || now.difference(since) < settings.patience) return null;
    _reported = true;
    return DVSchemaFinding(
      'DV-SCHEMA-003',
      'The backfill has run below its floor of ${settings.floor} rows/s '
          'since ${since.toIso8601String()}, longer than its patience of '
          '${settings.patience}. The database cannot take it at this load.',
    );
  }
}

/// One recorded chunk.
final class DVBackfillChunk {
  const DVBackfillChunk({
    required this.index,
    required this.first,
    required this.last,
    required this.rows,
    required this.state,
    required this.everMatched,
  });

  final int index;

  /// The first and last key the chunk covered, inclusive.
  final Object? first;
  final Object? last;
  final int rows;

  /// `backfilled`, `verified` or `mismatched`.
  final String state;

  /// Whether this chunk has ever verified clean.
  final bool everMatched;

  /// How findings name it, e.g. `#1 [11..20]`.
  String get name => '#$index [$first..$last]';
}

/// Where a backfill has got to.
final class DVBackfillProgress {
  const DVBackfillProgress({required this.complete, required this.chunks});

  /// No rows remained past the last chunk when it last looked.
  final bool complete;
  final List<DVBackfillChunk> chunks;

  int get rows =>
      chunks.fold(0, (int sum, DVBackfillChunk chunk) => sum + chunk.rows);

  List<DVBackfillChunk> get mismatched =>
      chunks.where((DVBackfillChunk c) => c.state == 'mismatched').toList();

  List<DVBackfillChunk> get unverified =>
      chunks.where((DVBackfillChunk c) => c.state == 'backfilled').toList();

  /// Every chunk backfilled and every chunk verified clean.
  bool get verified =>
      complete && chunks.every((DVBackfillChunk c) => c.state == 'verified');
}

/// Why a run stopped.
enum DVBackfillStop { complete, paused, maxChunks }

/// What one run did.
final class DVBackfillRun {
  const DVBackfillRun({
    required this.rows,
    required this.chunks,
    required this.stoppedBecause,
    required this.findings,
  });

  final int rows;
  final int chunks;
  final DVBackfillStop stoppedBecause;
  final List<DVSchemaFinding> findings;

  bool get complete => stoppedBecause == DVBackfillStop.complete;
}

/// Copies [source] into [target] for every row of [table], chunked by [key].
final class DVBackfill {
  DVBackfill({
    required this.database,
    required this.id,
    required this.table,
    required this.key,
    required this.source,
    required this.target,
    required this.convert,
    this.chunkSize = 1000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    // Identifiers are written into SQL; values never are. An identifier that
    // is not one is refused before a statement is built from it.
    for (final String name in <String>[table, key, source, target]) {
      if (!_identifier.hasMatch(name)) {
        throw ArgumentError.value(name, 'identifier', 'not an identifier');
      }
    }
    if (chunkSize < 1) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be at least 1');
    }
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static const String _chunks = 'dv_schema_backfill_chunks';
  static const String _state = 'dv_schema_backfill_state';

  final DVDatabaseAdapter database;

  /// Names the backfill in its records; stable across restarts.
  final String id;
  final String table;
  final String key;
  final String source;
  final String target;

  /// What the new shape should hold for a value of the old one.
  ///
  /// Used to copy and, separately, to compute what verification expects, so
  /// a row changed after it was copied is caught.
  final Object? Function(Object? source) convert;

  final int chunkSize;
  final DateTime Function() _clock;
  bool _prepared = false;

  Future<void> _prepare() async {
    if (_prepared) return;
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $_chunks (backfill TEXT, chunk INTEGER, '
      'first_key TEXT, last_key TEXT, row_count INTEGER, state TEXT, '
      'ever_matched INTEGER)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $_state (backfill TEXT, paused INTEGER, '
      'complete INTEGER)',
    );
    final List<Map<String, Object?>> existing = await database.query(
      'SELECT backfill FROM $_state WHERE backfill = ?',
      <Object?>[id],
    );
    if (existing.isEmpty) {
      await database.execute(
        'INSERT INTO $_state (backfill, paused, complete) VALUES (?, ?, ?)',
        <Object?>[id, 0, 0],
      );
    }
    _prepared = true;
  }

  Future<Map<String, Object?>> _readState() async {
    await _prepare();
    return (await database.query(
      'SELECT paused, complete FROM $_state WHERE backfill = ?',
      <Object?>[id],
    )).single;
  }

  Future<void> _setState(String column, bool value) async {
    await _prepare();
    await database.execute(
      'UPDATE $_state SET $column = ? WHERE backfill = ?',
      <Object?>[value ? 1 : 0, id],
    );
  }

  /// Stops the backfill at its next chunk boundary, across restarts.
  Future<void> pause() => _setState('paused', true);

  Future<void> resume() => _setState('paused', false);

  Future<bool> get paused async => _truthy((await _readState())['paused']);

  /// Copies the next chunk, or returns null when no rows remain.
  Future<DVBackfillChunk?> backfillNext() async {
    await _prepare();
    final List<Map<String, Object?>> last = await database.query(
      'SELECT chunk, last_key FROM $_chunks WHERE backfill = ? '
      'ORDER BY chunk DESC LIMIT 1',
      <Object?>[id],
    );
    final List<Map<String, Object?>> rows = last.isEmpty
        ? await database.query(
            'SELECT $key, $source FROM $table ORDER BY $key LIMIT ?',
            <Object?>[chunkSize],
          )
        : await database.query(
            'SELECT $key, $source FROM $table WHERE $key > ? '
            'ORDER BY $key LIMIT ?',
            <Object?>[_decodeKey(last.single['last_key']), chunkSize],
          );
    if (rows.isEmpty) {
      await _setState('complete', true);
      return null;
    }
    await _setState('complete', false);

    for (final Map<String, Object?> row in rows) {
      await database.execute(
        'UPDATE $table SET $target = ? WHERE $key = ?',
        <Object?>[convert(row[source]), row[key]],
      );
    }
    // Recorded after the rows are written. A crash between the two copies the
    // chunk again on restart, which is harmless; recording first would skip
    // rows that were never copied.
    final DVBackfillChunk chunk = DVBackfillChunk(
      index: last.isEmpty ? 0 : (last.single['chunk']! as num).toInt() + 1,
      first: rows.first[key],
      last: rows.last[key],
      rows: rows.length,
      state: 'backfilled',
      everMatched: false,
    );
    await database.execute(
      'INSERT INTO $_chunks (backfill, chunk, first_key, last_key, row_count, '
      'state, ever_matched) VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        id,
        chunk.index,
        jsonEncode(chunk.first),
        jsonEncode(chunk.last),
        chunk.rows,
        chunk.state,
        0,
      ],
    );
    return chunk;
  }

  /// Copies chunks until none remain, the backfill is paused, or [maxChunks]
  /// have been copied, paced by [throttle] when there is one.
  Future<DVBackfillRun> run({
    int? maxChunks,
    DVBackfillThrottle? throttle,
    DVBackfillLoad Function()? load,
    Future<void> Function(Duration)? sleep,
  }) async {
    final Future<void> Function(Duration) wait =
        sleep ?? (Duration d) => Future<void>.delayed(d);
    final List<DVSchemaFinding> findings = <DVSchemaFinding>[];
    int rows = 0;
    int chunks = 0;
    DVBackfillRun stop(DVBackfillStop why) => DVBackfillRun(
      rows: rows,
      chunks: chunks,
      stoppedBecause: why,
      findings: List<DVSchemaFinding>.unmodifiable(findings),
    );
    while (true) {
      if (await paused) return stop(DVBackfillStop.paused);
      final DVBackfillChunk? chunk = await backfillNext();
      if (chunk == null) return stop(DVBackfillStop.complete);
      rows += chunk.rows;
      chunks++;
      if (throttle != null) {
        // Measured after the chunk, so the pause that follows answers what
        // the chunk did to the database.
        final DVSchemaFinding? finding = throttle.observe(
          load?.call() ?? const DVBackfillLoad(),
          _clock(),
        );
        if (finding != null) findings.add(finding);
        await wait(
          Duration(
            microseconds: (chunk.rows / throttle.rate * 1000000).round(),
          ),
        );
      }
      if (maxChunks != null && chunks >= maxChunks) {
        return stop(DVBackfillStop.maxChunks);
      }
    }
  }

  /// A chunk boundary as it was read from the table.
  ///
  /// Keys are stored as JSON in a text column. A key column may hold numbers
  /// or text, and a text column on its own would hand back `'10'` for `10`:
  /// on SQLite that key then compares greater than every number, so the next
  /// chunk would find no rows and the backfill would stop with rows uncopied.
  static Object? _decodeKey(Object? stored) =>
      stored == null ? null : jsonDecode('$stored');

  /// Every recorded chunk and whether the backfill is complete.
  Future<DVBackfillProgress> progress() async {
    final Map<String, Object?> state = await _readState();
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT chunk, first_key, last_key, row_count, state, ever_matched '
      'FROM $_chunks WHERE backfill = ? ORDER BY chunk',
      <Object?>[id],
    );
    return DVBackfillProgress(
      complete: _truthy(state['complete']),
      chunks: <DVBackfillChunk>[
        for (final Map<String, Object?> row in rows)
          DVBackfillChunk(
            index: (row['chunk']! as num).toInt(),
            first: _decodeKey(row['first_key']),
            last: _decodeKey(row['last_key']),
            rows: (row['row_count']! as num).toInt(),
            state: '${row['state']}',
            everMatched: _truthy(row['ever_matched']),
          ),
      ],
    );
  }

  /// Hashes every recorded chunk -- or only [chunk] -- on both shapes.
  ///
  /// `DV-SCHEMA-004` for each chunk whose hashes differ, naming it; and
  /// `DV-SCHEMA-007` as well when that chunk had verified clean before, since
  /// a chunk that agreed and then diverged was written to one shape and not
  /// the other.
  Future<List<DVSchemaFinding>> verify({int? chunk}) async {
    final List<DVSchemaFinding> findings = <DVSchemaFinding>[];
    for (final DVBackfillChunk recorded in (await progress()).chunks) {
      if (chunk != null && recorded.index != chunk) continue;
      final List<Map<String, Object?>> rows = await database.query(
        'SELECT $key, $source, $target FROM $table '
        'WHERE $key >= ? AND $key <= ? ORDER BY $key',
        <Object?>[recorded.first, recorded.last],
      );
      final String expected = _hash(<List<Object?>>[
        for (final Map<String, Object?> row in rows)
          <Object?>[row[key], convert(row[source])],
      ]);
      final String actual = _hash(<List<Object?>>[
        for (final Map<String, Object?> row in rows)
          <Object?>[row[key], row[target]],
      ]);
      final bool match = expected == actual;
      await database.execute(
        'UPDATE $_chunks SET state = ?, ever_matched = ? '
        'WHERE backfill = ? AND chunk = ?',
        <Object?>[
          match ? 'verified' : 'mismatched',
          (recorded.everMatched || match) ? 1 : 0,
          id,
          recorded.index,
        ],
      );
      if (match) continue;
      findings.add(
        DVSchemaFinding(
          'DV-SCHEMA-004',
          'Chunk ${recorded.name} of $id does not match: $table.$target differs '
              'from $table.$source for at least one of its rows. The read switch is '
              'refused until it is fixed and verified again.',
          chunk: recorded.name,
        ),
      );
      if (recorded.everMatched) {
        findings.add(
          DVSchemaFinding(
            'DV-SCHEMA-007',
            'Chunk ${recorded.name} of $id verified clean before and differs '
                'now, so a write reached one shape and not the other.',
            chunk: recorded.name,
          ),
        );
      }
    }
    return findings;
  }

  static bool _truthy(Object? value) =>
      value == true || (value is num && value != 0) || value == '1';

  static String _hash(List<List<Object?>> rows) => sha256
      .convert(
        utf8.encode(
          rows
              .map(
                (List<Object?> row) => jsonEncode(
                  row,
                  toEncodable: (Object? value) => value is DateTime
                      ? value.toUtc().toIso8601String()
                      : '$value',
                ),
              )
              .join('\n'),
        ),
      )
      .toString();
}

/// The payload of a backfill slice queued on [DVQueues].
final class DVSchemaBackfillRequest {
  const DVSchemaBackfillRequest({required this.id, required this.chunks});

  final String id;

  /// Chunks this job copies before it queues the next slice.
  final int chunks;
}

/// Backfills run as ordinary jobs on the existing queue machinery.
///
/// A job copies a slice of chunks and queues the next slice, so a worker
/// restart loses at most a slice -- which the recorded chunks make harmless --
/// and a paused backfill simply stops queueing itself.
final class DVSchemaBackfills {
  final Map<String, DVBackfill> _backfills = <String, DVBackfill>{};
  final Map<String, DVBackfillThrottle> _throttles =
      <String, DVBackfillThrottle>{};
  DVQueues _queues = const DVQueues();
  String _queue = 'default';

  /// Findings raised by jobs, most recent last.
  final List<DVSchemaFinding> findings = <DVSchemaFinding>[];

  void add(DVBackfill backfill, {DVBackfillThrottle? throttle}) {
    _backfills[backfill.id] = backfill;
    if (throttle != null) _throttles[backfill.id] = throttle;
  }

  DVBackfill _find(String id) {
    final DVBackfill? backfill = _backfills[id];
    if (backfill == null) {
      throw StateError(
        'No backfill is registered as $id. Add it to DVSchemaBackfills on '
        'the worker before its jobs run.',
      );
    }
    return backfill;
  }

  void registerJobs(DVQueues queues, {String queue = 'default'}) {
    _queues = queues;
    _queue = queue;
    queues.register<DVSchemaBackfillRequest>((
      DVSchemaBackfillRequest request,
    ) async {
      final DVBackfillRun run = await _find(
        request.id,
      ).run(maxChunks: request.chunks, throttle: _throttles[request.id]);
      findings.addAll(run.findings);
      if (run.stoppedBecause == DVBackfillStop.maxChunks) {
        await start(request.id, chunksPerJob: request.chunks);
      }
    });
  }

  Future<void> start(String id, {int chunksPerJob = 10}) async {
    _find(id);
    await _queues.dispatch<DVSchemaBackfillRequest>(
      DVSchemaBackfillRequest(id: id, chunks: chunksPerJob),
      queue: _queue,
    );
  }

  Future<void> pause(String id) => _find(id).pause();

  Future<void> resume(String id, {int chunksPerJob = 10}) async {
    await _find(id).resume();
    await start(id, chunksPerJob: chunksPerJob);
  }
}
