/// Escapes [s] for inclusion in a single-quoted Dart string literal.
///
/// Order matters and is the reason this was wrong: backslashes must be doubled
/// **first**, or the backslash added when escaping a quote or a dollar gets
/// doubled again on a later pass.
///
/// Getting this wrong does not produce a wrong value, it produces a file that
/// does not compile — and every symbol that file was meant to declare vanishes
/// with it. Windows found all three failures at once. A generated path
/// `D:\a\dartvel\...` was emitted unescaped and the compiler stopped at "an
/// escape sequence starting with '\u' must be followed by 4 hexadecimal
/// digits", leaving `User`, `getHelloApi` and everything else undefined. A
/// bare `$` interpolated a variable that did not exist. A `'` closed the
/// literal early. None of it was visible on Linux because none of those
/// characters appear in a posix path.
String esc(String s) => s
    .replaceAll(r'\', r'\\')
    // A literal newline, carriage return or tab inside a single-quoted
    // literal is a syntax error, not merely ugly. These run after the
    // backslash pass so the backslash they introduce is not doubled.
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\t', r'\t')
    .replaceAll(r'$', r'\$')
    .replaceAll("'", r"\'");

int asInt(Object? v, int dflt) {
  if (v is int) return v;
  if (v is String) {
    final n = int.tryParse(v);
    if (n != null) return n;
  }
  return dflt;
}

bool asBool(Object? v, bool dflt) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return dflt;
}

String transitionEnum(String v) {
  switch (v) {
    case 'none':
      return 'DvTransition.none';
    case 'fade':
      return 'DvTransition.fade';
    case 'slideLeft':
      return 'DvTransition.slideLeft';
    case 'slideUp':
      return 'DvTransition.slideUp';
    case 'scale':
      return 'DvTransition.scale';
    case 'sharedAxis':
      return 'DvTransition.sharedAxis';
    default:
      return 'DvTransition.fade';
  }
}

String curveExpr(String v) {
  switch (v) {
    case 'linear':
      return 'Curves.linear';
    case 'easeIn':
      return 'Curves.easeIn';
    case 'easeOut':
      return 'Curves.easeOut';
    case 'easeInOut':
      return 'Curves.easeInOut';
    case 'decelerate':
      return 'Curves.decelerate';
    default:
      return 'Curves.easeInOut';
  }
}
