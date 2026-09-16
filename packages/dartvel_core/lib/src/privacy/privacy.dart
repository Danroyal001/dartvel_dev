/// Data compliance and lifecycle: erasure, subject-access export, retention,
/// and the evidence each leaves behind.
///
/// Everything here walks one declaration — which rows belong to whom — and
/// every failure it guards against is a silent one: an erasure that reports
/// success while a soft-deleted row, an old value in a change log or a
/// ciphertext survives; an export that forgets a relation or carries another
/// person's identifier; a retention sweep that deletes what a longer
/// retention holds; a receipt that still verifies after it was edited.
library dartvel_core.privacy;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../dartvel.dart';
import '../database/framework_tables.dart' show dvEnsureFrameworkTable;

enum _DVSubjectKind { self, field, through }

/// How a model's rows reach the person they belong to.
///
/// A walk over the model graph needs this and nothing else: erasure and
/// export both start from a subject and visit every row whose path leads to
/// it.
final class DVSubject {
  const DVSubject._self()
    : _kind = _DVSubjectKind.self,
      column = null,
      parent = null;

  /// The row's column [column] holds the subject's id.
  const DVSubject.field(String this.column)
    : _kind = _DVSubjectKind.field,
      parent = null;

  /// The row's column [column] holds the key of a row of the model named
  /// [parent], and that row belongs to the subject — an order line through
  /// its order.
  const DVSubject.through(String this.column, {required String this.parent})
    : _kind = _DVSubjectKind.through;

  /// The row is the subject: its key is the subject's id.
  static const DVSubject self = DVSubject._self();

  final _DVSubjectKind _kind;
  final String? column;
  final String? parent;

  @override
  String toString() => switch (_kind) {
    _DVSubjectKind.self => 'DVSubject.self',
    _DVSubjectKind.field => 'DVSubject.field($column)',
    _DVSubjectKind.through => 'DVSubject.through($column -> $parent)',
  };
}

/// What a retention sweep does to an expired row.
enum DVRetentionAction { delete, anonymize }

/// How long a model's rows are kept before a sweep removes them.
final class DVRetention {
  /// Kept [days] after the timestamp in column [from], then [then].
  ///
  /// [from] may be left out on a model annotation, where the generator
  /// resolves it to the model's createdAt field and refuses a model without
  /// one. A [DVPrivacyModel] refuses it missing: a sweep with no timestamp to
  /// measure an age from deletes nothing.
  const DVRetention.days(
    int this.days, {
    this.from,
    this.then = DVRetentionAction.delete,
  });

  /// `then: DVRetention.delete`: an expired row is deleted.
  static const DVRetentionAction delete = DVRetentionAction.delete;

  /// `then: DVRetention.anonymize`: an expired row stays and its personal
  /// fields are replaced.
  static const DVRetentionAction anonymize = DVRetentionAction.anonymize;

  const DVRetention._indefinite()
    : days = null,
      from = null,
      then = DVRetentionAction.delete;

  /// Kept for ever — deliberately, and declared so.
  static const DVRetention indefinite = DVRetention._indefinite();

  final int? days;
  final String? from;
  final DVRetentionAction then;

  bool get isIndefinite => days == null;
  Duration? get duration => days == null ? null : Duration(days: days!);
}

/// A retention an erasure cannot override: the row is kept and its personal
/// fields are anonymized, and [because] is the answer to "why do you still
/// have my invoice".
final class DVRetain {
  const DVRetain({required this.years, required this.because});

  final int years;
  final String because;

  Duration get duration => Duration(days: years * 365);
}

/// One model as the privacy walk sees it.
class DVPrivacyModel {
  DVPrivacyModel({
    required this.name,
    required this.table,
    this.subject,
    Set<String> personal = const <String>{},
    Set<String> anonymizeOnErase = const <String>{},
    Set<String> otherSubjects = const <String>{},
    this.retain,
    this.retention,
  }) : personal = Set<String>.unmodifiable(personal),
       anonymizeOnErase = Set<String>.unmodifiable(anonymizeOnErase),
       otherSubjects = Set<String>.unmodifiable(otherSubjects) {
    final DVRetention? dated = retention;
    if (dated != null && !dated.isIndefinite && dated.from == null) {
      throw ArgumentError.value(
        name,
        'retention',
        'keeps rows ${dated.days} days and names no from column to measure '
            'that from, so no sweep would ever find a row expired',
      );
    }
    for (final String field in <String>{
      ...personal,
      ...anonymizeOnErase,
      ...otherSubjects,
      if (subject?.column != null) subject!.column!,
      if (retention?.from != null) retention!.from!,
    }) {
      if (!table.columns.contains(field)) {
        throw ArgumentError.value(
          field,
          'field',
          'is not a column of ${table.table}',
        );
      }
    }
  }

  final String name;
  final DVRecordTable table;

  /// Null for a model that holds nobody's data, such as a currency table.
  final DVSubject? subject;

  /// Personal fields beyond the table's sensitive ones.
  final Set<String> personal;

  /// Fields replaced with [DVPrivacy.tombstone] on erasure rather than the row
  /// being deleted.
  final Set<String> anonymizeOnErase;

  /// Columns naming a different subject. An export carries the requesting
  /// subject's contribution only, so these are cleared in it.
  final Set<String> otherSubjects;

  final DVRetain? retain;
  final DVRetention? retention;

  /// Every field that is personal data: the declared ones and the sensitive
  /// ones.
  Set<String> get personalFields => <String>{...personal, ...table.sensitive};
}

/// A problem with the declarations, found before anything runs.
class DVPrivacyFinding {
  const DVPrivacyFinding({
    required this.code,
    required this.model,
    required this.message,
    required this.level,
  });

  final String code;
  final String model;
  final String message;
  final DVLogLevel level;

  @override
  String toString() => '$code ($model): $message';
}

/// Declarations an erasure could not honour (`DV-PRIVACY-001`).
class DVPrivacyDeclarationError implements Exception {
  DVPrivacyDeclarationError(this.findings);

  final List<DVPrivacyFinding> findings;

  @override
  String toString() => 'DVPrivacyDeclarationError: ${findings.join('; ')}';
}

/// The subject a walk is about: its id, and the pseudonym every record the
/// walk leaves behind uses instead.
class DVPrivacySubjectRef {
  const DVPrivacySubjectRef({required this.id, required this.pseudonym});

  final Object id;
  final String pseudonym;
}

/// A store outside the database that holds a subject's data — a search index,
/// a cache, file storage, a device's offline copy.
///
/// An erasure that cannot reach one is reported as incomplete
/// (`DV-PRIVACY-009`), never as a success.
abstract interface class DVPrivacyAdapter {
  String get name;
  Future<void> erase(DVPrivacySubjectRef subject);
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject);
}

