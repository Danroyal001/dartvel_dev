/// Rollback: to the previous release, or to a named one, by its provenance
/// record.
///
/// The release is the unit. Rolling back one function and leaving its
/// neighbours is a state nobody described, because the functions released
/// together share generated serialization, one protocol version and one schema
/// expectation (`DV-RELEASE-004`).
///
/// Data is not rolled back. A rollback onto a release that reads a shape a
/// contract step has already dropped is refused rather than attempted, and a
/// rollback that would leave a backfill stale says which migration has to be
/// verified again. A rollback across a protocol bump is held against the
/// clients actually calling, as a deploy is.
library;

import 'dart:async';

import '../protocol/compatibility_check.dart';
import '../protocol/contract.dart';
import 'release_diagnostics.dart';
import 'release_gates.dart';
import 'release_plan.dart';
import 'release_record.dart';

/// Where a rollback goes.
final class DVRollbackTarget {
  /// The release serving before the current one (`dartvel deploy rollback`).
  const DVRollbackTarget.previous() : release = null, at = null;

  /// A release by name.
  const DVRollbackTarget.release(String this.release) : at = null;

  /// The release that was serving at a moment
  /// (`dartvel deploy rollback --to 2026-09-11T14:02Z`).
  const DVRollbackTarget.at(DateTime this.at) : release = null;

  final String? release;
  final DateTime? at;

  @override
  String toString() => release != null
      ? 'release $release'
      : at != null
      ? 'the release serving at ${at!.toUtc().toIso8601String()}'
      : 'the previous release';
}

/// Reads the phase an expand/contract migration has reached on the database,
/// or null when it cannot be told.
typedef DVMigrationPhaseSource =
    FutureOr<DVReleaseMigrationPhase?> Function(String migration);

/// What a rollback would do, and whether it may.
final class DVRollbackPlan {
  const DVRollbackPlan._({
    required this.from,
    required this.to,
    required this.refusals,
    required this.findings,
    required this.reverify,
    required this.overrides,
  });

  /// The release serving when the plan was made.
  final DVDeployedRelease? from;

  /// The release it would restore, when one was found.
  final DVDeployedRelease? to;

  /// Why it may not run. Empty when it may.
  final List<String> refusals;
  final List<DVReleaseFinding> findings;

  /// Migrations whose backfill the restored release will leave stale, to be
  /// verified again before their read switch.
  final List<String> reverify;

  /// Overrides that let a refusal through.
  final List<DVGateOverrideRecord> overrides;

  bool get allowed => refusals.isEmpty && from != null && to != null;

  String describe() {
    final StringBuffer out = StringBuffer()
      ..writeln('rollback  ${from?.id ?? 'nothing deployed'} -> ${to?.id ?? '?'}');
    final DVReleaseRecord? record = to?.provenance;
    if (record != null) {
      out.writeln(
        'restores  commit ${record.commit}, ${record.artifact}, protocol '
        '${record.protocolVersion}, released by ${record.releasedBy}',
      );
    }
    for (final String migration in reverify) {
      out.writeln('reverify  $migration: the restored release does not dual-write');
    }
    for (final DVGateOverrideRecord o in overrides) {
      out.writeln('override  ${o.gate} by ${o.by}: ${o.reason}');
    }
    for (final String refusal in refusals) {
      out.writeln('refused   $refusal');
    }
    for (final DVReleaseFinding finding in findings) {
      out.writeln(finding);
    }
    return out.toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'from': from?.id,
    'to': to?.id,
    'allowed': allowed,
    'refusals': refusals,
    'findings': <Object?>[for (final DVReleaseFinding f in findings) f.toJson()],
    'reverify': reverify,
    'overrides': <Object?>[for (final DVGateOverrideRecord o in overrides) o.toJson()],
  };
}

