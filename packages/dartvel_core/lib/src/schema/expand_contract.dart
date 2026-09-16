/// The five phases of an expand/contract, and the gates between them.
///
/// Each phase is a separate deploy. A phase boundary is where a rollback is
/// still cheap, and an expand/contract compressed into one release is the
/// outage it was meant to avoid -- so a release that already ran a phase
/// cannot run the next one.
///
/// Verification and the read switch are separate. [DVSchemaEvolution.verify]
/// records that every chunk is backfilled, every chunk verified, and the
/// dual-write discrepancy counter at zero for the whole verification window;
/// it is the job's result, not a deploy, and a discrepancy recorded afterwards
/// takes it away. [DVSchemaEvolution.switchReads] then moves reads to the new
/// shape in a release of its own, while both shapes are still written, so
/// every release that reads the old shape is still a safe rollback target.
///
/// The contract stops writing the old shape and a later release drops it.
/// Both are decided by Backend Release Management's [DVContractDecision], the
/// same decision its contract-step gate makes: refused while any client inside
/// the protocol window still reads the old shape -- the release that expands
/// raised the protocol, and a client older than it knows only the old column
/// -- and while the release being replaced still reads it.
library dartvel_core.schema.expand_contract;

import 'dart:convert';

import '../database/adapter.dart';
import '../release/contract_gate.dart'
    show DVContractDecision, DVContractReplacing;
import '../release/release_record.dart' show DVReleaseMigrationPhase;
import '../release/rollback.dart' show DVMigrationPhaseSource;
import 'backfill.dart';
import 'schema_planner.dart' show DVSchemaFinding;

/// The phases, in order.
enum DVSchemaPhase {
  /// The new column exists beside the old one; nothing reads it.
  expand,

  /// Generated model code writes both shapes; reads stay on the old one.
  dualWrite,

  /// Existing rows are copied, chunk by chunk.
  backfill,

  /// Every chunk is compared on both shapes. Once they agree for the whole
  /// window the migration is verified, and a release of its own moves reads
  /// to the new shape while both shapes are still written.
  verify,

  /// Dual-write stops, so the old shape is no longer kept current. Reads moved
  /// in an earlier release; the old column is dropped in a later one.
  contract,
}

/// What a gate decided.
final class DVSchemaPhaseResult {
  const DVSchemaPhaseResult({
    required this.allowed,
    required this.phase,
    this.findings = const <DVSchemaFinding>[],
    this.reasons = const <String>[],
  });

  final bool allowed;

  /// The phase after the decision.
  final DVSchemaPhase phase;

  /// Coded refusals: `DV-SCHEMA-004`, `-005`, `-007`.
  final List<DVSchemaFinding> findings;

  /// Refusals the specification gives no code: a release reused, a backfill
  /// unfinished, a window not yet elapsed, verification missing, a client
  /// histogram missing, a release being replaced that still reads the old
  /// shape.
  final List<String> reasons;
}

/// One expand/contract in progress.
final class DVSchemaEvolution {
  DVSchemaEvolution._({
    required this.id,
    required this.expandProtocol,
    required this.verificationWindow,
    required DVSchemaPhase phase,
    required Map<DVSchemaPhase, String> releases,
    required Map<DVSchemaPhase, DateTime> enteredAt,
    required List<DateTime> discrepancies,
    required String? dropRelease,
    required DateTime? verifiedAt,
    required String? readSwitchRelease,
  }) : _phase = phase,
       _releases = releases,
       _enteredAt = enteredAt,
       _discrepancies = discrepancies,
       _dropRelease = dropRelease,
       _verifiedAt = verifiedAt,
       _readSwitchRelease = readSwitchRelease;

  /// Starts an expand/contract: [release] ran the expand at [at].
  ///
  /// [expandProtocol] is the protocol version that release carries. A client
  /// on an older protocol reads the old shape.
  factory DVSchemaEvolution.expand({
    required String id,
    required String release,
    required DateTime at,
    required int expandProtocol,
    Duration verificationWindow = const Duration(hours: 1),
  }) => DVSchemaEvolution._(
    id: id,
    expandProtocol: expandProtocol,
    verificationWindow: verificationWindow,
    phase: DVSchemaPhase.expand,
    releases: <DVSchemaPhase, String>{DVSchemaPhase.expand: release},
    enteredAt: <DVSchemaPhase, DateTime>{DVSchemaPhase.expand: at},
    discrepancies: <DateTime>[],
    dropRelease: null,
    verifiedAt: null,
    readSwitchRelease: null,
  );

