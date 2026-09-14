/// Applying an approved plan to a host, and verifying the host afterwards.
library;

import 'infra_desired.dart';
import 'infra_plan.dart';

/// A host the provisioner can read and change.
///
/// The SSH adapter implements this in the CLI; tests implement it in memory.
abstract interface class DVInfraHost {
  String get name;

  /// Reads the managed resources, certificates and restore record.
  Future<DVInfraObservation> observe();

  /// Performs one step. [resource] is the desired resource, null for a
  /// removal. [secretValue] is given only to a `deliver` step and must not be
  /// written anywhere but the encrypted credential store.
  ///
  /// Throws when the step did not happen.
  Future<void> apply(
    DVInfraStep step,
    DVInfraResource? resource, {
    String? secretValue,
  });
}

enum DVInfraApplyStatus {
  /// Every step ran and the host now matches the manifest.
  applied,

  /// Nothing ran.
  refused,

  /// A step failed; the ones before it ran, the ones after did not.
  failed,

  /// Every step ran, and the host still does not match.
  unverified,
}

/// What an apply did.
final class DVInfraApplyResult {
  const DVInfraApplyResult({
    required this.status,
    required this.message,
    this.applied = const <DVInfraStep>[],
    this.failed,
    this.error,
    this.pending = const <DVInfraStep>[],
    this.remaining = const <DVInfraStep>[],
  });

  final DVInfraApplyStatus status;
  final String message;
  final List<DVInfraStep> applied;
  final DVInfraStep? failed;

  /// The failed step's error, with secret values struck out.
  final String? error;

  /// Steps after the failure that did not run.
  final List<DVInfraStep> pending;

  /// After verification: what still differs.
  final List<DVInfraStep> remaining;

  bool get ok => status == DVInfraApplyStatus.applied;

  @override
  String toString() => '${status.name}: $message';
}

/// Applies [approved] to [host], if it is still the plan [desired] and the
/// host produce.
///
/// Refuses, running nothing, when the plan has unsupported declarations, when
/// the plan computed now differs from the one approved, or when it removes
/// something and [confirmDestructive] is false. Stops at the first failing
/// step. After the last step it observes the host again, and reports success
/// only when nothing is left to do.
Future<DVInfraApplyResult> dvApplyInfraPlan({
  required DVInfraPlan approved,
  required DVInfraDesiredState desired,
  required DVInfraHost host,
  required DVInfraSecretLookup secret,
  bool confirmDestructive = false,
}) async {
  if (approved.unsupported.isNotEmpty) {
    return DVInfraApplyResult(
      status: DVInfraApplyStatus.refused,
      message: 'The manifest declares what this provisioner cannot do, so '
          'nothing was applied:\n  ${approved.unsupported.join('\n  ')}',
    );
  }

  final DVInfraPlan current = dvInfraPlan(
    desired,
    await host.observe(),
    secret: secret,
  );
  if (current.digest != approved.digest) {
    return DVInfraApplyResult(
      status: DVInfraApplyStatus.refused,
      message: 'The host or the manifest changed after this plan was approved '
          '(approved ${approved.digest.substring(0, 12)}, now '
          '${current.digest.substring(0, 12)}), so nothing was applied. Run '
          'the plan again and review what it would do now.',
    );
  }

  final List<DVInfraStep> destructive = current.destructive;
  if (destructive.isNotEmpty && !confirmDestructive) {
    return DVInfraApplyResult(
      status: DVInfraApplyStatus.refused,
      message: 'The plan removes ${destructive.length} thing(s), and nothing '
          'was applied without confirmation: '
          '${destructive.map((DVInfraStep s) => s.id).join(', ')}',
    );
  }

  final List<String> values = <String>[
    for (final DVInfraResource r in desired.resources)
      if (r.kind == DVInfraResourceKind.credential) ?secret(r.id),
  ];
  String redact(String text) {
    String out = text;
    for (final String v in values) {
      if (v.length >= 4) out = out.replaceAll(v, '[redacted]');
    }
    return out;
  }

  final List<DVInfraStep> applied = <DVInfraStep>[];
  for (int i = 0; i < current.steps.length; i++) {
    final DVInfraStep step = current.steps[i];
    DVInfraResource? resource;
    if (step.action != DVInfraAction.remove) {
      for (final DVInfraResource r in desired.resources) {
        if (r.kind == step.kind && r.id == step.id) resource = r;
      }
    }
    try {
      await host.apply(
        step,
        resource,
        secretValue: step.action == DVInfraAction.deliver ? secret(step.id) : null,
      );
    } on Object catch (e) {
      final String error = redact('$e');
      final List<DVInfraStep> pending = current.steps.sublist(i + 1);
      return DVInfraApplyResult(
        status: DVInfraApplyStatus.failed,
        applied: List<DVInfraStep>.unmodifiable(applied),
        failed: step,
        error: error,
        pending: List<DVInfraStep>.unmodifiable(pending),
        message: 'Provisioning ${host.name} stopped at ${step.action.name} '
            '${step.id}: $error. ${applied.length} step(s) ran before it and '
            '${pending.length} did not. Running the provision again plans '
            'only what is still missing.',
      );
    }
    applied.add(step);
  }

  final DVInfraPlan after = dvInfraPlan(
    desired,
    await host.observe(),
    secret: secret,
  );
  if (!after.isEmpty) {
    return DVInfraApplyResult(
      status: DVInfraApplyStatus.unverified,
      applied: List<DVInfraStep>.unmodifiable(applied),
      remaining: after.steps,
      message: 'Every step ran on ${host.name}, and the host still does not '
          'match the manifest: ${after.steps.join('; ')}',
    );
  }
  return DVInfraApplyResult(
    status: DVInfraApplyStatus.applied,
    applied: List<DVInfraStep>.unmodifiable(applied),
    message: applied.isEmpty
        ? '${host.name} already matches the manifest.'
        : '${host.name}: ${applied.length} step(s) applied and verified.',
  );
}