/// Plans rollbacks.
abstract final class DVRollbackPlanner {
  static Future<DVRollbackPlan> plan({
    required DVReleaseHistory history,
    DVRollbackTarget target = const DVRollbackTarget.previous(),
    String? function,
    required DVMigrationPhaseSource schema,
    DVProtocolLock? lock,
    DVProtocolWindow window = const DVProtocolWindow(),
    FutureOr<Iterable<DVProtocolSessionSample>> Function()? samples,
    DVGateOverride? protocolOverride,
    required DateTime now,
    DVReleaseDiagnosticSink? onDiagnostic,
  }) async {
    final DVReleaseDiagnosticSink diagnose =
        onDiagnostic ?? dvLogReleaseDiagnostic;
    final List<String> refusals = <String>[];
    final List<DVReleaseFinding> findings = <DVReleaseFinding>[];
    final List<String> reverify = <String>[];
    final List<DVGateOverrideRecord> overrides = <DVGateOverrideRecord>[];
    final DVDeployedRelease? from = history.current;
    DVDeployedRelease? to;

    DVRollbackPlan result() => DVRollbackPlan._(
      from: from,
      to: to,
      refusals: List<String>.unmodifiable(refusals),
      findings: List<DVReleaseFinding>.unmodifiable(findings),
      reverify: List<String>.unmodifiable(reverify),
      overrides: List<DVGateOverrideRecord>.unmodifiable(overrides),
    );

    void finding(String code, String message) {
      findings.add(DVReleaseFinding(code, message));
      diagnose(code, message);
    }

    if (from == null) {
      refusals.add('nothing has been deployed, so there is nothing to roll back');
      return result();
    }

    if (function != null) {
      final Set<String> released = from.provenance?.functions ?? const <String>{};
      final String message =
          'rolling back function $function alone is refused: it was released '
          'with ${from.id}'
          '${released.isEmpty ? '' : ' (${(released.toList()..sort()).join(', ')})'}'
          ', which shares one serialization, protocol and schema expectation; '
          'roll back ${from.id} instead';
      finding('DV-RELEASE-004', message);
      refusals.add(message);
      return result();
    }

    to = switch (target) {
      DVRollbackTarget(release: final String id) => history.find(id),
      DVRollbackTarget(at: final DateTime moment) => history.servingAt(moment),
      _ => history.previous(),
    };
    if (to == null) {
      refusals.add('there is no release to roll back to as $target');
      return result();
    }
    if (identical(to, from) || to.id == from.id) {
      refusals.add('${to.id} is the release already serving');
      return result();
    }
    if (to.rolledBackFrom) {
      refusals.add(
        '${to.id} was itself rolled back; restoring it is rolling forward onto '
        'the release that was taken away',
      );
      return result();
    }
    final DVReleaseRecord? record = to.provenance;
    if (record == null) {
      final String message =
          '${to.id} was deployed with no provenance record, so a rollback '
          'cannot name what it would restore';
      finding('DV-RELEASE-006', message);
      refusals.add(message);
      return result();
    }

    // Schema: every migration either release names, against the database.
    final Set<String> migrations = <String>{
      ...record.schema.keys,
      ...?from.provenance?.schema.keys,
    };
    for (final String migration in (migrations.toList()..sort())) {
      final DVReleaseMigrationPhase? phase;
      try {
        phase = await schema(migration);
      } catch (error) {
        refusals.add('the phase of $migration could not be read: $error');
        continue;
      }
      if (phase == null) {
        refusals.add(
          'the phase of $migration could not be read, and an unread schema is '
          'not a safe one to roll back onto',
        );
        continue;
      }
      final DVReleaseMigrationPhase? expects = record.schema[migration];
      if (phase == DVReleaseMigrationPhase.contracted &&
          expects != DVReleaseMigrationPhase.contracted) {
        refusals.add(
          '$migration has been contracted and ${to.id} was built for '
          '${expects?.name ?? 'the shape before it'}; it would read or write '
          'a shape the contract stopped keeping current, and data is not '
          'rolled back',
        );
        continue;
      }
      if (expects != null && expects.index > phase.index) {
        refusals.add(
          '${to.id} was built for $migration at ${expects.name} and the '
          'database is at ${phase.name}',
        );
        continue;
      }
      if (phase.index >= DVReleaseMigrationPhase.backfilled.index &&
          (expects == null ||
              expects.index < DVReleaseMigrationPhase.dualWriting.index)) {
        reverify.add(migration);
      }
    }

    // Protocol: a rollback across a version is a deploy of the older one.
    final int fromProtocol =
        from.provenance?.protocolVersion ?? record.protocolVersion;
    if (from.provenance == null || record.protocolVersion != fromProtocol) {
      final String crossing = from.provenance == null
          ? '${from.id} has no record of its protocol'
          : 'the rollback crosses protocol $fromProtocol to '
                '${record.protocolVersion}';
      if (lock == null || samples == null) {
        refusals.add(
          '$crossing, and there is no ${lock == null ? 'protocol lock' : 'session histogram'} '
          'to check the clients against',
        );
      } else if (lock.release(record.protocolVersion) == null) {
        refusals.add(
          '$crossing, and the protocol lock has no version '
          '${record.protocolVersion}',
        );
      } else {
        final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
          candidate: DVProtocolLock(<DVProtocolRelease>[
            for (final DVProtocolRelease r in lock.releases)
              if (r.protocol <= record.protocolVersion) r,
          ]),
          window: window,
          samples: await samples(),
          now: now,
          overrideReason: protocolOverride?.reason,
          onDiagnostic: onDiagnostic,
        );
        if (verdict.refusal != null) {
          if (verdict.overridden && protocolOverride != null) {
            overrides.add(
              DVGateOverrideRecord(
                gate: protocolOverride.gate,
                code: verdict.stranded.isEmpty ? null : 'DV-PROTO-005',
                reason: protocolOverride.reason,
                by: protocolOverride.by,
                at: protocolOverride.at,
                overrode: verdict.refusal!,
                evidence: verdict.toJson(),
              ),
            );
          } else {
            refusals.add('rolling back to ${to.id}: ${verdict.refusal}');
          }
        }
      }
    }
    return result();
  }
}

/// Carries out a rollback plan.
abstract final class DVReleaseRollback {
  /// Routes all traffic to the plan's target, confirms the platform reports
  /// it, and records the rollback in [history].
  ///
  /// Returns false, and records nothing, when the platform does not report
  /// the target at all traffic. Throws when the plan is refused or was made
  /// against a history that has since moved.
  static Future<bool> execute(
    DVRollbackPlan plan, {
    required DVReleaseAdapter adapter,
    required DVReleaseHistory history,
    required DateTime now,
  }) async {
    if (!plan.allowed) {
      throw StateError(
        'the rollback is refused: ${plan.refusals.join('; ')}',
      );
    }
    if (!identical(history.current, plan.from)) {
      throw StateError(
        'the plan was made while ${plan.from!.id} was serving and '
        '${history.current?.id} is serving now; plan again',
      );
    }
    final DVDeployedRelease to = plan.to!;
    await adapter.route(candidate: to.id, previous: plan.from!.id, percent: 100);
    if (await adapter.weightOf(to.id) != 100) return false;
    history.rolledBack(to: to.id, at: now);
    return true;
  }
}
