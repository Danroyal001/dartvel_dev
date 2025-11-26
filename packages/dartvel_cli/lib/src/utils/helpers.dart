String esc(String s) => s.replaceAll(r'$', r'\\$').replaceAll("'", r"\\'");

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
