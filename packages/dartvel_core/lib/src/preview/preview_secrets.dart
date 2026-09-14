/// Which secret values a preview is given.
///
/// A preview is its own environment, named `preview`. Its values come from a
/// source of their own and never from production's: a preview holding a live
/// payment key takes real money from whoever clicks the button.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../diagnostics/diagnostics.dart';

/// The environment name a preview runs as.
const String dvPreviewEnvironment = 'preview';

/// One diagnostic raised while planning, creating or tearing down a preview.
final class DVPreviewFinding {
  DVPreviewFinding(this.code, this.message) : level = _registered(code).level;

  /// A `DV-PREVIEW-*` code from the diagnostic registry.
  final String code;

  /// The registry's level for [code], so a finding cannot disagree with it.
  final String level;

  final String message;

  static DVDiagnostic _registered(String code) {
    final DVDiagnostic? diagnostic = DVDiagnostics.find(code);
    if (diagnostic == null) {
      throw ArgumentError.value(code, 'code', 'not a registered diagnostic');
    }
    return diagnostic;
  }

  bool get isError => level == 'error';

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'level': level,
        'message': message,
      };

  @override
  String toString() => '$code ($level): $message';
}

/// The secrets a preview is deployed with, and why it may not be.
final class DVPreviewSecretPlan {
  const DVPreviewSecretPlan._(this.values, this.findings);

  /// Name to preview value. Handed to the deployment and nowhere else.
  final Map<String, String> values;

  final List<DVPreviewFinding> findings;

  bool get deployable => !findings.any((DVPreviewFinding f) => f.isError);
}

/// Plans a preview's secrets from the declaration.
///
/// [required] is each declared secret's `required:` list. A secret required
/// in `production` or in `preview` must have a preview value, or the plan
/// carries `DV-PREVIEW-002`: a production requirement means the application
/// cannot run without it, and the preview is that application.
///
/// [previewValue] is the preview's own source. [productionValue], when
/// given, is consulted only to compare digests: a preview value identical to
/// production's is refused the same way as a missing one, because it is the
/// production credential under another variable name, and that is how a
/// `PREVIEW_STRIPE_KEY=$STRIPE_KEY` line in a workflow takes real payments.
DVPreviewSecretPlan dvPlanPreviewSecrets({
  required Map<String, Set<String>> required,
  required String? Function(String name) previewValue,
  String? Function(String name)? productionValue,
}) {
  final Map<String, String> values = <String, String>{};
  final List<DVPreviewFinding> findings = <DVPreviewFinding>[];
  final List<String> names = required.keys.toList()..sort();
  for (final String name in names) {
    final Set<String> environments = required[name]!;
    final bool needed = environments.contains('production') ||
        environments.contains(dvPreviewEnvironment);

    final String? value = _nonEmpty(previewValue(name));
    final String? production =
        productionValue == null ? null : _nonEmpty(productionValue(name));
    final bool isProductions =
        value != null && production != null && _same(value, production);

    if (value != null && !isProductions) {
      values[name] = value;
      continue;
    }
    if (isProductions) {
      findings.add(DVPreviewFinding(
        'DV-PREVIEW-002',
        '"$name" has a preview value identical to production\'s. Production '
        'values are never resolved for a preview; give the preview its own '
        '(a test-mode key, a sandbox account) or the preview is not deployed.',
      ));
      continue;
    }
    if (needed) {
      findings.add(DVPreviewFinding(
        'DV-PREVIEW-002',
        '"$name" is required in ${(environments.toList()..sort()).join(', ')} '
        'and has no preview value, so the preview was not deployed. Set a '
        'preview value for it; production\'s is never used.',
      ));
    }
  }
  return DVPreviewSecretPlan._(
    Map<String, String>.unmodifiable(values),
    List<DVPreviewFinding>.unmodifiable(findings),
  );
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

/// Compared by digest so neither value is held longer than the comparison.
bool _same(String a, String b) =>
    sha256.convert(utf8.encode(a)) == sha256.convert(utf8.encode(b));