/// A row an erasure reached, identified by its table and key.
class DVErasedRecord {
  const DVErasedRecord({required this.table, required this.key});

  final DVRecordTable table;
  final Object key;
}

/// A store holding copies of individual rows -- a change capture log, a
/// warehouse -- that finds them by the rows themselves rather than by the
/// subject.
///
/// Such a store cannot walk the subject paths once the rows are gone, so the
/// erasure hands it the rows it reached, resolved before anything was
/// changed. [erase] is not called for it.
abstract interface class DVPrivacyRecordAdapter implements DVPrivacyAdapter {
  Future<void> eraseRecords(
    DVPrivacySubjectRef subject,
    List<DVErasedRecord> records,
  );
}

/// A row an erasure kept under a declared retention.
class DVKeptRecord {
  const DVKeptRecord({
    required this.model,
    required this.key,
    required this.because,
  });

  final String model;
  final Object key;
  final String because;

  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    'key': '$key',
    'because': because,
  };
}

/// A signed account of one erasure, naming the subject by pseudonym only.
class DVErasureReceipt {
  const DVErasureReceipt({required this.payload, required this.signature});

  final Map<String, Object?> payload;

  /// Lowercase hex HMAC-SHA256 over the canonical JSON of [payload].
  final String signature;

  Map<String, Object?> toJson() => <String, Object?>{
    'payload': payload,
    'signature': signature,
  };
}

class DVErasureResult {
  DVErasureResult._({
    required this.deleted,
    required this.anonymized,
    required this.kept,
    required this.unreached,
    required this.late,
    required this.codes,
    required this.receipt,
  });

  final Map<String, int> deleted;
  final Map<String, int> anonymized;
  final List<DVKeptRecord> kept;

  /// Adapters the erasure could not reach.
  final List<String> unreached;
  final bool late;
  final List<String> codes;
  final DVErasureReceipt receipt;

  /// Whether every store the walk covers was reached.
  bool get complete => unreached.isEmpty;
}

class DVExportArchive {
  DVExportArchive._({
    required this.records,
    required this.adapters,
    required this.unreached,
    required this.codes,
  });

  final Map<String, List<Map<String, Object?>>> records;
  final Map<String, Map<String, Object?>> adapters;
  final List<String> unreached;
  final List<String> codes;

  String toJson() =>
      jsonEncode(<String, Object?>{'records': records, 'adapters': adapters});
}

class DVRetentionPlan {
  DVRetentionPlan._(this.deletions, this.anonymizations, this.held);

  final Map<String, int> deletions;
  final Map<String, int> anonymizations;

  /// Expired under the model's retention, but held by a longer one.
  final Map<String, int> held;
}

class DVRetentionSweep {
  DVRetentionSweep._({
    required this.deleted,
    required this.anonymized,
    required this.held,
    this.skipped = const <String, int>{},
    required this.remaining,
    required this.codes,
  });

  final Map<String, int> deleted;
  final Map<String, int> anonymized;
  final Map<String, int> held;

  /// Rows rewritten between the sweep's read and its write, which it left
  /// alone: deleting or anonymizing one from the stale read would remove a row
  /// that may have been renewed. Each is re-read, and one still expired is
  /// counted in [remaining].
  final Map<String, int> skipped;

  /// Expired rows this run did not reach, including skipped rows still
  /// expired; the next run reads them again and continues.
  final int remaining;
  final List<String> codes;
}

class DVErasureReplay {
  DVErasureReplay._(this.records, this.codes);

  final int records;
  final List<String> codes;
}

/// The payload of an erasure queued on [DVQueues].
class DVPrivacyErasureRequest {
  const DVPrivacyErasureRequest({
    required this.subject,
    required this.reason,
    this.requestedAt,
    this.requestedBy,
    this.runBy,
  });

  final Object subject;
  final String reason;
  final DateTime? requestedAt;
  final String? requestedBy;
  final String? runBy;

  /// The name the request is stored under in a durable queue.
  static const String codecName = 'dartvel.privacy.erasure';

  /// Stores [request]. A subject that is a string, a number or a boolean
  /// keeps its type: an integer key read back as a string is compared as a
  /// string by some databases and matches no row.
  static Map<String, Object?> encode(DVPrivacyErasureRequest request) {
    final Object subject = request.subject;
    return <String, Object?>{
      'subject': subject is String || subject is num || subject is bool
          ? subject
          : '$subject',
      'reason': request.reason,
      'requestedAt': request.requestedAt?.toUtc().toIso8601String(),
      'requestedBy': request.requestedBy,
      'runBy': request.runBy,
    };
  }

  static DVPrivacyErasureRequest decode(Map<String, Object?> json) {
    final Object? at = json['requestedAt'];
    return DVPrivacyErasureRequest(
      subject: json['subject'] ?? '',
      reason: '${json['reason']}',
      requestedAt: at is String ? DateTime.parse(at) : null,
      requestedBy: json['requestedBy'] as String?,
      runBy: json['runBy'] as String?,
    );
  }
}

/// The payload of a retention sweep queued on [DVQueues].
class DVPrivacyRetentionRequest {
  const DVPrivacyRetentionRequest({this.batchSize = 500, this.maxBatches});

  final int batchSize;
  final int? maxBatches;

  /// The name the request is stored under in a durable queue.
  static const String codecName = 'dartvel.privacy.retention';

  static Map<String, Object?> encode(DVPrivacyRetentionRequest request) =>
      <String, Object?>{
        'batchSize': request.batchSize,
        'maxBatches': request.maxBatches,
      };

  static DVPrivacyRetentionRequest decode(Map<String, Object?> json) =>
      DVPrivacyRetentionRequest(
        batchSize: (json['batchSize'] as num?)?.toInt() ?? 500,
        maxBatches: (json['maxBatches'] as num?)?.toInt(),
      );
}

/// What a deadline check found and did: [open] erasures requested and not
/// yet completed, [overdue] of them past the deadline, and the [results] of
/// the ones it ran.
class DVErasureDeadlines {
  const DVErasureDeadlines({
    required this.open,
    required this.overdue,
    required this.results,
  });

  final int open;
  final int overdue;
  final List<DVErasureResult> results;
}