  /// Reads a saved state. A state saved before verification and the read
  /// switch were recorded reads as neither: verified again, not assumed.
  factory DVSchemaEvolution.fromJson(Map<String, Object?> json) {
    DVSchemaPhase phaseNamed(Object? name) => DVSchemaPhase.values.firstWhere(
      (DVSchemaPhase p) => p.name == name,
      orElse: () => throw FormatException('Not a schema phase', '$name'),
    );
    final Map<Object?, Object?> releases =
        json['releases']! as Map<Object?, Object?>;
    final Map<Object?, Object?> entered =
        json['enteredAt']! as Map<Object?, Object?>;
    final Object? verifiedAt = json['verifiedAt'];
    return DVSchemaEvolution._(
      id: json['id']! as String,
      expandProtocol: (json['expandProtocol']! as num).toInt(),
      verificationWindow: Duration(
        microseconds: (json['verificationWindowMicros']! as num).toInt(),
      ),
      phase: phaseNamed(json['phase']),
      releases: <DVSchemaPhase, String>{
        for (final MapEntry<Object?, Object?> e in releases.entries)
          phaseNamed(e.key): '${e.value}',
      },
      enteredAt: <DVSchemaPhase, DateTime>{
        for (final MapEntry<Object?, Object?> e in entered.entries)
          phaseNamed(e.key): DateTime.parse('${e.value}'),
      },
      discrepancies: <DateTime>[
        for (final Object? at in json['discrepancies']! as List<Object?>)
          DateTime.parse('$at'),
      ],
      dropRelease: json['oldShapeDroppedIn'] as String?,
      verifiedAt: verifiedAt == null ? null : DateTime.parse('$verifiedAt'),
      readSwitchRelease: json['readsSwitchedIn'] as String?,
    );
  }

  final String id;
  final int expandProtocol;
  final Duration verificationWindow;

  DVSchemaPhase _phase;
  final Map<DVSchemaPhase, String> _releases;
  final Map<DVSchemaPhase, DateTime> _enteredAt;
  final List<DateTime> _discrepancies;
  String? _dropRelease;
  DateTime? _verifiedAt;
  String? _readSwitchRelease;

  DVSchemaPhase get phase => _phase;

  /// Dual-write discrepancies recorded so far.
  int get discrepancies => _discrepancies.length;

  /// Every chunk agreed for the whole window, and no discrepancy has been
  /// recorded since.
  bool get verified => _verifiedAt != null;

  /// A release has moved reads to the new shape.
  bool get readsSwitched => _readSwitchRelease != null;

  bool get oldShapeDropped => _dropRelease != null;

  /// Where this migration stands in Backend Release Management's terms, which
  /// its rollback planner reads to decide what a rollback can restore.
  ///
  /// `backfilled` only once the gate into verify has seen the backfill
  /// complete, so the backfill phase itself still reads as `dualWriting`.
  /// `verified` while verification stands and reads have not moved, and
  /// `readSwitched` once they have: both shapes are still written in either,
  /// so a release reading the old shape is still a safe target. `contracted`
  /// from the contract on, not only once the old column is dropped: the
  /// contract stops writing the old shape, and a release that reads a column
  /// nobody writes is not one a rollback may restore.
  DVReleaseMigrationPhase get releasePhase {
    if (oldShapeDropped) return DVReleaseMigrationPhase.contracted;
    return switch (_phase) {
      DVSchemaPhase.expand => DVReleaseMigrationPhase.expanded,
      DVSchemaPhase.dualWrite => DVReleaseMigrationPhase.dualWriting,
      DVSchemaPhase.backfill => DVReleaseMigrationPhase.dualWriting,
      DVSchemaPhase.verify =>
        readsSwitched
            ? DVReleaseMigrationPhase.readSwitched
            : verified
            ? DVReleaseMigrationPhase.verified
            : DVReleaseMigrationPhase.backfilled,
      DVSchemaPhase.contract => DVReleaseMigrationPhase.contracted,
    };
  }

