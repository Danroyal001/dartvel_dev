/// The migration planner and the deploy gate.
///
/// The planner classifies each change by asking the adapter, refuses a
/// blocking change as written where a safe version of it exists and plans that
/// version instead, and treats a change nobody can classify as blocking. The
/// gate refuses a blocking change against production unless an explicit,
/// logged override accompanies it.
library dartvel_core.schema.planner;

import '../database/adapter.dart';
import '../diagnostics/diagnostics.dart';
import 'schema_change.dart';

/// One diagnostic raised while planning, gating or verifying a schema change.
final class DVSchemaFinding {
  DVSchemaFinding(this.code, this.message, {this.change, this.chunk})
    : level = _registered(code).level;

  /// A `DV-SCHEMA-*` code from the diagnostic registry.
  final String code;

  /// The registry's level for [code], so a finding cannot disagree with it.
  final String level;

  final String message;

  /// The change the finding is about, when there is one.
  final DVSchemaChange? change;

  /// The chunk the finding names, for a verification mismatch.
  final String? chunk;

  static DVDiagnostic _registered(String code) {
    final DVDiagnostic? diagnostic = DVDiagnostics.find(code);
    if (diagnostic == null) {
      throw ArgumentError.value(code, 'code', 'not a registered diagnostic');
    }
    return diagnostic;
  }

  @override
  String toString() => '$code ($level): $message';
}

/// The safe version of a blocking change: five phases, each its own deploy.
///
/// 1. expand -- [expand] adds the new column alongside the old one.
/// 2. dual-write -- generated model code writes both; reads stay on the old.
/// 3. backfill -- existing rows are copied from [sourceColumn] to
///    [targetColumn] in chunks.
/// 4. verify -- every chunk is compared on both shapes.
/// 5. contract -- reads move to the new shape, and [contract] removes the old
///    one in a later release.
final class DVExpandContractPlan {
  const DVExpandContractPlan({
    required this.original,
    required this.expand,
    required this.sourceColumn,
    required this.targetColumn,
    required this.contract,
    required this.expandClass,
    required this.contractClass,
  });

  final DVSchemaChange original;
  final DVAddColumn expand;
  final String sourceColumn;
  final String targetColumn;
  final List<DVSchemaChange> contract;

  /// What [expand] costs on this server. Never blocking: a safe version that
  /// blocks is not offered.
  final DVSchemaChangeClass expandClass;

  /// The most expensive of the [contract] changes on this server.
  ///
  /// Reported rather than hidden. On SQLite the eventual drop is itself a
  /// rebuild, and a plan that concealed the cost of its last step would be
  /// the surprise it exists to prevent.
  final DVSchemaChangeClass contractClass;
}

/// One change in a plan, and what it costs.
final class DVSchemaPlanStep {
  const DVSchemaPlanStep({
    required this.change,
    required this.changeClass,
    required this.classifiedByAdapter,
    this.expandContract,
    this.rows,
  });

  final DVSchemaChange change;

  /// The class the adapter gave, or blocking when it could not give one.
  final DVSchemaChangeClass changeClass;

  /// False when the adapter could not classify the change (`DV-SCHEMA-006`).
  final bool classifiedByAdapter;

  /// The safe version planned in its place, when this change blocks and one
  /// exists.
  final DVExpandContractPlan? expandContract;

  /// Rows in the table, when the plan was made against a snapshot.
  final int? rows;

  /// A blocking change that will not run as written, because its safe
  /// version runs instead.
  bool get refusedAsWritten =>
      changeClass == DVSchemaChangeClass.blocking && expandContract != null;

  /// A change that will hold readers or writers when it runs.
  bool get runsBlocking =>
      changeClass == DVSchemaChangeClass.blocking && expandContract == null;
}

/// A classified migration.
final class DVSchemaPlan {
  const DVSchemaPlan({required this.steps, required this.findings});

  final List<DVSchemaPlanStep> steps;
  final List<DVSchemaFinding> findings;

  /// The steps that will hold readers or writers as they run.
  List<DVSchemaPlanStep> get blocking =>
      steps.where((DVSchemaPlanStep s) => s.runsBlocking).toList();

  /// The plan as `dartvel db migrate --plan` prints it: one line per change.
  String describe() {
    final StringBuffer out = StringBuffer();
    for (final DVSchemaPlanStep step in steps) {
      out.write('${step.changeClass.name.padRight(8)}  ${step.change}');
      if (step.rows != null) out.write('  (${step.rows} rows)');
      if (!step.classifiedByAdapter) out.write('  [unclassified]');
      out.writeln();
      final DVExpandContractPlan? safe = step.expandContract;
      if (safe != null) {
        out
          ..writeln('          refused as written; planned as expand/contract:')
          ..writeln(
            '            1. expand      ${safe.expand} '
            '(${safe.expandClass.name})',
          )
          ..writeln(
            '            2. dual-write  ${safe.sourceColumn} and '
            '${safe.targetColumn}',
          )
          ..writeln(
            '            3. backfill    ${safe.sourceColumn} -> '
            '${safe.targetColumn}, chunked',
          )
          ..writeln('            4. verify      per-chunk hash on both shapes')
          ..writeln(
            '            5. contract    '
            '${safe.contract.join('; ')} (${safe.contractClass.name})',
          );
      }
    }
    for (final DVSchemaFinding finding in findings) {
      out.writeln(finding);
    }
    return out.toString();
  }
}