/// Erasure, export and retention over a set of declared models.
class DVPrivacy {
  DVPrivacy({
    required List<DVPrivacyModel> models,
    required this.database,
    required List<int> signingKey,
    List<DVPrivacyAdapter> adapters = const <DVPrivacyAdapter>[],
    this.deadline = const Duration(days: 30),
    DateTime Function()? now,
  }) : models = List<DVPrivacyModel>.unmodifiable(models),
       adapters = List<DVPrivacyAdapter>.unmodifiable(adapters),
       _key = List<int>.unmodifiable(signingKey),
       _now = now ?? DateTime.now {
    if (signingKey.length < 32) {
      throw ArgumentError.value(
        signingKey.length,
        'signingKey',
        'must be at least 32 bytes; it signs receipts and derives pseudonyms',
      );
    }
    final Set<String> names = <String>{};
    for (final DVPrivacyModel model in models) {
      if (!names.add(model.name)) {
        throw ArgumentError.value(model.name, 'name', 'is declared twice');
      }
    }
    for (final DVPrivacyModel model in models) {
      final String? parent = model.subject?.parent;
      if (parent != null && !names.contains(parent)) {
        throw ArgumentError.value(
          parent,
          'parent',
          'of ${model.name} is not a declared model',
        );
      }
    }
    final List<DVPrivacyFinding> errors = <DVPrivacyFinding>[
      for (final DVPrivacyFinding finding in check(models))
        if (finding.level == DVLogLevel.error) finding,
    ];
    if (errors.isNotEmpty) throw DVPrivacyDeclarationError(errors);
  }

  /// The value an anonymized field holds.
  static const String tombstone = '[erased]';

  final List<DVPrivacyModel> models;
  final DVDatabaseAdapter database;
  final List<DVPrivacyAdapter> adapters;

  /// How long an erasure has from its request, which is the regulation's
  /// clock rather than the framework's.
  final Duration deadline;

  final List<int> _key;
  final DateTime Function() _now;

  static const String tombstoneTable = 'dv_privacy_tombstones';

  /// Erasures requested and not yet completed, one row per subject, keyed by
  /// pseudonym. It holds the subject's id because running the erasure needs
  /// it, which is what the queued job holds too; the row goes when an
  /// erasure of the subject completes.
  static const String openErasuresTable = 'dv_privacy_open_erasures';

  /// Every export and erasure, through Record History, by pseudonym.
  late final DVRecordTable requests = DVRecordTable(
    table: 'dv_privacy_requests',
    key: 'id',
    columns: const <String>[
      'id',
      'kind',
      'subject',
      'reason',
      'requested_by',
      'run_by',
      'requested_at',
      'completed_at',
      'covered',
      'kept',
      'complete',
    ],
    types: const <String, String>{
      'id': 'TEXT',
      'kind': 'TEXT',
      'subject': 'TEXT',
      'reason': 'TEXT',
      'requested_by': 'TEXT',
      'run_by': 'TEXT',
      'requested_at': 'TEXT',
      'completed_at': 'TEXT',
      'covered': 'TEXT',
      'kept': 'INTEGER',
      'complete': 'INTEGER',
    },
    history: const DVHistory(keep: Duration(days: 3650)),
    versioned: false,
    database: database,
  );

  /// The declarations, checked. `DV-PRIVACY-001` for personal data no subject
  /// path reaches; `DV-PRIVACY-002` for personal data with no retention.
  static List<DVPrivacyFinding> check(List<DVPrivacyModel> models) {
    final List<DVPrivacyFinding> findings = <DVPrivacyFinding>[];
    for (final DVPrivacyModel model in models) {
      final Set<String> personal = model.personalFields;
      if (personal.isEmpty) continue;
      if (model.subject == null) {
        findings.add(
          DVPrivacyFinding(
            code: 'DV-PRIVACY-001',
            model: model.name,
            message:
                '${model.name} carries personal data '
                '(${(personal.toList()..sort()).join(', ')}) and declares no '
                'subject path, so an erasure cannot reach it.',
            level: DVLogLevel.error,
          ),
        );
      }
      if (model.retention == null) {
        findings.add(
          DVPrivacyFinding(
            code: 'DV-PRIVACY-002',
            model: model.name,
            message:
                '${model.name} carries personal data and declares no '
                'retention, so it is kept indefinitely.',
            level: DVLogLevel.warn,
          ),
        );
      }
    }
    return findings;
  }

  /// Creates the walk's own tables: the request log, the tombstone log and
  /// the open erasures. The generated server runs it at start.
  Future<void> ensureSchema() async {
    await requests.ensureSchema();
    await dvEnsureFrameworkTable(
      database,
      'CREATE TABLE IF NOT EXISTS $tombstoneTable (subject TEXT, '
      'erased_at TEXT)',
    );
    await dvEnsureFrameworkTable(
      database,
      'CREATE TABLE IF NOT EXISTS $openErasuresTable ('
      'id VARCHAR(64) PRIMARY KEY, subject TEXT NOT NULL, '
      'reason TEXT NOT NULL, requested_by TEXT, '
      'requested_at VARCHAR(40) NOT NULL)',
    );
  }

  /// The id every record the walk leaves behind uses instead of [subject].
  String pseudonym(Object subject) => Hmac(
    sha256,
    _key,
  ).convert(utf8.encode('dv-privacy-subject:$subject')).toString();

  DVPrivacySubjectRef _ref(Object subject) =>
      DVPrivacySubjectRef(id: subject, pseudonym: pseudonym(subject));

  DVPrivacyModel _model(String name) =>
      models.firstWhere((DVPrivacyModel m) => m.name == name);

  // --- the walk -------------------------------------------------------------

  /// Every row of every subject-bearing model that belongs to [subject],
  /// resolved before anything is changed: a row reached through its parent
  /// has to be found while the parent still exists.
  Future<Map<String, List<DVRecord>>> _walk(Object subject) async {
    final Map<String, List<DVRecord>> rows = <String, List<DVRecord>>{};
    Future<List<DVRecord>> rowsFor(DVPrivacyModel model) async {
      final List<DVRecord>? known = rows[model.name];
      if (known != null) return known;
      final DVSubject path = model.subject!;
      final List<DVRecord> all = await model.table.all(withDeleted: true);
      final List<DVRecord> found;
      switch (path._kind) {
        case _DVSubjectKind.self:
          found = <DVRecord>[
            for (final DVRecord r in all)
              if ('${r.key}' == '$subject') r,
          ];
        case _DVSubjectKind.field:
          found = <DVRecord>[
            for (final DVRecord r in all)
              if ('${r.values[path.column]}' == '$subject') r,
          ];
        case _DVSubjectKind.through:
          final Set<String> parents = <String>{
            for (final DVRecord p in await rowsFor(_model(path.parent!)))
              '${p.key}',
          };
          found = <DVRecord>[
            for (final DVRecord r in all)
              if (parents.contains('${r.values[path.column]}')) r,
          ];
      }
      rows[model.name] = found;
      return found;
    }

    for (final DVPrivacyModel model in models) {
      if (model.subject != null) await rowsFor(model);
    }
    return rows;
  }

  // --- erasure --------------------------------------------------------------