  /// A write that reached one shape and not the other, seen at [at]. It takes
  /// verification away: the counter has to stay at zero for a whole window
  /// again before reads may move.
  void recordDiscrepancy(DateTime at) {
    _discrepancies.add(at);
    _verifiedAt = null;
  }

  /// Records every `DV-SCHEMA-007` among [findings] as a discrepancy at [at].
  void recordFindings(Iterable<DVSchemaFinding> findings, DateTime at) {
    for (final DVSchemaFinding finding in findings) {
      if (finding.code == 'DV-SCHEMA-007') recordDiscrepancy(at);
    }
  }

  /// Records that the backfill verifies: every chunk backfilled, every chunk
  /// verified, and no dual-write discrepancy for the whole window since the
  /// verify phase began. Not a deploy, so it names no release.
  DVSchemaPhaseResult verify({
    required DateTime now,
    required DVBackfillProgress? progress,
  }) {
    if (_phase != DVSchemaPhase.verify) {
      return _refused(
        reasons: <String>[
          '$id is in its ${_phase.name} phase; verification runs in the '
              'verify phase.',
        ],
      );
    }
    final List<String> reasons = <String>[];
    final List<DVSchemaFinding> findings = <DVSchemaFinding>[];
    _chunks(progress, reasons, findings);
    _window(now, reasons, findings);
    if (reasons.isNotEmpty || findings.isNotEmpty) {
      return _refused(reasons: reasons, findings: findings);
    }
    _verifiedAt = now;
    return DVSchemaPhaseResult(allowed: true, phase: _phase);
  }

  /// Moves reads to the new shape in [release], once verified. Both shapes are
  /// still written, so the old one stays current for any release that reads
  /// it. [progress] is checked again: a chunk that has since stopped matching
  /// refuses the switch.
  DVSchemaPhaseResult switchReads({
    required String release,
    required DVBackfillProgress? progress,
  }) {
    if (_phase != DVSchemaPhase.verify || readsSwitched) {
      return _refused(
        reasons: <String>[
          readsSwitched
              ? 'Reads of $id already moved in $_readSwitchRelease.'
              : '$id is in its ${_phase.name} phase; reads switch in the '
                    'verify phase.',
        ],
      );
    }
    final String? reused = _reusedBy(release);
    if (reused != null) return _refused(reasons: <String>[reused]);
    final List<String> reasons = <String>[];
    final List<DVSchemaFinding> findings = <DVSchemaFinding>[];
    if (!verified) {
      reasons.add(
        '$id is not verified: every chunk has to agree on both shapes, with no '
        'dual-write discrepancy, for the whole verification window.',
      );
    }
    _chunks(progress, reasons, findings);
    if (reasons.isNotEmpty || findings.isNotEmpty) {
      return _refused(reasons: reasons, findings: findings);
    }
    _readSwitchRelease = release;
    return DVSchemaPhaseResult(allowed: true, phase: _phase);
  }

  /// Moves to the next phase in [release], if its gate allows.
  ///
  /// [progress] is the backfill's, needed to enter verify.
  /// [clientProtocols] is every protocol version seen calling inside the
  /// window, needed for the contract; null means "not known", and is refused
  /// rather than read as "no clients".
  DVSchemaPhaseResult advance({
    required String release,
    required DateTime now,
    DVBackfillProgress? progress,
    Set<int>? clientProtocols,
  }) {
    if (_phase == DVSchemaPhase.contract) {
      return _refused(
        reasons: <String>[
          '$id is already contracted. The old shape is removed with '
              'dropOldShape, in a later release.',
        ],
      );
    }
    final String? reused = _reusedBy(release);
    if (reused != null) return _refused(reasons: <String>[reused]);

    final DVSchemaPhase next = DVSchemaPhase.values[_phase.index + 1];
    final List<String> reasons = <String>[];
    final List<DVSchemaFinding> findings = <DVSchemaFinding>[];

    switch (next) {
      case DVSchemaPhase.expand:
      case DVSchemaPhase.dualWrite:
      case DVSchemaPhase.backfill:
        break;
      case DVSchemaPhase.verify:
        if (progress == null || !progress.complete) {
          reasons.add(
            'The backfill of $id is not complete'
            '${progress == null ? '' : ' (${progress.rows} rows in '
                      '${progress.chunks.length} chunks so far)'}.',
          );
        }
      case DVSchemaPhase.contract:
        _contract(clientProtocols, reasons, findings);
    }

    if (reasons.isNotEmpty || findings.isNotEmpty) {
      return _refused(reasons: reasons, findings: findings);
    }
    _phase = next;
    _releases[next] = release;
    _enteredAt[next] = now;
    return DVSchemaPhaseResult(allowed: true, phase: _phase);
  }

