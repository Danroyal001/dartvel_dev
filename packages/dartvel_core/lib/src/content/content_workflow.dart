/// Content workflow: draft, review, scheduled and published states on stored
/// documents.
///
/// This is the runtime the specification's `# Content Workflow` describes.
/// Page documents, scene documents, theme overrides and translation catalogs
/// are all stored, versioned data, so they take one workflow: a
/// [DVContentWorkflow] is declared once per document kind, over the document
/// type's own JSON codec, and its versions live in a [DVRecordTable] -- so
/// every state change carries its actor and its transaction in Record
/// History, and rolls back with an enclosing `DV.transaction`.
///
/// Every guard here is against a quiet failure:
///
/// - An approval is pinned to the revision and digest it was given on. A
///   publish of anything else is refused with `DV-CONTENT-002`, and every
///   transition is a conditional write against the version as the caller read
///   it, so a stale snapshot cannot approve or publish what the row now holds.
/// - Roles are policy actions checked through [DVAuthAuthorization] at every
///   transition, never cached, so a role removed mid-review is removed for the
///   next step. A scheduled publish checks the scheduler's authority again at
///   the slot.
/// - Anyone who edited a version is its author for approval purposes, and
///   approving one's own work needs the separate [DVContentAction.reviewOwn]
///   action, which nothing grants by default.
/// - A scheduled publish is a job on [DVQueues], and runs at most once: it
///   carries the schedule's id, and a cancelled, rescheduled, withdrawn or
///   already-published version does not match it. A slot that passes without
///   the job running is `DV-CONTENT-005`, never a late publish.
/// - Only a published version is served. A preview is a signed, expiring
///   token; an altered or expired one serves the published version and
///   reports `DV-CONTENT-001`, and a preview is never cacheable or indexable.
/// - Cache tags are revalidated, publish hooks run and review requests are
///   sent after the transaction commits, so a publish that rolls back has
///   invalidated and announced nothing.
library dartvel_core.content.content_workflow;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../dartvel.dart'
    show
        DVAuthAuthorization,
        DVCacheTags,
        DVJobPayloadCodec,
        DVJobPayloadCodecs,
        DVNotificationMessage,
        DVNotificationsService,
        DVQueues;
import '../data/record_history.dart';
import '../database/adapter.dart';
import '../observability/observability.dart';
import '../transaction/transaction.dart';

/// The policy actions the workflow checks, registered like `update` and
/// `delete` through `DV.Auth.authorization.register<User, Document>(...)`.
final class DVContentAction {
  const DVContentAction._();

  /// Open a draft, change it, submit it for review, issue a preview link.
  static const String edit = 'edit';

  /// Approve a version under review, or send it back for changes.
  static const String review = 'review';

  /// Approve a version the approver edited. A separate action so that the
  /// default -- nothing registers it -- is that nobody approves their own work.
  static const String reviewOwn = 'reviewOwn';

  /// Publish, restore, or withdraw a published version.
  static const String publish = 'publish';

  /// Schedule a publish or a withdrawal, or cancel one.
  static const String schedule = 'schedule';

  static const List<String> all = <String>[
    edit,
    review,
    reviewOwn,
    publish,
    schedule,
  ];
}

/// Where a version is in the workflow.
///
/// `approved` sits between review and scheduled; `superseded` is a version
/// that was published and has been replaced, kept so it can be restored;
/// `withdrawn` is a version taken down or abandoned.
enum DVContentState {
  draft,
  review,
  approved,
  scheduled,
  published,
  superseded,
  withdrawn,
}

/// A refusal from the workflow. [code] is the diagnostic, when the
/// specification assigns one.
abstract class DVContentError implements Exception {
  String? get code;
}

/// The actor lacks the policy action. `DV-CONTENT-003` for [DVContentAction.publish]
/// and [DVContentAction.schedule]; the specification assigns no code to the
/// others.
class DVContentRefused implements DVContentError {
  DVContentRefused(this.action, this.actor, {this.versionId});

  final String action;
  final String actor;
  final String? versionId;

  @override
  String? get code =>
      action == DVContentAction.publish || action == DVContentAction.schedule
      ? 'DV-CONTENT-003'
      : null;

  @override
  String toString() =>
      '${code ?? 'DVContentRefused'}: $actor lacks the '
      '"$action" policy action${versionId == null ? '' : ' on $versionId'}.';
}

/// The version changed after it was approved, so publishing it would ship
/// text nobody approved (`DV-CONTENT-002`).
class DVContentChangedAfterApproval implements DVContentError {
  DVContentChangedAfterApproval(
    this.versionId, {
    required this.approvedRevision,
    required this.revision,
  });

  final String versionId;

  /// The revision the approval was given on, or null when there is none.
  final int? approvedRevision;
  final int revision;

  @override
  String get code => 'DV-CONTENT-002';

  @override
  String toString() => approvedRevision == null
      ? '$code: $versionId has no approval, so it cannot be published.'
      : '$code: $versionId was approved at revision $approvedRevision and is '
            'now at revision $revision; it needs a new review.';
}

/// A version under review cannot be edited: a reviewer approving a moving
/// document approves nothing.
class DVContentFrozen implements DVContentError {
  DVContentFrozen(this.versionId);

  final String versionId;

  @override
  String? get code => null;

  @override
  String toString() =>
      '$versionId is under review and frozen against edits. '
      'Request changes to return it to draft.';
}

/// The version is not in a state the operation applies to.
class DVContentInvalidTransition implements DVContentError {
  DVContentInvalidTransition(this.versionId, this.from, this.operation);

  final String versionId;
  final DVContentState from;
  final String operation;

  @override
  String? get code => null;

  @override
  String toString() =>
      'Cannot $operation $versionId: it is ${from.name}.${from == DVContentState.published ? ' A published version is never edited in place; open a new draft beside it.' : ''}';
}

/// The document already has a version open for editing, review or
/// scheduling. One at a time, so there is one answer to "what is next".
class DVContentOpenDraft implements DVContentError {
  DVContentOpenDraft(this.documentId, this.versionId);

  final String documentId;
  final String versionId;

  @override
  String? get code => null;

  @override
  String toString() =>
      '$documentId already has an open version, $versionId. Edit it, or '
      'withdraw it before opening another.';
}

/// Which version was approved, by whom and when. Travels with a bundle, so a
/// rollback restores the fact that the restored version was the reviewed one.
class DVContentApproval {
  const DVContentApproval({
    required this.approvedBy,
    required this.approvedAt,
    required this.revision,
    required this.digest,
  });

