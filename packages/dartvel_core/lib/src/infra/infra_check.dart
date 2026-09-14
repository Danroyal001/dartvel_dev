/// `dartvel infra check`: what has changed underneath a host, as typed
/// `DV-INFRA-*` findings.
library;

import '../diagnostics/diagnostics.dart';
import 'infra_desired.dart';
import 'infra_plan.dart';

/// One finding about one host.
final class DVInfraFinding {
  DVInfraFinding(this.code, this.host, this.message)
    : level = _registered(code).level;

  final String code;

  /// The registry's level, so a finding cannot disagree with it.
  final String level;
  final String host;
  final String message;

  static DVDiagnostic _registered(String code) {
    final DVDiagnostic? d = DVDiagnostics.find(code);
    if (d == null) {
      throw ArgumentError.value(code, 'code', 'not a registered diagnostic');
    }
    return d;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'level': level,
    'host': host,
    'message': message,
  };

  @override
  String toString() => '$code ($level) $host: $message';
}

/// Compares [observation] with [desired].
///
/// * `DV-INFRA-001` for every step a provision would take other than
///   starting a service, and for a package whose version moved since it was
///   provisioned;
/// * `DV-INFRA-003` for a declared service that is not running, including
///   one waiting on a first release -- it is still not running;
/// * `DV-INFRA-002` for a certificate within [renewalWindow] of expiry (or
///   missing) whose renewal is failing. One close to expiry that is still
///   renewing is the proxy doing its job;
/// * `DV-INFRA-004` when a backup is declared and the last verified restore
///   is older than its window, or there has never been one.
List<DVInfraFinding> dvInfraCheck({
  required DVInfraDesiredState desired,
  required DVInfraObservation observation,
  required DVInfraSecretLookup secret,
  required DateTime now,
  Duration renewalWindow = const Duration(days: 30),
}) {
  final String host = observation.host;
  final List<DVInfraFinding> findings = <DVInfraFinding>[];
  final DVInfraPlan plan = dvInfraPlan(desired, observation, secret: secret);

  for (final DVInfraStep step in plan.steps) {
    if (step.kind == DVInfraResourceKind.unit &&
        (step.action == DVInfraAction.start ||
            step.action == DVInfraAction.restart)) {
      continue;
    }
    findings.add(DVInfraFinding(
      'DV-INFRA-001',
      host,
      '${step.id}: ${step.reason} (a provision would ${step.action.name} it)',
    ));
  }

  for (final DVObservedResource o in observation.resources) {
    if (o.kind != DVInfraResourceKind.package) continue;
    if (o.installedVersion != null &&
        o.recordedVersion != null &&
        o.installedVersion != o.recordedVersion) {
      findings.add(DVInfraFinding(
        'DV-INFRA-001',
        host,
        'package ${o.id} was ${o.recordedVersion} when provisioned and is now '
        '${o.installedVersion}',
      ));
    }
  }

  for (final DVInfraResource r in desired.resources) {
    if (r.kind != DVInfraResourceKind.unit || !r.active) continue;
    final DVObservedResource? o = observation.find(r.kind, r.id);
    if (o?.active ?? false) continue;
    final bool waiting = r.requiresRelease && !observation.releasePresent;
    findings.add(DVInfraFinding(
      'DV-INFRA-003',
      host,
      '${r.id} is declared and not running'
      '${waiting ? '; there is no release on the host for it to run' : ''}',
    ));
  }

  final List<String> domains =
      desired.manifest.tls?.domains ?? const <String>[];
  for (final String domain in domains) {
    final DVObservedCertificate? cert = observation.certificates[domain];
    if (cert == null || !cert.renewalFailing) continue;
    final DateTime? notAfter = cert.notAfter;
    if (notAfter == null) {
      findings.add(DVInfraFinding(
        'DV-INFRA-002',
        host,
        '$domain has no certificate and obtaining one is failing',
      ));
    } else if (notAfter.difference(now) <= renewalWindow) {
      final int days = notAfter.difference(now).inDays;
      findings.add(DVInfraFinding(
        'DV-INFRA-002',
        host,
        days < 0
            ? '$domain expired ${-days} day(s) ago and renewal is failing'
            : '$domain expires in $days day(s) and renewal is failing',
      ));
    }
  }

  final bool backupDeclared = desired.resources.any(
    (DVInfraResource r) => r.id == '${desired.appName}-backup.timer',
  );
  final Duration? window =
      desired.manifest.database?.backup?.verifiedRestoreWithin;
  if (backupDeclared && window != null) {
    final DateTime? last = observation.lastVerifiedRestore;
    if (last == null) {
      findings.add(DVInfraFinding(
        'DV-INFRA-004',
        host,
        'backups are scheduled and a restore has never been verified',
      ));
    } else if (now.difference(last) > window) {
      findings.add(DVInfraFinding(
        'DV-INFRA-004',
        host,
        'the last verified restore was ${now.difference(last).inDays} days '
        'ago, outside the ${window.inDays}-day window',
      ));
    }
  }

  return findings;
}