  /// Drops the old shape, in a release after the one that contracted.
  DVSchemaPhaseResult dropOldShape({
    required String release,
    required Set<int>? clientProtocols,
  }) {
    if (_phase != DVSchemaPhase.contract || oldShapeDropped) {
      return _refused(
        reasons: <String>[
          oldShapeDropped
              ? 'The old shape of $id was already dropped in $_dropRelease.'
              : '$id has not contracted; the old shape is still written.',
        ],
      );
    }
    final String? reused = _reusedBy(release);
    if (reused != null) return _refused(reasons: <String>[reused]);
    final List<String> reasons = <String>[];
    final List<DVSchemaFinding> findings = <DVSchemaFinding>[];
    _contract(clientProtocols, reasons, findings);
    if (reasons.isNotEmpty || findings.isNotEmpty) {
      return _refused(reasons: reasons, findings: findings);
    }
    _dropRelease = release;
    return DVSchemaPhaseResult(allowed: true, phase: _phase);
  }

  String? _reusedBy(String release) {
    final Map<String, String> ran = <String, String>{
      for (final MapEntry<DVSchemaPhase, String> e in _releases.entries)
        e.value: 'the ${e.key.name} phase',
      if (_readSwitchRelease != null) _readSwitchRelease!: 'the read switch',
    };
    final String? step = ran[release];
    if (step == null) return null;
    return 'Release $release already ran $step of $id. Each phase is a '
        'separate deploy, because a phase boundary is where a rollback is '
        'still cheap.';
  }

  /// The release that ran the latest step: the one a contract replaces.
  String get _latestRelease =>
      _dropRelease ??
      _releases[DVSchemaPhase.contract] ??
      _readSwitchRelease ??
      _releases[_phase]!;

  void _chunks(
    DVBackfillProgress? progress,
    List<String> reasons,
    List<DVSchemaFinding> findings,
  ) {
    if (progress == null || !progress.complete) {
      reasons.add('The backfill of $id is not complete.');
    }
    if (progress == null) return;
    final List<DVBackfillChunk> unverified = progress.unverified;
    if (unverified.isNotEmpty) {
      reasons.add(
        'Chunks of $id not yet verified: '
        '${unverified.map((DVBackfillChunk c) => c.name).join(', ')}.',
      );
    }
    for (final DVBackfillChunk chunk in progress.mismatched) {
      findings.add(
        DVSchemaFinding(
          'DV-SCHEMA-004',
          'Chunk ${chunk.name} of $id does not match on both shapes; the '
              'read switch is refused until it verifies.',
          chunk: chunk.name,
        ),
      );
    }
  }

  void _window(
    DateTime now,
    List<String> reasons,
    List<DVSchemaFinding> findings,
  ) {
    final DateTime? verifying = _enteredAt[DVSchemaPhase.verify];
    final DateTime windowOpened = now.subtract(verificationWindow);
    if (verifying == null || verifying.isAfter(windowOpened)) {
      reasons.add(
        'The verification window of $id has not elapsed: it needs '
        '$verificationWindow of verification, which ends at '
        '${(verifying ?? now).add(verificationWindow).toIso8601String()}.',
      );
    }
    final List<DateTime> recent = <DateTime>[
      for (final DateTime at in _discrepancies)
        if (at.isAfter(windowOpened)) at,
    ];
    if (recent.isNotEmpty) {
      findings.add(
        DVSchemaFinding(
          'DV-SCHEMA-007',
          '${recent.length} dual-write discrepancy(ies) in $id within the '
              'verification window, the latest at '
              '${recent.last.toIso8601String()}. The counter has to stay at zero '
              'for the whole window.',
        ),
      );
    }
  }