  factory DVContentApproval.fromJson(Map<String, Object?> json) =>
      DVContentApproval(
        approvedBy: json['approvedBy']! as String,
        approvedAt: DateTime.parse(json['approvedAt']! as String),
        revision: (json['revision']! as num).toInt(),
        digest: json['digest']! as String,
      );

  final String approvedBy;
  final DateTime approvedAt;

  /// The revision of the version's content the approval was given on.
  final int revision;

  /// The SHA-256 of that content, canonically encoded.
  final String digest;

  /// Whether this approval covers [version] as it stands.
  bool matches(DVContentVersion<Object?> version) =>
      revision == version.revision && digest == version.digest;

  Map<String, Object?> toJson() => <String, Object?>{
    'approvedBy': approvedBy,
    'approvedAt': _stamp(approvedAt),
    'revision': revision,
    'digest': digest,
  };
}

/// One version of one document, as read.
///
/// A snapshot: transitions take it as the version the caller read and refuse
/// when the stored version has moved since.
class DVContentVersion<T> {
  DVContentVersion._(this._record, this.document)
    : editors = Set<String>.unmodifiable(_decodeSet(_record.values['editors'])),
      machineTranslated = Set<String>.unmodifiable(
        _decodeSet(_record.values['machine_keys']),
      );

  final DVRecord _record;

  /// The document as this version holds it.
  final T document;

  Map<String, Object?> get _v => _record.values;

  /// `kind:documentId:number`.
  String get id => _v['id']! as String;
  String get kind => _v['kind']! as String;
  String get documentId => _v['document_id']! as String;

  /// The version's place among its document's versions, from 1.
  int get number => _asInt(_v['number']);

  /// How many times the content was set, from 1. State changes do not move it.
  int get revision => _asInt(_v['revision']);

  /// SHA-256 of the canonically encoded content.
  String get digest => _v['digest']! as String;

  DVContentState get state =>
      DVContentState.values.byName(_v['state']! as String);

  /// Who opened the draft.
  String get author => _v['author']! as String;

  /// Everyone who opened or changed the content, the author included.
  final Set<String> editors;

  /// Who was asked to review.
  String? get reviewer => _v['reviewer'] as String?;

  DVContentApproval? get approval {
    final Object? by = _v['approved_by'];
    if (by == null) return null;
    return DVContentApproval(
      approvedBy: by as String,
      approvedAt: DateTime.parse(_v['approved_at']! as String),
      revision: _asInt(_v['approved_revision']),
      digest: _v['approved_digest']! as String,
    );
  }

  /// Whether there is an approval and the content has moved since it.
  bool get changedSinceApproval {
    final DVContentApproval? given = approval;
    return given != null && !given.matches(this);
  }

  DateTime? get scheduledAt => _date(_v['scheduled_at']);
  String? get scheduledBy => _v['scheduled_by'] as String?;
  String? get scheduleId => _v['schedule_id'] as String?;

  DateTime? get withdrawAt => _date(_v['withdraw_at']);
  String? get withdrawBy => _v['withdraw_by'] as String?;
  String? get withdrawId => _v['withdraw_id'] as String?;

  DateTime? get publishedAt => _date(_v['published_at']);
  String? get publishedBy => _v['published_by'] as String?;

  /// Top-level keys whose values a machine wrote and no human has changed or
  /// confirmed.
  final Set<String> machineTranslated;

  /// The last note left on a transition, such as a reviewer's request.
  String? get note => _v['note'] as String?;

  @override
  String toString() => 'DVContentVersion($id r$revision ${state.name})';
}

/// What to serve for a document, and how it may be served.
class DVContentServed<T> {
  const DVContentServed._(
    this.version, {
    required this.isPreview,
    required this.cacheTags,
  });

  final DVContentVersion<T> version;
  T get document => version.document;

  /// Whether this is an unpublished version shown through a preview link.
  final bool isPreview;

  /// A preview carries `noindex`: a draft a crawler can reach is published.
  bool get noindex => isPreview;

  /// A preview is never cached, so it can never be served from a cache to
  /// somebody without the link.
  bool get cacheable => !isPreview;

  /// The tags a response for the published version is cached under. Empty for
  /// a preview.
  final List<String> cacheTags;
}

/// One state change, from Record History.
class DVContentTransition {
  const DVContentTransition._({
    required this.version,
    required this.versionId,
    required this.from,
    required this.to,
    required this.actor,
    required this.at,
  });

  /// The version's number.
  final int version;
  final String versionId;

  /// Null for the change that opened the draft.
  final DVContentState? from;
  final DVContentState to;
  final String? actor;
  final DateTime at;
}

enum DVContentReportKind {
  /// `DV-CONTENT-001`.
  previewRejected,

  /// `DV-CONTENT-002`.
  changedAfterApproval,

  /// `DV-CONTENT-003`.
  refused,

  /// `DV-CONTENT-004`.
  machineTranslated,

  /// `DV-CONTENT-005`.
  missedSlot,

  /// A review request could not be delivered. The submission stands.
  notificationFailed,
}

/// Something the workflow reported rather than threw, or threw and also
/// recorded, because the caller was a job with nobody to throw to.
class DVContentReport {
  DVContentReport._(
    this.kind,
    this.message, {
    this.versionId,
    Set<String> keys = const <String>{},
  }) : keys = Set<String>.unmodifiable(keys);

  final DVContentReportKind kind;
  final String message;
  final String? versionId;

  /// The machine-translated keys, for [DVContentReportKind.machineTranslated].
  final Set<String> keys;

  String? get code => switch (kind) {
    DVContentReportKind.previewRejected => 'DV-CONTENT-001',
    DVContentReportKind.changedAfterApproval => 'DV-CONTENT-002',
    DVContentReportKind.refused => 'DV-CONTENT-003',
    DVContentReportKind.machineTranslated => 'DV-CONTENT-004',
    DVContentReportKind.missedSlot => 'DV-CONTENT-005',
    DVContentReportKind.notificationFailed => null,
  };

  @override
  String toString() => '${code ?? kind.name}: $message';
}

/// What a scheduled job does at its slot.
enum DVContentScheduledAction { publish, withdraw }

/// How a scheduled job ended.
enum DVContentScheduleOutcome {
  /// The version was published or withdrawn.
  done,