/// Classifies changes and plans the safe version of a blocking one.
final class DVSchemaPlanner {
  const DVSchemaPlanner();

  /// Plans [changes] with the classification [classifier] gives.
  ///
  /// A null [classifier] is a server nothing here knows the rules for, and
  /// every change is then blocking. [rows] is the row count per table, from a
  /// snapshot, carried onto each step.
  Future<DVSchemaPlan> plan(
    Iterable<DVSchemaChange> changes,
    DVSchemaClassifier? classifier, {
    Map<String, int> rows = const <String, int>{},
  }) async {
    final List<DVSchemaPlanStep> steps = <DVSchemaPlanStep>[];
    final List<DVSchemaFinding> findings = <DVSchemaFinding>[];

    Future<DVSchemaChangeClass?> ask(DVSchemaChange change) async =>
        classifier == null ? null : await classifier.classify(change);

    for (final DVSchemaChange change in changes) {
      final DVSchemaChangeClass? given = await ask(change);
      if (given == null) {
        findings.add(
          DVSchemaFinding(
            'DV-SCHEMA-006',
            'The adapter cannot classify "$change", so it is treated as '
                'blocking.',
            change: change,
          ),
        );
      }
      final DVSchemaChangeClass changeClass =
          given ?? DVSchemaChangeClass.blocking;

      DVExpandContractPlan? safe;
      if (changeClass == DVSchemaChangeClass.blocking) {
        safe = await _expandContract(change, ask);
        if (safe != null) {
          findings.add(
            DVSchemaFinding(
              'DV-SCHEMA-001',
              '"$change" blocks readers or writers, and an expand/contract '
                  'plan exists for it; the plan runs instead.',
              change: change,
            ),
          );
        }
      }

      steps.add(
        DVSchemaPlanStep(
          change: change,
          changeClass: changeClass,
          classifiedByAdapter: given != null,
          expandContract: safe,
          rows: rows[change.table],
        ),
      );
    }
    return DVSchemaPlan(
      steps: List<DVSchemaPlanStep>.unmodifiable(steps),
      findings: List<DVSchemaFinding>.unmodifiable(findings),
    );
  }

  /// Plans [changes] with the classification [adapter] gives for the server
  /// it is connected to.
  Future<DVSchemaPlan> planFor(
    DVDatabaseAdapter adapter,
    Iterable<DVSchemaChange> changes,
  ) => plan(
    changes,
    adapter is DVSchemaClassifier ? adapter as DVSchemaClassifier : null,
  );

  /// The name the new shape is written under until the contract renames it.
  static String shadowColumn(String column) => '${column}__dv_next';

  Future<DVExpandContractPlan?> _expandContract(
    DVSchemaChange change,
    Future<DVSchemaChangeClass?> Function(DVSchemaChange) ask,
  ) async {
    // A changed type is the change with a general safe version: the new
    // shape is a new column, which every shipped server adds without
    // holding anybody.
    if (change is! DVChangeColumnType) return null;
    final String target = shadowColumn(change.column);
    final DVAddColumn expand = DVAddColumn(
      change.table,
      target,
      type: change.to,
    );
    final DVSchemaChangeClass? expandClass = await ask(expand);
    // A safe version that blocks on this server is not a safe version.
    if (expandClass == null || expandClass == DVSchemaChangeClass.blocking) {
      return null;
    }
    final List<DVSchemaChange> contract = <DVSchemaChange>[
      DVDropColumn(change.table, change.column),
      DVRenameColumn(change.table, from: target, to: change.column),
    ];
    DVSchemaChangeClass contractClass = DVSchemaChangeClass.instant;
    for (final DVSchemaChange step in contract) {
      final DVSchemaChangeClass cost =
          await ask(step) ?? DVSchemaChangeClass.blocking;
      if (cost.index > contractClass.index) contractClass = cost;
    }
    return DVExpandContractPlan(
      original: change,
      expand: expand,
      sourceColumn: change.column,
      targetColumn: target,
      contract: List<DVSchemaChange>.unmodifiable(contract),
      expandClass: expandClass,
      contractClass: contractClass,
    );
  }
}

/// An explicit decision to run a blocking change against production.
///
/// Sometimes the forty minutes are worth it -- at three in the morning, with
/// everyone told. What the gate insists on is that it is said, with a reason,
/// and written down.
final class DVSchemaOverride {
  const DVSchemaOverride({required this.reason, required this.at, this.by});