  /// The contract and the drop, decided by [DVContractDecision]: the release
  /// being replaced is the one that ran the latest step, built for where the
  /// migration stands now.
  void _contract(
    Set<int>? clientProtocols,
    List<String> reasons,
    List<DVSchemaFinding> findings,
  ) {
    final DVContractReplacing replacing = (
      release: _latestRelease,
      builtFor: releasePhase,
    );
    final DVContractDecision decision = DVContractDecision.evaluate(
      windowed: clientProtocols,
      readsOldShape: (int protocol) => protocol < expandProtocol,
      replacing: replacing,
    );
    if (!decision.windowKnown) {
      reasons.add(
        'No client protocol histogram was given for $id, so whether a client '
        'still reads the old shape is unknown. Pass the protocol versions '
        'seen inside the window -- an empty set when there are none.',
      );
    }
    if (decision.readers.isNotEmpty) {
      findings.add(
        DVSchemaFinding(
          'DV-SCHEMA-005',
          'Clients on protocol ${decision.readers.join(', ')} are inside the '
              'window and read the old shape of $id, which protocol '
              '$expandProtocol replaced.',
        ),
      );
    }
    if (decision.replacingReadsOldShape) {
      reasons.add(
        '${replacing.release}, the release being replaced, was built for '
        '${replacing.builtFor!.name} and still reads the old shape of $id. '
        'Reads move to the new shape with switchReads, in a release before '
        'the contract.',
      );
    }
  }

  DVSchemaPhaseResult _refused({
    List<String> reasons = const <String>[],
    List<DVSchemaFinding> findings = const <DVSchemaFinding>[],
  }) => DVSchemaPhaseResult(
    allowed: false,
    phase: _phase,
    reasons: List<String>.unmodifiable(reasons),
    findings: List<DVSchemaFinding>.unmodifiable(findings),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'phase': _phase.name,
    'expandProtocol': expandProtocol,
    'verificationWindowMicros': verificationWindow.inMicroseconds,
    'releases': <String, Object?>{
      for (final MapEntry<DVSchemaPhase, String> e in _releases.entries)
        e.key.name: e.value,
    },
    'enteredAt': <String, Object?>{
      for (final MapEntry<DVSchemaPhase, DateTime> e in _enteredAt.entries)
        e.key.name: e.value.toIso8601String(),
    },
    'discrepancies': <String>[
      for (final DateTime at in _discrepancies) at.toIso8601String(),
    ],
    'oldShapeDroppedIn': _dropRelease,
    'verifiedAt': _verifiedAt?.toIso8601String(),
    'readsSwitchedIn': _readSwitchRelease,
  };
}

/// Keeps [DVSchemaEvolution]s in the database, so a phase decided in one
/// release is still decided in the next.
final class DVSchemaEvolutionStore {
  DVSchemaEvolutionStore(this.database);

  static const String _table = 'dv_schema_evolution';

  final DVDatabaseAdapter database;
  bool _prepared = false;

  Future<void> _prepare() async {
    if (_prepared) return;
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $_table (id TEXT, state TEXT)',
    );
    _prepared = true;
  }

  Future<void> save(DVSchemaEvolution evolution) async {
    await _prepare();
    final String state = jsonEncode(evolution.toJson());
    final int updated = await database.execute(
      'UPDATE $_table SET state = ? WHERE id = ?',
      <Object?>[state, evolution.id],
    );
    if (updated == 0) {
      await database.execute(
        'INSERT INTO $_table (id, state) VALUES (?, ?)',
        <Object?>[evolution.id, state],
      );
    }
  }

  Future<DVSchemaEvolution?> load(String id) async {
    await _prepare();
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT state FROM $_table WHERE id = ?',
      <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return DVSchemaEvolution.fromJson(
      jsonDecode('${rows.single['state']}') as Map<String, Object?>,
    );
  }

  /// The phase each migration has reached, for Backend Release Management's
  /// rollback and contract gates. Null for a migration this store has never
  /// recorded, which those gates treat as not knowable.
  DVMigrationPhaseSource get phaseSource =>
      (String migration) async => (await load(migration))?.releasePhase;
}