  /// The job no longer matches the version: the schedule was cancelled or
  /// replaced, the version withdrawn or superseded, or the job already ran.
  stale,

  /// The slot has not arrived; nothing was done.
  notDue,

  /// `DV-CONTENT-005`.
  missed,

  /// `DV-CONTENT-002`.
  changedAfterApproval,

  /// `DV-CONTENT-003`.
  refused,
}

/// The payload of a scheduled publish or withdrawal on [DVQueues].
class DVContentScheduledJob {
  const DVContentScheduledJob({
    required this.kind,
    required this.versionId,
    required this.scheduleId,
    required this.action,
    required this.at,
  });

  factory DVContentScheduledJob.fromJson(Map<String, Object?> json) =>
      DVContentScheduledJob(
        kind: json['kind']! as String,
        versionId: json['versionId']! as String,
        scheduleId: json['scheduleId']! as String,
        action: DVContentScheduledAction.values.byName(
          json['action']! as String,
        ),
        at: DateTime.parse(json['at']! as String),
      );

  final String kind;
  final String versionId;

  /// The schedule this job was dispatched for. A job whose id no longer
  /// matches the version's does nothing.
  final String scheduleId;
  final DVContentScheduledAction action;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'versionId': versionId,
    'scheduleId': scheduleId,
    'action': action.name,
    'at': _stamp(at),
  };

  /// Registered by [DVContentWorkflow.registerJobs], so a database queue can
  /// persist the job across a restart. The name is stored and must not change.
  static final DVJobPayloadCodec<DVContentScheduledJob> codec =
      DVJobPayloadCodec<DVContentScheduledJob>(
        name: 'dartvel.content.scheduled',
        encode: (DVContentScheduledJob job) => job.toJson(),
        decode: DVContentScheduledJob.fromJson,
      );
}

/// The workflow for one kind of stored document.
class DVContentWorkflow<T> {
  DVContentWorkflow({
    required this.kind,
    required Map<String, Object?> Function(T document) encode,
    required T Function(Map<String, Object?> json) decode,
    required String Function(T document) documentId,
    required String Function(Object? user) actorId,
    DVDatabaseAdapter? database,
    DVAuthAuthorization authorization = const DVAuthAuthorization(),
    Future<Object?> Function(String actorId)? findActor,
    List<int>? previewKey,
    List<String> Function(DVContentVersion<T> version)? cacheTags,
    FutureOr<void> Function(String tag)? revalidateTag,
    Future<void> Function(String recipient, DVNotificationMessage message)?
    notify,
    FutureOr<void> Function(DVContentVersion<T> version)? onPublished,
    FutureOr<void> Function(DVContentVersion<T> version)? onWithdrawn,
    this.queue = 'default',
    this.requireApproval = true,
    this.missedAfter = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _encode = encode,
       _decode = decode,
       _documentId = documentId,
       _actorId = actorId,
       _authorization = authorization,
       _findActor = findActor,
       _previewKey = previewKey == null
           ? null
           : List<int>.unmodifiable(previewKey),
       _cacheTags = cacheTags,
       _revalidateTag =
           revalidateTag ??
           ((String tag) => const DVCacheTags().revalidateTag(tag)),
       _notify = notify ?? const DVNotificationsService().send,
       _onPublished = onPublished,
       _onWithdrawn = onWithdrawn,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _table = DVRecordTable(
         table: table,
         key: 'id',
         columns: _columns,
         history: const DVHistory(),
         database: database,
       ) {
    if (kind.isEmpty || kind.contains(':')) {
      throw ArgumentError.value(kind, 'kind', 'must be non-empty without ":"');
    }
  }

  /// Where every kind's versions are stored, told apart by `kind`.
  static const String table = 'dartvel_content_versions';

  static const List<String> _columns = <String>[
    'id',
    'kind',
    'document_id',
    'number',
    'revision',
    'body',
    'digest',
    'state',
    'author',
    'editors',
    'reviewer',
    'approved_by',
    'approved_at',
    'approved_revision',
    'approved_digest',
    'scheduled_at',
    'scheduled_by',
    'schedule_id',
    'schedule_dispatched',
    'withdraw_at',
    'withdraw_by',
    'withdraw_id',
    'withdraw_dispatched',
    'published_at',
    'published_by',
    'machine_keys',
    'note',
    'moved_at',
  ];

  static const List<String> _scheduleColumns = <String>[
    'scheduled_at',
    'scheduled_by',
    'schedule_id',
    'schedule_dispatched',
  ];

  static const List<String> _withdrawColumns = <String>[
    'withdraw_at',
    'withdraw_by',
    'withdraw_id',
    'withdraw_dispatched',
  ];

  static final Map<String, DVContentWorkflow<Object?>> _jobWorkflows =
      <String, DVContentWorkflow<Object?>>{};

  /// The document kind, e.g. `page`, `scene`, `theme`, `catalog`.
  final String kind;

  /// The queue scheduled jobs are dispatched to.
  final String queue;

  /// Whether a publish needs an approval that matches the content. Off only
  /// for an application where one person edits their own site.
  final bool requireApproval;

  /// How late a slot may be run before it counts as missed.
  final Duration missedAfter;

  final Map<String, Object?> Function(T document) _encode;
  final T Function(Map<String, Object?> json) _decode;
  final String Function(T document) _documentId;
  final String Function(Object? user) _actorId;
  final DVAuthAuthorization _authorization;
  final Future<Object?> Function(String actorId)? _findActor;
  final List<int>? _previewKey;
  final List<String> Function(DVContentVersion<T> version)? _cacheTags;
  final FutureOr<void> Function(String tag) _revalidateTag;
  final Future<void> Function(String recipient, DVNotificationMessage message)
  _notify;
  final FutureOr<void> Function(DVContentVersion<T> version)? _onPublished;

  /// Runs after commit when a published version stops being served, so
  /// whatever [_onPublished] wrote for it can be taken down.
  final FutureOr<void> Function(DVContentVersion<T> version)? _onWithdrawn;
  final DateTime Function() _clock;
  final DVRecordTable _table;
  final DVTransactionRunner _transactions = DVTransactionRunner();
  final List<DVContentReport> _reports = <DVContentReport>[];
  final math.Random _random = math.Random.secure();

  DVDatabaseAdapter get database => _table.database;

  /// What this workflow reported, oldest first; the last 1000 are kept.
  List<DVContentReport> get reports =>
      List<DVContentReport>.unmodifiable(_reports);

  /// The tag every response for [documentId] is cached under.
  String documentTag(String documentId) => 'dv-content:$kind:$documentId';

  Future<void> ensureSchema() => _table.ensureSchema();

  // --- reading ---------------------------------------------------------------

  /// The version with [id], as it stands.
  Future<DVContentVersion<T>?> version(String id) async {
    final DVRecord? record = await _table.read(id);
    if (record == null || record.values['kind'] != kind) return null;
    return _fromRecord(record);
  }

  /// Every version of [documentId], oldest first.
  Future<List<DVContentVersion<T>>> versions(String documentId) =>
      _select('document_id', documentId);

  /// The published version of [documentId], or null.
  Future<DVContentVersion<T>?> current(String documentId) async {
    for (final DVContentVersion<T> v in await versions(documentId)) {
      if (v.state == DVContentState.published) return v;
    }
    return null;
  }

  /// Every published version of this kind: the set static generation, the
  /// sitemap and a bundle may read. Nothing unpublished is ever in it.
  Future<List<DVContentVersion<T>>> publicVersions() =>
      _select('state', DVContentState.published.name);

  /// What to serve for [documentId].
  ///
  /// The published version, unless [preview] is a valid, unexpired link for a
  /// version of this document. A link that fails verification serves the
  /// published version and reports `DV-CONTENT-001` -- not the draft, and not
  /// a 404, because the published page is the honest answer to the route.
  Future<DVContentServed<T>?> resolve(
    String documentId, {
    String? preview,
  }) async {
    if (preview != null) {
      final String? versionId = _verifyPreview(preview, documentId);
      final DVContentVersion<T>? named = versionId == null
          ? null
          : await version(versionId);
      if (named != null && named.documentId == documentId) {
        return DVContentServed<T>._(
          named,
          isPreview: named.state != DVContentState.published,
          cacheTags: named.state == DVContentState.published
              ? _tagsFor(named)
              : const <String>[],
        );
      }
      _report(
        DVContentReport._(
          DVContentReportKind.previewRejected,
          'a preview link for $kind:$documentId failed verification or had '
          'expired; the published version was served',
          versionId: versionId,
        ),
      );
    }
    final DVContentVersion<T>? live = await current(documentId);
    if (live == null) return null;
    return DVContentServed<T>._(
      live,
      isPreview: false,
      cacheTags: _tagsFor(live),
    );
  }

  /// A signed link token naming [version], valid for [expiresIn].
  ///
  /// Carries the document, the version and the expiry, signed with the
  /// preview key. Issuing one needs [DVContentAction.edit] or
  /// [DVContentAction.review].
  Future<String> previewToken(
    DVContentVersion<T> version, {
    required Object? as,
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    final List<int> key = _requirePreviewKey();
    final String actor = _actorId(as);
    if (!await _can(as, DVContentAction.edit, version.document) &&
        !await _can(as, DVContentAction.review, version.document)) {
      throw DVContentRefused(
        DVContentAction.edit,
        actor,
        versionId: version.id,
      );
    }
    final String payload = _b64(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'k': kind,
          'd': version.documentId,
          'v': version.id,
          'e': _clock().add(expiresIn).millisecondsSinceEpoch,
        }),
      ),
    );
    return '$payload.${_b64(Hmac(sha256, key).convert(utf8.encode(payload)).bytes)}';
  }