  Future<DVErasureResult> erase({
    required Object subject,
    required String reason,
    DateTime? requestedAt,
    String? requestedBy,
    String? runBy,
  }) async {
    final DVPrivacySubjectRef ref = _ref(subject);
    final DateTime started = _now();
    final DateTime asked = requestedAt ?? started;
    final List<String> codes = <String>[];
    final Map<String, int> deleted = <String, int>{};
    final Map<String, int> anonymized = <String, int>{};
    final List<DVKeptRecord> kept = <DVKeptRecord>[];
    final List<String> unreached = <String>[];

    final bool late = started.difference(asked) > deadline;
    if (late) {
      _report(
        codes,
        'DV-PRIVACY-004',
        'An erasure requested ${asked.toIso8601String()} is past its '
            '${deadline.inDays}-day deadline; it is running now.',
        DVLogLevel.error,
        ref,
      );
    }

    final Map<String, List<DVRecord>> walk = await _walk(subject);
    // Whether a row, as it is now, still belongs to the subject: the walk
    // resolved it earlier, and a row moved to someone else since is theirs.
    bool belongs(DVPrivacyModel model, DVRecord row) {
      final DVSubject path = model.subject!;
      return switch (path._kind) {
        _DVSubjectKind.self => '${row.key}' == '$subject',
        _DVSubjectKind.field => '${row.values[path.column]}' == '$subject',
        _DVSubjectKind.through =>
          (walk[path.parent!] ?? const <DVRecord>[]).any(
            (DVRecord p) => '${p.key}' == '${row.values[path.column]}',
          ),
      };
    }

    final List<DVErasedRecord> reached = <DVErasedRecord>[];
    for (final DVPrivacyModel model in models) {
      for (final DVRecord row in walk[model.name] ?? const <DVRecord>[]) {
        final _DVRowOutcome? outcome = await _eraseRow(
          model,
          row,
          ref,
          capture: !_captureAdapterErases(model.table),
          belongs: (DVRecord now) => belongs(model, now),
        );
        if (outcome == null) continue;
        reached.add(DVErasedRecord(table: model.table, key: row.key));
        switch (outcome) {
          case _DVRowOutcome.deleted:
            deleted.update(model.name, (int n) => n + 1, ifAbsent: () => 1);
          case _DVRowOutcome.anonymized:
            anonymized.update(model.name, (int n) => n + 1, ifAbsent: () => 1);
          case _DVRowOutcome.kept:
            kept.add(
              DVKeptRecord(
                model: model.name,
                key: row.key,
                because: model.retain!.because,
              ),
            );
        }
      }
    }
    if (kept.isNotEmpty) {
      _report(
        codes,
        'DV-PRIVACY-003',
        '${kept.length} rows were kept under a declared retention and their '
            'personal fields anonymized.',
        DVLogLevel.info,
        ref,
      );
    }

    for (final DVPrivacyAdapter adapter in adapters) {
      try {
        if (adapter is DVPrivacyRecordAdapter) {
          await adapter.eraseRecords(ref, reached);
        } else {
          await adapter.erase(ref);
        }
      } on Object catch (error) {
        unreached.add(adapter.name);
        _report(
          codes,
          'DV-PRIVACY-009',
          'The erasure could not reach ${adapter.name}; the subject\'s data '
              'there was not removed ($error).',
          DVLogLevel.error,
          ref,
        );
      }
    }

    await database.execute(
      'INSERT INTO $tombstoneTable (subject, erased_at) VALUES (?, ?)',
      <Object?>[ref.pseudonym, started.toUtc().toIso8601String()],
    );

    final DateTime finished = _now();
    final Map<String, Object?> payload = <String, Object?>{
      'version': 1,
      'subject': ref.pseudonym,
      'reason': reason,
      'requested_at': asked.toUtc().toIso8601String(),
      'completed_at': finished.toUtc().toIso8601String(),
      'deleted': deleted,
      'anonymized': anonymized,
      'kept': <Map<String, Object?>>[
        for (final DVKeptRecord k in kept) k.toJson(),
      ],
      'unreached': unreached,
      'complete': unreached.isEmpty,
      'late': late,
    };
    final DVErasureReceipt receipt = DVErasureReceipt(
      payload: payload,
      signature: _sign(payload),
    );

    await _record(
      'erase',
      ref,
      reason: reason,
      requestedAt: asked,
      completedAt: finished,
      requestedBy: requestedBy,
      runBy: runBy,
      covered: <String>[
        for (final DVPrivacyModel m in models)
          if (m.subject != null) m.name,
        for (final DVPrivacyAdapter a in adapters) a.name,
      ],
      kept: kept.length,
      complete: unreached.isEmpty,
    );
    // An erasure an adapter missed stays open, so the deadline check runs it
    // again rather than the request being forgotten half done.
    if (unreached.isEmpty) {
      await database.execute(
        'DELETE FROM $openErasuresTable WHERE id = ?',
        <Object?>[ref.pseudonym],
      );
    }

    return DVErasureResult._(
      deleted: deleted,
      anonymized: anonymized,
      kept: kept,
      unreached: unreached,
      late: late,
      codes: codes,
      receipt: receipt,
    );
  }

  /// Whether an adapter erases [table]'s rows from its capture log, which
  /// then captures the erasure itself: capturing it here as well would
  /// publish every erasure twice.
  bool _captureAdapterErases(DVRecordTable table) =>
      table.capture != null &&
      adapters.any(
        (DVPrivacyAdapter a) =>
            a is DVCapturePrivacyAdapter && identical(a.capture, table.capture),
      );

  /// Applies what [model] declared to one of the subject's rows, and removes
  /// the row's change log either way: a log entry holds earlier values, and a
  /// revert would put them back. With [capture], a captured model's log is
  /// purged and the removal captured too.
  ///
  /// The write applies only at the version the walk read. A row rewritten
  /// since is read again: one that [belongs] to the subject no longer is left
  /// alone and returns null, one that still does is written at its new
  /// version, and one gone already has only its copies to forget.
  Future<_DVRowOutcome?> _eraseRow(
    DVPrivacyModel model,
    DVRecord row,
    DVPrivacySubjectRef ref, {
    required bool capture,
    required bool Function(DVRecord row) belongs,
  }) async {
    final DVRecordTable table = model.table;
    final bool anonymizing =
        model.retain != null || model.anonymizeOnErase.isNotEmpty;
    final ({DVRecord row, bool gone})? written = await _writeAtVersion(
      table,
      row,
      belongs: belongs,
      write: (DVRecord at) => anonymizing
          ? _anonymize(model, at, ref)
          // Removed outright, even from a soft-delete table: a row marked
          // deleted still holds everything it held.
          : _deleteAt(database, table, at),
    );
    if (written == null) return null;
    await _forgetRow(database, table, written.row, capture: capture);
    if (written.gone || !anonymizing) return _DVRowOutcome.deleted;
    return model.retain != null ? _DVRowOutcome.kept : _DVRowOutcome.anonymized;
  }

