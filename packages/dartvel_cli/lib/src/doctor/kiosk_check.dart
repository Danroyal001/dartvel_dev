/// `dartvel doctor` on a kiosk policy.
///
/// The specification says doctor validates that the declared policy is
/// enforceable on each configured target. Without this the refusals the policy
/// parser produces -- a literal exit PIN, `auth` in a display-scope reset --
/// were computed and dropped, which is the same as not checking.
///
/// Pure, so it can be tested without running the command: doctor prints
/// [lines] and takes [ok] into its own verdict.
library dartvel_cli.doctor.kiosk_check;

import 'package:dartvel_core/dartvel.dart';

/// The kiosk section of a doctor run.
class DVKioskCheck {
  const DVKioskCheck({required this.ok, required this.lines});

  /// Whether the project may ship as configured.
  final bool ok;

  /// What to print. Empty when the project declares no kiosk.
  final List<String> lines;

  /// Validates [dartvelSection] against [targets].
  static DVKioskCheck run(Object? dartvelSection, List<DVKioskTarget> targets) {
    final DVKioskPolicy policy = DVKioskPolicy.parse(dartvelSection);
    if (!policy.enabled) {
      return const DVKioskCheck(ok: true, lines: <String>[]);
    }

    final List<String> lines = <String>['Kiosk (${policy.scope.name} scope)'];
    var ok = true;

    // The policy's own refusals first: nothing about a target matters if the
    // declaration cannot be honoured anywhere.
    for (final String problem in policy.problems) {
      // The problem text never contains the value it rejected -- doctor output
      // gets pasted into issues.
      lines.add('  [!] $problem');
      ok = false;
    }

    for (final DVKioskTarget target in targets) {
      final DVKioskEnforcement e =
          DVKioskEnforcement.resolve(policy: policy, target: target);

      if (!e.supported) {
        // Nothing about the configuration is wrong; shipping it here is.
        lines.add('  [!] ${target.name}: cannot be a kiosk '
            '(${DVKioskDegradation.unsupportedTarget.code})');
        ok = false;
        continue;
      }

      final String codes = e.codes.isEmpty ? '' : '  ${e.codes.join(' ')}';
      // A weaker target is a deployment choice, not a mistake: a Linux desktop
      // kiosk is supervised and someone may well want that. Said, not failed.
      final String mark = e.codes.isEmpty ? '+' : '-';
      lines.add('  [$mark] ${target.name}: ${e.strength.name}'
          '${e.scopeHonoured ? '' : ', scope degraded'}$codes');
    }

    return DVKioskCheck(ok: ok, lines: lines);
  }
}