  /// Every state change of every version of [documentId], version by version.
  Future<List<DVContentTransition>> history(String documentId) async {
    final List<DVContentTransition> transitions = <DVContentTransition>[];
    for (final DVContentVersion<T> v in await versions(documentId)) {
      for (final DVHistoryEntry entry in await _table.history(v.id)) {
        final DVFieldChange? state = entry.changes['state'];
        if (state == null) continue;
        final Object? movedAt = entry.changes['moved_at']?.to;
        transitions.add(
          DVContentTransition._(
            version: v.number,
            versionId: v.id,
            from: state.from == null
                ? null
                : DVContentState.values.byName(state.from! as String),
            to: DVContentState.values.byName(state.to! as String),
            actor: entry.actor,
            at: movedAt is String ? DateTime.parse(movedAt) : entry.at,
          ),
        );
      }
    }
    return transitions;
  }

  /// The top-level fields [version] changes relative to [against], or to the
  /// published version when [against] is null.
  Future<Map<String, DVFieldChange>> diff(
    DVContentVersion<T> version, {
    DVContentVersion<T>? against,
  }) async {
    final DVContentVersion<T>? base =
        against ?? await current(version.documentId);
    final Map<String, Object?> before = base == null
        ? const <String, Object?>{}
        : _encode(base.document);
    final Map<String, Object?> after = _encode(version.document);
    return <String, DVFieldChange>{
      for (final String key in <String>{...before.keys, ...after.keys})
        if (_canonicalJson(before[key]) != _canonicalJson(after[key]))
          key: DVFieldChange(from: before[key], to: after[key]),
    };
  }

  // --- editing ---------------------------------------------------------------

  /// Opens a draft of [document] beside whatever is published.
  ///
  /// [machineTranslated] names the top-level keys a machine wrote; each stays
  /// marked until a human changes or confirms it.
  Future<DVContentVersion<T>> draft(
    T document, {
    required Object? as,
    Set<String> machineTranslated = const <String>{},
  }) async {
    final String actor = await _authorize(as, DVContentAction.edit, document);
    final String documentId = _documentId(document);
    final List<DVContentVersion<T>> existing = await versions(documentId);
    for (final DVContentVersion<T> v in existing) {
      if (_open(v.state)) throw DVContentOpenDraft(documentId, v.id);
    }
    final int number =
        existing.fold<int>(
          0,
          (int n, DVContentVersion<T> v) => math.max(n, v.number),
        ) +
        1;
    final String body = _canonicalJson(_encode(document));
    return _transactions((DVContext context) async {
      final DVWriteResult result = await _table.write(<String, Object?>{
        'id': '$kind:$documentId:$number',
        'kind': kind,
        'document_id': documentId,
        'number': number,
        'revision': 1,
        'body': body,
        'digest': _digest(body),
        'state': DVContentState.draft.name,
        'author': actor,
        'editors': _encodeSet(<String>{actor}),
        'machine_keys': _encodeSet(machineTranslated),
        'moved_at': _stamp(_clock()),
      }, actor: actor);
      return _fromRecord(result.record);
    });
  }