  /// Tombstones every personal field of a kept row and replaces the subject
  /// column with the pseudonym, bumping the version so a writer holding the
  /// old row conflicts rather than writing it back.
  ///
  /// Applied only while the row is still at [row]'s version and holds each
  /// value in [unchanged]; returns whether it was. A write at a stale version
  /// would also set the version the rewrite had already taken, and the writer
  /// holding that rewrite would not conflict.
  Future<bool> _anonymize(
    DVPrivacyModel model,
    DVRecord row,
    DVPrivacySubjectRef ref, {
    Map<String, Object?> unchanged = const <String, Object?>{},
  }) async {
    final DVRecordTable table = model.table;
    final Map<String, Object?> set = <String, Object?>{
      for (final String field in model.personalFields) field: tombstone,
      if (model.subject?._kind == _DVSubjectKind.field)
        model.subject!.column!: ref.pseudonym,
    };
    if (set.isEmpty) return true;
    final List<String> columns = set.keys.toList();
    final (String where, List<Object?> params) = _atVersion(
      table,
      row,
      unchanged,
    );
    final int affected = await database.execute(
      'UPDATE ${table.table} SET '
      '${<String>[for (final String c in columns) '$c = ?', '${DVRecordTable.versionColumn} = ?'].join(', ')} '
      'WHERE $where',
      <Object?>[
        for (final String c in columns) set[c],
        row.version + 1,
        ...params,
      ],
    );
    return affected > 0;
  }

  bool verifyReceipt(DVErasureReceipt receipt) {
    final String expected = _sign(receipt.payload);
    final String actual = receipt.signature;
    if (expected.length != actual.length) return false;
    int diff = 0;
    for (int i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ actual.codeUnitAt(i);
    }
    return diff == 0;
  }

