// A field name shortcut (`:final _x`, also through `?` and `!`) takes its
// name from the getter; a positional record field does not.
class C {
  final int _a = 1;
  final int? _b = 2;
}

int f(Object o, (int, int) r) {
  if (o case C(:final _a, :final _b?)) {
    return _a + _b;
  }
  if (o case C(:var _b!)) {
    return _b;
  }
  if (o case C(_a: final _c)) {
    return _c;
  }
  final (_d, _e) = r;
  if (r case (final _f, final _g)) {
    return _f + _g;
  }
  return _d + _e;
}