  /// Sets [version]'s content to [document].
  ///
  /// Allowed in draft, approved and scheduled. An approved or scheduled
  /// version keeps its approval, pinned to the revision it was given on, so a
  /// publish of the edited content is refused with `DV-CONTENT-002` rather
  /// than shipping what nobody approved. Refused under review, and for a
  /// published version, which is never edited in place.
  Future<DVContentVersion<T>> edit(
    DVContentVersion<T> version,
    T document, {
    required Object? as,
  }) async {
    final String actor = await _authorize(
      as,
      DVContentAction.edit,
      version.document,
    );
    if (_documentId(document) != version.documentId) {
      throw ArgumentError.value(
        document,
        'document',
        'is not ${version.documentId}',
      );
    }
    if (version.state == DVContentState.review) {
      throw DVContentFrozen(version.id);
    }
    _expect(version, 'edit', const <DVContentState>{
      DVContentState.draft,
      DVContentState.approved,
      DVContentState.scheduled,
    });
    final String body = _canonicalJson(_encode(document));
    if (body == version._v['body']) return version;

    final Map<String, Object?> before = _encode(version.document);
    final Map<String, Object?> after = _encode(document);
    final Set<String> machine = <String>{
      for (final String key in version.machineTranslated)
        if (_canonicalJson(before[key]) == _canonicalJson(after[key])) key,
    };
    return _move(version, actor, <String, Object?>{
      'body': body,
      'digest': _digest(body),
      'revision': version.revision + 1,
      'editors': _encodeSet(<String>{...version.editors, actor}),
      'machine_keys': _encodeSet(machine),
    });
  }

  /// Marks [keys] as reviewed by a human without changing them.
  Future<DVContentVersion<T>> confirmTranslations(
    DVContentVersion<T> version,
    Set<String> keys, {
    required Object? as,
  }) async {
    final String actor = await _authorize(
      as,
      DVContentAction.edit,
      version.document,
    );
    _expect(version, 'confirm translations of', const <DVContentState>{
      DVContentState.draft,
      DVContentState.review,
      DVContentState.approved,
      DVContentState.scheduled,
    });
    return _move(version, actor, <String, Object?>{
      'machine_keys': _encodeSet(version.machineTranslated.difference(keys)),
    });
  }

  // --- review ----------------------------------------------------------------

  /// Asks [to] to review [version], freezing it. The request is sent through
  /// `DV.Notifications` after the transition commits.
  Future<DVContentVersion<T>> submit(
    DVContentVersion<T> version, {
    required String to,
    required Object? as,
  }) async {
    final String actor = await _authorize(
      as,
      DVContentAction.edit,
      version.document,
    );
    _expect(version, 'submit', const <DVContentState>{
      DVContentState.draft,
      DVContentState.approved,
    });
    return _transactions((DVContext context) async {
      final DVContentVersion<T> moved = await _move(
        version,
        actor,
        <String, Object?>{
          'state': DVContentState.review.name,
          'reviewer': to,
          ..._cleared(const <String>[
            'approved_by',
            'approved_at',
            'approved_revision',
            'approved_digest',
            'note',
          ]),
        },
      );
      context.afterCommit(() async {
        try {
          await _notify(
            to,
            DVNotificationMessage(
              title: 'Review requested',
              body: '$actor asked you to review ${moved.documentId}.',
              data: <String, String>{
                'kind': kind,
                'document': moved.documentId,
                'version': moved.id,
              },
            ),
          );
        } catch (error) {
          _report(
            DVContentReport._(
              DVContentReportKind.notificationFailed,
              'the review request for ${moved.id} to $to could not be sent: '
              '$error',
              versionId: moved.id,
            ),
          );
        }
      });
      return moved;
    });
  }

  /// Approves [version] as it was read, pinning the approval to its revision.
  ///
  /// Anyone who edited the version needs [DVContentAction.reviewOwn] as well.
  Future<DVContentVersion<T>> approve(
    DVContentVersion<T> version, {
    required Object? as,
  }) async {
    final String actor = await _authorize(
      as,
      DVContentAction.review,
      version.document,
    );
    if (version.editors.contains(actor)) {
      await _authorize(as, DVContentAction.reviewOwn, version.document);
    }
    _expect(version, 'approve', const <DVContentState>{DVContentState.review});
    final DateTime now = _clock();
    return _move(version, actor, <String, Object?>{
      'state': DVContentState.approved.name,
      'approved_by': actor,
      'approved_at': _stamp(now),
      'approved_revision': version.revision,
      'approved_digest': version.digest,
    });
  }

  /// Sends [version] back to draft.
  Future<DVContentVersion<T>> requestChanges(
    DVContentVersion<T> version, {
    required Object? as,
    String? note,
  }) async {
    final String actor = await _authorize(
      as,
      DVContentAction.review,
      version.document,
    );
    _expect(version, 'request changes to', const <DVContentState>{
      DVContentState.review,
    });
    return _move(version, actor, <String, Object?>{
      'state': DVContentState.draft.name,
      'note': note,
    });
  }

  // --- scheduling ------------------------------------------------------------

  /// Schedules [version] to be published at [at], by a job on [DVQueues].
  ///
  /// Needs `findActor`, because the scheduler's authority is checked again at
  /// the slot and a job carries an id, not a user.
  Future<DVContentVersion<T>> schedule(
    DVContentVersion<T> version, {
    required DateTime at,
    required Object? as,
  }) async {
    _requireFindActor();
    final String actor = await _authorize(
      as,
      DVContentAction.schedule,
      version.document,
      versionId: version.id,
    );
    _expect(version, 'schedule', const <DVContentState>{
      DVContentState.approved,
    });
    _requireApproved(version);
    if (at.isBefore(_clock())) {
      throw ArgumentError.value(at, 'at', 'is in the past; publish instead');
    }
    return _move(version, actor, <String, Object?>{
      'state': DVContentState.scheduled.name,
      'scheduled_at': _stamp(at),
      'scheduled_by': actor,
      'schedule_id': _newId(),
      'schedule_dispatched': null,
    });
  }