  String _sign(Map<String, Object?> payload) => Hmac(
    sha256,
    _key,
  ).convert(utf8.encode(jsonEncode(_canonical(payload)))).toString();

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final List<String> keys = <String>[
        for (final Object? k in value.keys) '$k',
      ]..sort();
      return <String, Object?>{
        for (final String k in keys) k: _canonical(value[k]),
      };
    }
    if (value is Iterable) {
      return <Object?>[for (final Object? v in value) _canonical(v)];
    }
    return value;
  }

  /// Re-erases every row belonging to a subject in the tombstone log. Run it
  /// before a restored deployment serves anything: a backup cannot be
  /// edited, but no restored system has to serve what it holds.
  Future<DVErasureReplay> replayErasures() async {
    final Set<String> erased = <String>{
      for (final Map<String, Object?> row in await database.query(
        'SELECT subject FROM $tombstoneTable',
      ))
        '${row['subject']}',
    };
    final List<String> codes = <String>[];
    if (erased.isEmpty) return DVErasureReplay._(0, codes);

    final Map<String, Map<String, Object?>> subjectOf =
        <String, Map<String, Object?>>{};
    Future<Map<String, Object?>> subjectsFor(DVPrivacyModel model) async {
      final Map<String, Object?>? known = subjectOf[model.name];
      if (known != null) return known;
      final DVSubject path = model.subject!;
      final Map<String, Object?> map = <String, Object?>{};
      final List<DVRecord> all = await model.table.all(withDeleted: true);
      switch (path._kind) {
        case _DVSubjectKind.self:
          for (final DVRecord r in all) {
            map['${r.key}'] = r.key;
          }
        case _DVSubjectKind.field:
          for (final DVRecord r in all) {
            map['${r.key}'] = r.values[path.column];
          }
        case _DVSubjectKind.through:
          final Map<String, Object?> parents = await subjectsFor(
            _model(path.parent!),
          );
          for (final DVRecord r in all) {
            map['${r.key}'] = parents['${r.values[path.column]}'];
          }
      }
      subjectOf[model.name] = map;
      return map;
    }

    final List<(DVPrivacyModel, DVRecord, DVPrivacySubjectRef)> due =
        <(DVPrivacyModel, DVRecord, DVPrivacySubjectRef)>[];
    for (final DVPrivacyModel model in models) {
      if (model.subject == null) continue;
      final Map<String, Object?> subjects = await subjectsFor(model);
      for (final DVRecord row in await model.table.all(withDeleted: true)) {
        final Object? id = subjects['${row.key}'];
        if (id == null) continue;
        final DVPrivacySubjectRef ref = _ref(id);
        if (erased.contains(ref.pseudonym)) due.add((model, row, ref));
      }
    }
    // A restore brings back the capture log with the rows, so the log is
    // purged again here; no adapter runs on a replay to do it instead.
    bool stillErased(DVPrivacyModel model, DVRecord row) {
      final DVSubject path = model.subject!;
      final Object? id = switch (path._kind) {
        _DVSubjectKind.self => row.key,
        _DVSubjectKind.field => row.values[path.column],
        _DVSubjectKind.through =>
          subjectOf[path.parent!]?['${row.values[path.column]}'],
      };
      return id != null && erased.contains(_ref(id).pseudonym);
    }

    for (final (DVPrivacyModel, DVRecord, DVPrivacySubjectRef) item in due) {
      await _eraseRow(
        item.$1,
        item.$2,
        item.$3,
        capture: true,
        belongs: (DVRecord now) => stillErased(item.$1, now),
      );
    }
    if (due.isNotEmpty) {
      _report(
        codes,
        'DV-PRIVACY-005',
        'A restore replayed the erasure tombstone log; ${due.length} rows '
            'belonging to erased subjects were erased again.',
        DVLogLevel.info,
        null,
      );
    }
    return DVErasureReplay._(due.length, codes);
  }

  // --- export ---------------------------------------------------------------

  Future<DVExportArchive> export({
    required Object subject,
    String? requestedBy,
    String? runBy,
  }) async {
    final DVPrivacySubjectRef ref = _ref(subject);
    final List<String> codes = <String>[];
    final Map<String, List<Map<String, Object?>>> records =
        <String, List<Map<String, Object?>>>{};
    int redacted = 0;

    final Map<String, List<DVRecord>> walk = await _walk(subject);
    for (final DVPrivacyModel model in models) {
      final List<DVRecord> rows = walk[model.name] ?? const <DVRecord>[];
      if (rows.isEmpty) continue;
      records[model.name] = <Map<String, Object?>>[
        for (final DVRecord row in rows)
          <String, Object?>{
            for (final String column in model.table.columns)
              column:
                  model.otherSubjects.contains(column) &&
                      row.values[column] != null &&
                      '${row.values[column]}' != '$subject'
                  ? () {
                      redacted++;
                      return null;
                    }()
                  : row.values[column],
          },
      ];
    }
    if (redacted > 0) {
      _report(
        codes,
        'DV-PRIVACY-006',
        '$redacted fields naming another subject were left out of the '
            'export; only the requesting subject\'s contribution is included.',
        DVLogLevel.info,
        ref,
      );
    }

    final Map<String, Map<String, Object?>> fromAdapters =
        <String, Map<String, Object?>>{};
    final List<String> unreached = <String>[];
    for (final DVPrivacyAdapter adapter in adapters) {
      try {
        fromAdapters[adapter.name] = await adapter.export(ref);
      } on Object {
        unreached.add(adapter.name);
      }
    }

    await _record(
      'export',
      ref,
      requestedAt: _now(),
      completedAt: _now(),
      requestedBy: requestedBy,
      runBy: runBy,
      covered: <String>[...records.keys, ...fromAdapters.keys],
      kept: 0,
      complete: unreached.isEmpty,
    );

    return DVExportArchive._(
      records: records,
      adapters: fromAdapters,
      unreached: unreached,
      codes: codes,
    );
  }

  // --- retention ------------------------------------------------------------

  Future<List<(DVPrivacyModel, DVRecord, bool held)>> _expired(
    DateTime now,
  ) async {
    final List<(DVPrivacyModel, DVRecord, bool)> out =
        <(DVPrivacyModel, DVRecord, bool)>[];
    for (final DVPrivacyModel model in models) {
      final DVRetention? retention = model.retention;
      if (retention == null || retention.isIndefinite) continue;
      for (final DVRecord row in await model.table.all(withDeleted: true)) {
        final bool? held = _heldOrDue(model, row, now);
        if (held != null) out.add((model, row, held));
      }
    }
    return out;
  }

  /// Null when [row] has not outlived [model]'s retention at [now]; otherwise
  /// whether a longer retention still holds it.
  static bool? _heldOrDue(DVPrivacyModel model, DVRecord row, DateTime now) {
    final DVRetention? retention = model.retention;
    final Duration? keep = retention?.duration;
    if (retention == null || keep == null) return null;
    final DateTime? at = DateTime.tryParse('${row.values[retention.from]}');
    if (at == null) return null;
    final Duration age = now.difference(at);
    if (age <= keep) return null;
    final DVRetain? longer = model.retain;
    return longer != null && age <= longer.duration;
  }

  /// What the next sweep would do, changing nothing.
  Future<DVRetentionPlan> planRetention({DateTime? now}) async {
    final Map<String, int> deletions = <String, int>{};
    final Map<String, int> anonymizations = <String, int>{};
    final Map<String, int> held = <String, int>{};
    for (final (DVPrivacyModel model, DVRecord _, bool isHeld)
        in await _expired(now ?? _now())) {
      final Map<String, int> into = isHeld
          ? held
          : model.retention!.then == DVRetentionAction.anonymize
          ? anonymizations
          : deletions;
      into.update(model.name, (int n) => n + 1, ifAbsent: () => 1);
    }
    return DVRetentionPlan._(deletions, anonymizations, held);
  }

  /// Removes expired rows in batches of [batchSize], stopping after
  /// [maxBatches] when given. Each batch stands on its own, so a sweep that
  /// stops part-way resumes where it left off rather than taking a database
  /// down in one transaction.
  Future<DVRetentionSweep> sweepRetention({
    DateTime? now,
    int batchSize = 500,
    int? maxBatches,
  }) async {
    if (batchSize < 1) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be at least 1');
    }
    final List<String> codes = <String>[];
    final Map<String, int> deleted = <String, int>{};
    final Map<String, int> anonymized = <String, int>{};
    final Map<String, int> held = <String, int>{};
    final Map<String, int> skipped = <String, int>{};
    int skippedDue = 0;
    final DateTime at = now ?? _now();
    final List<(DVPrivacyModel, DVRecord, bool)> expired = await _expired(at);
    final List<(DVPrivacyModel, DVRecord)> due = <(DVPrivacyModel, DVRecord)>[];
    for (final (DVPrivacyModel model, DVRecord row, bool isHeld) in expired) {
      if (isHeld) {
        held.update(model.name, (int n) => n + 1, ifAbsent: () => 1);
      } else {
        due.add((model, row));
      }
    }

    int batches = 0;
    int done = 0;
    while (done < due.length && (maxBatches == null || batches < maxBatches)) {
      final int end = done + batchSize < due.length
          ? done + batchSize
          : due.length;
      for (final (DVPrivacyModel model, DVRecord row) in due.sublist(
        done,
        end,
      )) {
        final DVRecordTable table = model.table;
        final DVRetention retention = model.retention!;
        // Only the row as it was read, still expired from the timestamp that
        // made it so: a row renewed since is not this sweep's to remove.
        final Map<String, Object?> unchanged = <String, Object?>{
          retention.from!: row.values[retention.from],
        };
        final bool anonymizing = retention.then == DVRetentionAction.anonymize;
        final bool applied = anonymizing
            ? await _anonymize(
                model,
                row,
                _ref(row.values[model.subject?.column] ?? row.key),
                unchanged: unchanged,
              )
            : await _deleteAt(database, table, row, unchanged: unchanged);
        if (!applied) {
          // Left for the next run, which reads it afresh; counted in
          // [remaining] only while it is still due.
          skipped.update(model.name, (int n) => n + 1, ifAbsent: () => 1);
          final DVRecord? current = await table.read(
            row.key,
            withDeleted: true,
          );
          if (current != null && _heldOrDue(model, current, at) == false) {
            skippedDue++;
          }
          continue;
        }
        (anonymizing ? anonymized : deleted).update(
          model.name,
          (int n) => n + 1,
          ifAbsent: () => 1,
        );
        // Retention applies to every copy of the row: its change log, and
        // the capture log and each destination it feeds.
        await _forgetRow(database, table, row);
      }
      done = end;
      batches++;
    }

    final int removed =
        deleted.values.fold(0, (int a, int b) => a + b) +
        anonymized.values.fold(0, (int a, int b) => a + b);
    if (removed > 0) {
      _report(
        codes,
        'DV-PRIVACY-007',
        'A retention sweep removed $removed expired rows.',
        DVLogLevel.info,
        null,
      );
    }
    if (held.isNotEmpty) {
      _report(
        codes,
        'DV-PRIVACY-008',
        'A retention sweep left ${held.values.fold(0, (int a, int b) => a + b)} '
            'rows a longer retention holds; the longer one won.',
        DVLogLevel.warn,
        null,
      );
    }
    return DVRetentionSweep._(
      deleted: deleted,
      anonymized: anonymized,
      held: held,
      skipped: skipped,
      remaining: due.length - done + skippedDue,
      codes: codes,
    );
  }

  // --- durable jobs ---------------------------------------------------------

  /// Results of erasures run from the queue, most recent last.
  final List<DVErasureResult> jobResults = <DVErasureResult>[];

  /// Registers the erasure and retention handlers on the durable job layer,
  /// with the codecs a queue shared between processes stores them under.
  void registerJobs(DVQueues queues) => registerJobsFor(queues, () => this);

  /// As [registerJobs], running each job on the [DVPrivacy] [privacy] returns
  /// when it runs -- so a process whose configuration changes after start,
  /// an adapter installed late, runs its jobs on the current one.
  static void registerJobsFor(DVQueues queues, DVPrivacy Function() privacy) {
    const DVJobPayloadCodecs()
      ..register<DVPrivacyErasureRequest>(
        const DVJobPayloadCodec<DVPrivacyErasureRequest>(
          name: DVPrivacyErasureRequest.codecName,
          encode: DVPrivacyErasureRequest.encode,
          decode: DVPrivacyErasureRequest.decode,
        ),
      )
      ..register<DVPrivacyRetentionRequest>(
        const DVJobPayloadCodec<DVPrivacyRetentionRequest>(
          name: DVPrivacyRetentionRequest.codecName,
          encode: DVPrivacyRetentionRequest.encode,
          decode: DVPrivacyRetentionRequest.decode,
        ),
      );
    queues
      ..register<DVPrivacyErasureRequest>((
        DVPrivacyErasureRequest request,
      ) async {
        final DVPrivacy current = privacy();
        current.jobResults.add(
          await current.erase(
            subject: request.subject,
            reason: request.reason,
            requestedAt: request.requestedAt,
            requestedBy: request.requestedBy,
            runBy: request.runBy,
          ),
        );
      })
      ..register<DVPrivacyRetentionRequest>((
        DVPrivacyRetentionRequest request,
      ) async {
        await privacy().sweepRetention(
          batchSize: request.batchSize,
          maxBatches: request.maxBatches,
        );
      });
  }

  /// Queues an erasure; a worker runs it.
  ///
  /// The request is recorded as open first, so an erasure whose job is lost
  /// -- an in-process queue that did not survive a restart, a job
  /// dead-lettered -- is still run by [checkErasureDeadlines]. A second
  /// request for a subject already open keeps the first one's time: the
  /// deadline runs from when the person first asked.
  Future<DVJobEnvelope<DVPrivacyErasureRequest>> requestErasure({
    required Object subject,
    required String reason,
    String? requestedBy,
    DVQueues queues = const DVQueues(),
    String queue = 'default',
  }) async {
    final DVPrivacySubjectRef ref = _ref(subject);
    DateTime requestedAt = _now();
    final List<Map<String, Object?>> open = await database.query(
      'SELECT requested_at FROM $openErasuresTable WHERE id = ?',
      <Object?>[ref.pseudonym],
    );
    if (open.isEmpty) {
      await database.execute(
        'INSERT INTO $openErasuresTable '
        '(id, subject, reason, requested_by, requested_at) '
        'VALUES (?, ?, ?, ?, ?)',
        <Object?>[
          ref.pseudonym,
          jsonEncode(
            DVPrivacyErasureRequest.encode(
              DVPrivacyErasureRequest(subject: subject, reason: reason),
            )['subject'],
          ),
          reason,
          requestedBy,
          requestedAt.toUtc().toIso8601String(),
        ],
      );
    } else {
      requestedAt = DateTime.parse('${open.single['requested_at']}');
    }
    return queues.dispatch<DVPrivacyErasureRequest>(
      DVPrivacyErasureRequest(
        subject: subject,
        reason: reason,
        requestedAt: requestedAt,
        requestedBy: requestedBy,
      ),
      queue: queue,
    );
  }

  /// Runs every open erasure requested more than [staleAfter] ago.
  ///
  /// The generated server schedules this. A request younger than
  /// [staleAfter] is left to the job it queued. An older one has lost its job
  /// or is waiting behind a queue nobody works, and is run here: erasure is
  /// idempotent, so a job that does turn up later erases nothing more. One
  /// past [deadline] reports `DV-PRIVACY-004` as it runs. An erasure an
  /// adapter could not reach stays open and is run again next time.
  Future<DVErasureDeadlines> checkErasureDeadlines({
    Duration staleAfter = const Duration(days: 1),
  }) async {
    final DateTime now = _now();
    final List<Map<String, Object?>> open = await database.query(
      'SELECT id, subject, reason, requested_by, requested_at '
      'FROM $openErasuresTable',
    );
    int overdue = 0;
    final List<DVErasureResult> results = <DVErasureResult>[];
    for (final Map<String, Object?> row in open) {
      final DateTime requestedAt = DateTime.parse('${row['requested_at']}');
      final Duration age = now.difference(requestedAt);
      if (age > deadline) overdue++;
      if (age < staleAfter) continue;
      final Object? subject = jsonDecode('${row['subject']}');
      if (subject == null) continue;
      results.add(
        await erase(
          subject: subject,
          reason: '${row['reason']}',
          requestedAt: requestedAt,
          requestedBy: row['requested_by'] as String?,
          runBy: 'dartvel:deadline-check',
        ),
      );
    }
    return DVErasureDeadlines(
      open: open.length,
      overdue: overdue,
      results: List<DVErasureResult>.unmodifiable(results),
    );
  }

  // --- records --------------------------------------------------------------

  Future<void> _record(
    String kind,
    DVPrivacySubjectRef ref, {
    String? reason,
    required DateTime requestedAt,
    required DateTime completedAt,
    String? requestedBy,
    String? runBy,
    required List<String> covered,
    required int kept,
    required bool complete,
  }) async {
    await requests.write(<String, Object?>{
      'id':
          '$kind-${ref.pseudonym.substring(0, 16)}-'
          '${completedAt.microsecondsSinceEpoch}',
      'kind': kind,
      'subject': ref.pseudonym,
      'reason': reason,
      'requested_by': requestedBy,
      'run_by': runBy,
      'requested_at': requestedAt.toUtc().toIso8601String(),
      'completed_at': completedAt.toUtc().toIso8601String(),
      'covered': jsonEncode(covered),
      'kept': kept,
      'complete': complete ? 1 : 0,
    });
  }

  void _report(
    List<String> codes,
    String code,
    String message,
    DVLogLevel level,
    DVPrivacySubjectRef? ref,
  ) {
    codes.add(code);
    DVObservability.log(
      message,
      level: level,
      code: code,
      context: <String, Object?>{if (ref != null) 'subject': ref.pseudonym},
    );
  }
}

