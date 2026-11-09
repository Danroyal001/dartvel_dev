/// The function configuration a `@DVBackendFunction` declares, read from
/// source: `authentication:`.
///
/// Read literally, like `policy:` and `mfa:`, so the forms are the ones the
/// specification writes. A value the build cannot read stops it naming the
/// file: skipped, the function would be generated without the guard its
/// declaration asked for, and the build would be green.
library;

import 'annotation_args.dart';

/// The value of [name] in [args], or null when it is not given.
String? _argument(String args, String name) {
  String? value;
  for (final String argument in dvSplitArgs(args)) {
    final RegExpMatch? named = RegExp(
      '^\\s*$name\\s*:\\s*(.*?)\\s*\$',
      dotAll: true,
    ).firstMatch(argument);
    if (named != null) value = named.group(1);
  }
  return value;
}

/// Whether [source]'s `@DVBackendFunction` declares
/// `authentication: DVAuthentication.required`.
///
/// `DVAuthentication.optional`, `null` and no declaration are false. Anything
/// else -- a constant declared elsewhere, a computed value -- throws naming
/// [rel].
bool dvAuthenticationRequiredFromSource(String source, {required String rel}) {
  final String? args = dvAnnotationArgs(source, 'DVBackendFunction');
  if (args == null) return false;
  final String? value = _argument(args, 'authentication');
  if (value == null) return false;
  final String bare = value
      .replaceFirst(RegExp(r'^const\s+'), '')
      .replaceFirst(RegExp(r'^core\.'), '')
      .trim();
  if (bare == 'null' || bare == 'DVAuthentication.optional') return false;
  if (bare == 'DVAuthentication.required') return true;
  throw StateError(
    '$rel declares @DVBackendFunction(authentication: $value), which is not '
    'a requirement Dartvel can read, so the function cannot be guarded. '
    'Write DVAuthentication.required or DVAuthentication.optional.',
  );
}