  /// Cancels [version]'s scheduled publish. A job already dispatched for it
  /// finds the schedule gone and does nothing.
  Future<DVContentVersion<T>> cancelSchedule(
    DVContentVersion<T> version, {
    required Object? as,
  }) async {
    final String actor = await _authorize(
      as,
      DVContentAction.schedule,
      version.document,
      versionId: version.id,
    );
    _expect(version, 'cancel the schedule of', const <DVContentState>{
      DVContentState.scheduled,
    });
    return _move(version, actor, <String, Object?>{
      'state': DVContentState.approved.name,
      ..._cleared(_scheduleColumns),
    });
  }

  /// Schedules the published [version] to be withdrawn at [at].
  Future<DVContentVersion<T>> scheduleWithdraw(
    DVContentVersion<T> version, {
    required DateTime at,
    required Object? as,
  }) async {
    _requireFindActor();
    final String actor = await _authorize(
      as,
      DVContentAction.schedule,
      version.document,
      versionId: version.id,
    );
    _expect(version, 'schedule the withdrawal of', const <DVContentState>{
      DVContentState.published,
    });
    if (at.isBefore(_clock())) {
      throw ArgumentError.value(at, 'at', 'is in the past; withdraw instead');
    }
    return _move(version, actor, <String, Object?>{
      'withdraw_at': _stamp(at),
      'withdraw_by': actor,
      'withdraw_id': _newId(),
      'withdraw_dispatched': null,
    });
  }

  /// Registers the scheduled-job handler on [queues], and the payload codec a
  /// database queue needs to persist it.
  void registerJobs(DVQueues queues) {
    _jobWorkflows[kind] = this;
    if (const DVJobPayloadCodecs().nameFor<DVContentScheduledJob>() == null) {
      const DVJobPayloadCodecs().register<DVContentScheduledJob>(
        DVContentScheduledJob.codec,
      );
    }
    queues.register<DVContentScheduledJob>((DVContentScheduledJob job) async {
      final DVContentWorkflow<Object?>? workflow = _jobWorkflows[job.kind];
      if (workflow == null) {
        // Failing the job keeps it visible in the dead letters, where a
        // deploy that dropped a workflow can be seen and retried.
        throw StateError('No content workflow registered for "${job.kind}".');
      }
      await workflow.runScheduled(job);
    });
  }

  /// Dispatches a job for every schedule whose slot has arrived, and reports
  /// every slot missed by more than [missedAfter] as `DV-CONTENT-005` --
  /// including one whose job was dispatched and never ran.
  ///
  /// Run it from a `@DVBackendCron` every minute. Each schedule is marked
  /// dispatched by a conditional write before its job is enqueued, so two
  /// sweeps dispatch it once.
  Future<List<DVContentScheduledJob>> dispatchDue() async {
    final DateTime now = _clock();
    final List<DVContentScheduledJob> dispatched = <DVContentScheduledJob>[];
    for (final DVContentVersion<T> v in await _select(
      'state',
      DVContentState.scheduled.name,
    )) {
      final DVContentScheduledJob? job = await _dispatchOne(
        v,
        now,
        DVContentScheduledAction.publish,
        at: v.scheduledAt,
        id: v.scheduleId,
        dispatchedColumn: 'schedule_dispatched',
      );
      if (job != null) dispatched.add(job);
    }
    for (final DVContentVersion<T> v in await _select(
      'state',
      DVContentState.published.name,
    )) {
      if (v.withdrawId == null) continue;
      final DVContentScheduledJob? job = await _dispatchOne(
        v,
        now,
        DVContentScheduledAction.withdraw,
        at: v.withdrawAt,
        id: v.withdrawId,
        dispatchedColumn: 'withdraw_dispatched',
      );
      if (job != null) dispatched.add(job);
    }
    return dispatched;
  }

  Future<DVContentScheduledJob?> _dispatchOne(
    DVContentVersion<T> version,
    DateTime now,
    DVContentScheduledAction action, {
    required DateTime? at,
    required String? id,
    required String dispatchedColumn,
  }) async {
    if (at == null || id == null || now.isBefore(at)) return null;
    if (now.isAfter(at.add(missedAfter))) {
      await _miss(version, action);
      return null;
    }
    if (version._v[dispatchedColumn] != null) return null;
    final DVContentVersion<T> marked;
    try {
      marked = await _move(version, null, <String, Object?>{
        dispatchedColumn: _stamp(now),
      }, trackMove: false);
    } on DVConflictError {
      return null; // Another sweep got there first.
    }
    final DVContentScheduledJob job = DVContentScheduledJob(
      kind: kind,
      versionId: version.id,
      scheduleId: id,
      action: action,
      at: at,
    );
    try {
      await const DVQueues().dispatch<DVContentScheduledJob>(job, queue: queue);
    } catch (_) {
      // Unmark, so the next sweep tries again rather than waiting for the
      // slot to be reported missed.
      await _move(marked, null, <String, Object?>{
        dispatchedColumn: null,
      }, trackMove: false);
      rethrow;
    }
    return job;
  }

  /// Runs one scheduled job. Safe to deliver more than once.
  Future<DVContentScheduleOutcome> runScheduled(
    DVContentScheduledJob job,
  ) async {
    final DVContentVersion<T>? v = await version(job.versionId);
    final bool publishing = job.action == DVContentScheduledAction.publish;
    if (v == null ||
        v.state !=
            (publishing
                ? DVContentState.scheduled
                : DVContentState.published) ||
        (publishing ? v.scheduleId : v.withdrawId) != job.scheduleId) {
      return DVContentScheduleOutcome.stale;
    }
    final DateTime at = (publishing ? v.scheduledAt : v.withdrawAt)!;
    final DateTime now = _clock();
    if (now.isBefore(at)) return DVContentScheduleOutcome.notDue;
    if (now.isAfter(at.add(missedAfter))) {
      await _miss(v, job.action);
      return DVContentScheduleOutcome.missed;
    }

    final String actorId = (publishing ? v.scheduledBy : v.withdrawBy)!;
    try {
      if (publishing && requireApproval && !_approvalCurrent(v)) {
        await _move(v, null, <String, Object?>{
          'state': DVContentState.approved.name,
          'note': 'scheduled publish refused: changed after approval',
          ..._cleared(_scheduleColumns),
        });
        _report(
          DVContentReport._(
            DVContentReportKind.changedAfterApproval,
            '${DVContentChangedAfterApproval(v.id, approvedRevision: v.approval?.revision, revision: v.revision)}',
            versionId: v.id,
          ),
        );
        return DVContentScheduleOutcome.changedAfterApproval;
      }

      final Object? actor = await _findActor!(actorId);
      if (actor == null ||
          !await _can(actor, DVContentAction.schedule, v.document)) {
        await _move(
          v,
          null,
          publishing
              ? <String, Object?>{
                  'state': DVContentState.approved.name,
                  'note': 'scheduled publish refused: $actorId lacks schedule',
                  ..._cleared(_scheduleColumns),
                }
              : _cleared(_withdrawColumns),
        );
        _report(
          DVContentReport._(
            DVContentReportKind.refused,
            '${DVContentRefused(DVContentAction.schedule, actorId, versionId: v.id)}',
            versionId: v.id,
          ),
        );
        return DVContentScheduleOutcome.refused;
      }

      if (publishing) {
        await _publish(v, actorId);
      } else {
        await _withdraw(v, actorId);
      }
      return DVContentScheduleOutcome.done;
    } on DVConflictError {
      // The version moved between the read and the write: a concurrent run
      // of the same job, or a person acting on it. Either way this run is
      // not the one that decides.
      return DVContentScheduleOutcome.stale;
    }
  }