enum _DVRowOutcome { deleted, anonymized, kept }

/// What a row the privacy walk removed or anonymized with SQL of its own owes
/// the copies [DVRecordTable] would otherwise have kept in step: its change
/// log removed and, for a captured model with [capture], the capture log's
/// values purged and the removal captured, so a destination fed by delivery
/// drops what the source dropped.
///
/// The walk writes beside the record table rather than through it -- a
/// soft-delete table would only mark the row, and a delete would log its
/// values again -- so nothing reaches those copies unless this does.
Future<void> _forgetRow(
  DVDatabaseAdapter database,
  DVRecordTable table,
  DVRecord row, {
  bool capture = true,
}) async {
  if (table.historyPolicy != null) {
    await database.execute(
      'DELETE FROM ${table.historyTable} WHERE record_key = ?',
      <Object?>[row.key],
    );
  }
  final DVCapture? log = table.capture;
  if (capture && log != null) {
    await log.recordErasure(table, row.key, version: row.version);
  }
}

/// The `WHERE` that matches [row] only as it was read: its key, its version,
/// and each value in [unchanged].
(String, List<Object?>) _atVersion(
  DVRecordTable table,
  DVRecord row,
  Map<String, Object?> unchanged,
) => (
  <String>[
    '${table.key} = ?',
    '${DVRecordTable.versionColumn} = ?',
    for (final String column in unchanged.keys) '$column = ?',
  ].join(' AND '),
  <Object?>[row.key, row.version, ...unchanged.values],
);