  final String reason;
  final String? by;
  final DateTime at;
}

/// What the deploy gate decided.
final class DVSchemaGateResult {
  const DVSchemaGateResult({
    required this.allowed,
    required this.findings,
    this.overrideRecord,
  });

  final bool allowed;
  final List<DVSchemaFinding> findings;

  /// The log entry for an override that let a blocking change through; the
  /// caller writes it where overrides are kept.
  final Map<String, Object?>? overrideRecord;
}

/// Refuses a blocking change against production without an override
/// (`DV-SCHEMA-002`).
final class DVSchemaDeployGate {
  const DVSchemaDeployGate();

  DVSchemaGateResult check(
    DVSchemaPlan plan, {
    required bool production,
    DVSchemaOverride? override,
  }) {
    final List<DVSchemaPlanStep> blocking = plan.blocking;
    if (!production || blocking.isEmpty) {
      return const DVSchemaGateResult(
        allowed: true,
        findings: <DVSchemaFinding>[],
      );
    }
    final List<String> changes = <String>[
      for (final DVSchemaPlanStep step in blocking) step.change.description,
    ];
    if (override != null && override.reason.trim().isNotEmpty) {
      return DVSchemaGateResult(
        allowed: true,
        findings: const <DVSchemaFinding>[],
        overrideRecord: <String, Object?>{
          'code': 'DV-SCHEMA-002',
          'reason': override.reason.trim(),
          if (override.by != null) 'by': override.by,
          'at': override.at.toIso8601String(),
          'changes': changes,
        },
      );
    }
    return DVSchemaGateResult(
      allowed: false,
      findings: <DVSchemaFinding>[
        for (final DVSchemaPlanStep step in blocking)
          DVSchemaFinding(
            'DV-SCHEMA-002',
            '"${step.change}" blocks readers or writers and is going to '
                'production without an override. Give a reason to override it, '
                'or change it to something that does not block.',
            change: step.change,
          ),
      ],
    );
  }
}

/// A table in a [DVSchemaSnapshot].
final class DVSchemaSnapshotTable {
  const DVSchemaSnapshotTable({required this.columns, required this.rows});

  final List<String> columns;
  final int rows;
}

/// The shape and size of a production database, to rehearse a plan against.
///
/// The classification a developer sees has to be the one production will
/// apply. Their empty local database is the wrong server, the wrong version
/// and the wrong size.
final class DVSchemaSnapshot {
  const DVSchemaSnapshot({
    required this.provider,
    required this.serverVersion,
    required this.tables,
  });

  factory DVSchemaSnapshot.fromJson(Map<String, Object?> json) {
    final Object? provider = json['provider'];
    final Object? version = json['serverVersion'];
    if (provider is! String || version is! String) {
      // Defaulting either would classify against a server nobody has.
      throw const FormatException(
        'A schema snapshot needs its provider and serverVersion.',
      );
    }
    final Object? tables = json['tables'];
    return DVSchemaSnapshot(
      provider: provider,
      serverVersion: version,
      tables: <String, DVSchemaSnapshotTable>{
        if (tables is Map)
          for (final MapEntry<Object?, Object?> entry in tables.entries)
            if (entry.value is Map)
              '${entry.key}': DVSchemaSnapshotTable(
                columns: <String>[
                  for (final Object? c
                      in ((entry.value as Map)['columns'] as List? ?? const []))
                    '$c',
                ],
                rows: ((entry.value as Map)['rows'] as num? ?? 0).toInt(),
              ),
      },
    );
  }

  final String provider;
  final String serverVersion;
  final Map<String, DVSchemaSnapshotTable> tables;

  Map<String, int> get rows => <String, int>{
    for (final MapEntry<String, DVSchemaSnapshotTable> t in tables.entries)
      t.key: t.value.rows,
  };

  /// The rules of the adapter for [provider] at [serverVersion], or null
  /// when there is no such adapter or the version cannot be read.
  DVSchemaClassifier? get classifier {
    final DVDatabaseServerVersion? version = DVDatabaseServerVersion.tryParse(
      serverVersion,
    );
    if (version == null) return null;
    return switch (provider.toLowerCase()) {
      'postgres' || 'postgresql' => DVPostgresSchemaRules(version),
      'mysql' => DVMySqlSchemaRules.forServer(serverVersion),
      'sqlite' || 'turso' || 'libsql' => DVSqliteSchemaRules(version),
      _ => null,
    };
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    'serverVersion': serverVersion,
    'tables': <String, Object?>{
      for (final MapEntry<String, DVSchemaSnapshotTable> t in tables.entries)
        t.key: <String, Object?>{
          'columns': t.value.columns,
          'rows': t.value.rows,
        },
    },
  };
}