  Future<void> _miss(
    DVContentVersion<T> version,
    DVContentScheduledAction action,
  ) async {
    final bool publishing = action == DVContentScheduledAction.publish;
    final DateTime at = (publishing
        ? version.scheduledAt
        : version.withdrawAt)!;
    try {
      await _move(
        version,
        null,
        publishing
            ? <String, Object?>{
                'state': DVContentState.approved.name,
                'note': 'scheduled publish missed its slot at ${_stamp(at)}',
                ..._cleared(_scheduleColumns),
              }
            : _cleared(_withdrawColumns),
      );
    } on DVConflictError {
      return; // Somebody else resolved it; they report it.
    }
    _report(
      DVContentReport._(
        DVContentReportKind.missedSlot,
        'a scheduled ${action.name} of ${version.id} missed its slot at '
        '${_stamp(at)} and did not run',
        versionId: version.id,
      ),
    );
  }

  // --- publishing ------------------------------------------------------------

  /// Publishes [version] now, superseding whatever was published.
  ///
  /// Refused without [DVContentAction.publish] (`DV-CONTENT-003`) and, when
  /// approval is required, unless the approval matches the content
  /// (`DV-CONTENT-002`). Cache tags, `onPublished` and the `DV-CONTENT-004`
  /// report happen after the transaction commits.
  Future<DVContentVersion<T>> publish(
    DVContentVersion<T> version, {
    required Object? as,
  }) async {
    final String actor = await _authorize(
      as,
      DVContentAction.publish,
      version.document,
      versionId: version.id,
    );
    _expect(
      version,
      'publish',
      requireApproval
          ? const <DVContentState>{
              DVContentState.approved,
              DVContentState.scheduled,
            }
          : const <DVContentState>{
              DVContentState.draft,
              DVContentState.approved,
              DVContentState.scheduled,
            },
    );
    _requireApproved(version);
    return _publish(version, actor);
  }

  /// Publishes a superseded [version] again: a rollback. Its approval is the
  /// one it was published with.
  Future<DVContentVersion<T>> restore(
    DVContentVersion<T> version, {
    required Object? as,
  }) async {
    final String actor = await _authorize(
      as,
      DVContentAction.publish,
      version.document,
      versionId: version.id,
    );
    _expect(version, 'restore', const <DVContentState>{
      DVContentState.superseded,
    });
    _requireApproved(version);
    return _publish(version, actor);
  }

  /// Withdraws [version]. A published version stops being served; an open one
  /// is abandoned, and any schedule on it stops.
  Future<DVContentVersion<T>> withdraw(
    DVContentVersion<T> version, {
    required Object? as,
  }) async {
    final bool live =
        version.state == DVContentState.published ||
        version.state == DVContentState.scheduled;
    final String actor = await _authorize(
      as,
      live ? DVContentAction.publish : DVContentAction.edit,
      version.document,
      versionId: version.id,
    );
    _expect(version, 'withdraw', const <DVContentState>{
      DVContentState.draft,
      DVContentState.review,
      DVContentState.approved,
      DVContentState.scheduled,
      DVContentState.published,
    });
    return _withdraw(version, actor);
  }

  Future<DVContentVersion<T>> _publish(
    DVContentVersion<T> version,
    String actor,
  ) {
    return _transactions((DVContext context) async {
      final DVContentVersion<T>? previous = await current(version.documentId);
      if (previous != null && previous.id != version.id) {
        await _move(previous, actor, <String, Object?>{
          'state': DVContentState.superseded.name,
          ..._cleared(_withdrawColumns),
        });
      }
      final DVContentVersion<T> published =
          await _move(version, actor, <String, Object?>{
            'state': DVContentState.published.name,
            'published_at': _stamp(_clock()),
            'published_by': actor,
            ..._cleared(_scheduleColumns),
            ..._cleared(_withdrawColumns),
          });
      context.afterCommit(() async {
        if (published.machineTranslated.isNotEmpty) {
          _report(
            DVContentReport._(
              DVContentReportKind.machineTranslated,
              '${published.id} was published with machine-translated strings '
              'no human reviewed: ${(published.machineTranslated.toList()..sort()).join(', ')}',
              versionId: published.id,
              keys: published.machineTranslated,
            ),
          );
        }
        await _invalidate(published);
        await _onPublished?.call(published);
      });
      return published;
    });
  }

  Future<DVContentVersion<T>> _withdraw(
    DVContentVersion<T> version,
    String actor,
  ) {
    return _transactions((DVContext context) async {
      final bool wasLive = version.state == DVContentState.published;
      final DVContentVersion<T> withdrawn =
          await _move(version, actor, <String, Object?>{
            'state': DVContentState.withdrawn.name,
            ..._cleared(_scheduleColumns),
            ..._cleared(_withdrawColumns),
          });
      if (wasLive) {
        context.afterCommit(() async {
          await _invalidate(withdrawn);
          await _onWithdrawn?.call(withdrawn);
        });
      }
      return withdrawn;
    });
  }

  Future<void> _invalidate(DVContentVersion<T> version) async {
    for (final String tag in _tagsFor(version)) {
      await _revalidateTag(tag);
    }
  }

  // --- internals -------------------------------------------------------------

  List<String> _tagsFor(DVContentVersion<T> version) => <String>[
    documentTag(version.documentId),
    ...?_cacheTags?.call(version),
  ];