/// Deletes [row] if it is still at the version it was read and holds each
/// value in [unchanged]; returns whether it was.
Future<bool> _deleteAt(
  DVDatabaseAdapter database,
  DVRecordTable table,
  DVRecord row, {
  Map<String, Object?> unchanged = const <String, Object?>{},
}) async {
  final (String where, List<Object?> params) = _atVersion(
    table,
    row,
    unchanged,
  );
  return await database.execute(
        'DELETE FROM ${table.table} WHERE $where',
        params,
      ) >
      0;
}

/// How many times an erasure reads a row again that keeps being rewritten
/// under it before giving up. A writer that wins every time is not one the
/// erasure can outrun, and failing loudly leaves the durable job to retry.
const int _erasureAttempts = 5;

/// Applies an erasure's [write] to [row] at the version it was read, reading
/// the row again whenever a rewrite got there first.
///
/// Returns the row as written, or as last read with `gone` when it no longer
/// exists -- its copies are the subject's to forget either way -- and null
/// when the row, as rewritten, no longer [belongs] to the subject, so it is
/// someone else's and left alone.
Future<({DVRecord row, bool gone})?> _writeAtVersion(
  DVRecordTable table,
  DVRecord row, {
  required Future<bool> Function(DVRecord at) write,
  required bool Function(DVRecord row) belongs,
}) async {
  DVRecord at = row;
  for (int attempt = 1; ; attempt++) {
    if (await write(at)) return (row: at, gone: false);
    final DVRecord? current = await table.read(at.key, withDeleted: true);
    if (current == null) return (row: at, gone: true);
    if (!belongs(current)) return null;
    if (attempt >= _erasureAttempts) {
      throw StateError(
        '${table.table}[${at.key}] was rewritten $attempt times while it was '
        'being erased; it still belongs to the subject and was not erased. '
        'Run the erasure again.',
      );
    }
    at = current;
  }
}

/// The erasure and export of one device's offline copy.
///
/// A local store holds the subject's rows and, in its mutation log, writes not
/// yet sent — both are the subject's data. The server cannot run this on a
/// device; the application runs it there, and until it has, that copy has not
/// been erased.
class DVOfflineStorePrivacyAdapter implements DVPrivacyAdapter {
  DVOfflineStorePrivacyAdapter({
    required this.store,
    required this.subject,
    String? name,
  }) : name = name ?? 'offline:${store.table.table}' {
    if (subject._kind == _DVSubjectKind.through) {
      throw ArgumentError.value(
        subject,
        'subject',
        'an offline store has no parent table to walk through',
      );
    }
  }

  final DVOfflineStore store;
  final DVSubject subject;

  @override
  final String name;

  bool _belongs(Object? key, Map<String, Object?> values, Object id) =>
      subject._kind == _DVSubjectKind.self
      ? '$key' == '$id'
      : '${values[subject.column]}' == '$id';

  /// The store writes keys and payloads as JSON: a queued write nests its
  /// values under `values`, a server copy is the values themselves.
  static Object? _decode(Object? stored) {
    if (stored is! String) return stored;
    try {
      return jsonDecode(stored);
    } on FormatException {
      return stored;
    }
  }

  static Map<String, Object?> _map(Object? value) => value is Map
      ? <String, Object?>{
          for (final MapEntry<Object?, Object?> e in value.entries)
            '${e.key}': e.value,
        }
      : const <String, Object?>{};

  @override
  Future<void> erase(DVPrivacySubjectRef ref) async {
    final DVRecordTable table = store.table;
    final DVDatabaseAdapter db = table.database;
    final Set<String> keys = <String>{};
    for (final DVRecord row in await table.all(withDeleted: true)) {
      if (!_belongs(row.key, row.values, ref.id)) continue;
      final ({DVRecord row, bool gone})? removed = await _writeAtVersion(
        table,
        row,
        write: (DVRecord at) => _deleteAt(db, table, at),
        belongs: (DVRecord now) => _belongs(now.key, now.values, ref.id),
      );
      // Moved to someone else since it was read: theirs, and so are the
      // server copy and queued writes its key would otherwise match.
      if (removed == null) continue;
      keys.add(jsonEncode(row.key));
      await _forgetRow(db, table, removed.row);
    }
    // A server copy or a queued write can outlive the local row it came from,
    // so each is matched on its own values, not only on a local row's key.
    for (final Map<String, Object?> s in await db.query(
      'SELECT * FROM ${store.serverTable}',
    )) {
      final String key = '${s['record_key']}';
      if (keys.contains(key) ||
          _belongs(_decode(key), _map(_decode(s['payload'])), ref.id)) {
        await db.execute(
          'DELETE FROM ${store.serverTable} WHERE record_key = ?',
          <Object?>[key],
        );
      }
    }
    for (final Map<String, Object?> m in await db.query(
      'SELECT * FROM ${store.logTable}',
    )) {
      final String key = '${m['record_key']}';
      final Map<String, Object?> values = _map(
        _map(_decode(m['payload']))['values'],
      );
      if (keys.contains(key) || _belongs(_decode(key), values, ref.id)) {
        await db.execute(
          'DELETE FROM ${store.logTable} WHERE mutation_id = ?',
          <Object?>[m['mutation_id']],
        );
      }
    }
  }

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef ref) async =>
      <String, Object?>{
        'records': <Map<String, Object?>>[
          for (final DVRecord row in await store.table.all(withDeleted: true))
            if (_belongs(row.key, row.values, ref.id)) row.values,
        ],
      };
}