  Future<List<DVContentVersion<T>>> _select(String column, String value) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT id FROM $table WHERE kind = ? AND $column = ?',
      <Object?>[kind, value],
    );
    final List<DVContentVersion<T>> found = <DVContentVersion<T>>[];
    for (final Map<String, Object?> row in rows) {
      final DVContentVersion<T>? v = await version(row['id']! as String);
      // Re-checked after the read: the row may have moved in between.
      if (v != null && '${v._v[column]}' == value) found.add(v);
    }
    found.sort(
      (DVContentVersion<T> a, DVContentVersion<T> b) =>
          a.documentId == b.documentId
          ? a.number.compareTo(b.number)
          : a.documentId.compareTo(b.documentId),
    );
    return found;
  }

  /// Writes [changes] over [base], conditional on the stored version still
  /// being the one [base] was read at.
  ///
  /// Always against the caller's snapshot and never a fresh read: re-reading
  /// here would let a reviewer holding revision 1 approve revision 2.
  Future<DVContentVersion<T>> _move(
    DVContentVersion<T> base,
    String? actor,
    Map<String, Object?> changes, {
    bool trackMove = true,
  }) async {
    final DVWriteResult result = await _table.write(
      <String, Object?>{
        ...base._record.values,
        ...changes,
        if (trackMove) 'moved_at': _stamp(_clock()),
      },
      base: base._record,
      actor: actor,
    );
    return _fromRecord(result.record);
  }

  DVContentVersion<T> _fromRecord(DVRecord record) => DVContentVersion<T>._(
    record,
    _decode(
      (jsonDecode(record.values['body']! as String) as Map)
          .cast<String, Object?>(),
    ),
  );

  Future<bool> _can(Object? user, String action, T document) async =>
      _authorization.can<Object?, T>(user, action, document);

  Future<String> _authorize(
    Object? user,
    String action,
    T document, {
    String? versionId,
  }) async {
    final String actor = _actorId(user);
    if (await _can(user, action, document)) return actor;
    final DVContentRefused refused = DVContentRefused(
      action,
      actor,
      versionId: versionId,
    );
    if (refused.code != null) {
      _report(
        DVContentReport._(
          DVContentReportKind.refused,
          '$refused',
          versionId: versionId,
        ),
      );
    }
    throw refused;
  }

  void _expect(
    DVContentVersion<T> version,
    String operation,
    Set<DVContentState> allowed,
  ) {
    if (!allowed.contains(version.state)) {
      throw DVContentInvalidTransition(version.id, version.state, operation);
    }
  }

  bool _approvalCurrent(DVContentVersion<T> version) =>
      version.approval?.matches(version) ?? false;

  void _requireApproved(DVContentVersion<T> version) {
    if (!requireApproval || _approvalCurrent(version)) return;
    final DVContentChangedAfterApproval error = DVContentChangedAfterApproval(
      version.id,
      approvedRevision: version.approval?.revision,
      revision: version.revision,
    );
    _report(
      DVContentReport._(
        DVContentReportKind.changedAfterApproval,
        '$error',
        versionId: version.id,
      ),
    );
    throw error;
  }

  void _requireFindActor() {
    if (_findActor == null) {
      throw StateError(
        'Scheduling needs findActor: the scheduler\'s authority is checked '
        'again when the slot arrives, and a job carries an id, not a user.',
      );
    }
  }

  List<int> _requirePreviewKey() {
    final List<int>? key = _previewKey;
    if (key == null || key.length < 16) {
      throw StateError(
        'Preview links need a previewKey of at least 16 bytes. There is no '
        'default: a guessable key is a published draft.',
      );
    }
    return key;
  }

  /// The version id a valid [token] names for [documentId], or null.
  String? _verifyPreview(String token, String documentId) {
    final List<int>? key = _previewKey;
    if (key == null) return null;
    final int dot = token.indexOf('.');
    if (dot <= 0 || dot == token.length - 1) return null;
    final String payload = token.substring(0, dot);
    final List<int> expected = Hmac(
      sha256,
      key,
    ).convert(utf8.encode(payload)).bytes;
    final List<int> given;
    final Map<String, Object?> claims;
    try {
      given = base64Url.decode(base64Url.normalize(token.substring(dot + 1)));
      if (!_sameBytes(expected, given)) return null;
      claims =
          (jsonDecode(
                    utf8.decode(base64Url.decode(base64Url.normalize(payload))),
                  )
                  as Map)
              .cast<String, Object?>();
    } on FormatException {
      return null;
    }
    final Object? expires = claims['e'];
    if (claims['k'] != kind ||
        claims['d'] != documentId ||
        expires is! int ||
        _clock().millisecondsSinceEpoch >= expires) {
      return null;
    }
    final Object? versionId = claims['v'];
    return versionId is String ? versionId : null;
  }

  void _report(DVContentReport report) {
    _reports.add(report);
    if (_reports.length > 1000) _reports.removeAt(0);
    if (report.kind == DVContentReportKind.refused) {
      DVObservability.logger.error('$report');
    } else {
      DVObservability.logger.warn('$report');
    }
  }

  String _newId() => _b64(List<int>.generate(12, (_) => _random.nextInt(256)));

  static bool _open(DVContentState state) =>
      state == DVContentState.draft ||
      state == DVContentState.review ||
      state == DVContentState.approved ||
      state == DVContentState.scheduled;

  static Map<String, Object?> _cleared(List<String> columns) =>
      <String, Object?>{for (final String column in columns) column: null};
}

String _digest(String body) => sha256.convert(utf8.encode(body)).toString();

/// JSON with object keys sorted at every depth, so equal content has one
/// encoding and one digest.
String _canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final List<String> keys = <String>[for (final Object? k in value.keys) '$k']
      ..sort();
    return <String, Object?>{
      for (final String k in keys) k: _canonical(value[k]),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final Object? v in value) _canonical(v)];
  }
  return value;
}

String _encodeSet(Set<String> values) => jsonEncode(values.toList()..sort());

Set<String> _decodeSet(Object? raw) => raw is String && raw.isNotEmpty
    ? <String>{for (final Object? v in jsonDecode(raw) as List) '$v'}
    : <String>{};

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  int diff = 0;
  for (int i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.parse(value) : null;

/// Millisecond UTC ISO-8601, so stamps compare as strings and read back equal.
String _stamp(DateTime time) => DateTime.fromMillisecondsSinceEpoch(
  time.toUtc().millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();
