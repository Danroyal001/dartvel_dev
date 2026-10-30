// `UP(NonNull(T1), T2)` of `??`: `promoteToNonNull` builds a new
// `TypeParameterTypeImpl`, never `identical` to `T2`, so for
// `T & Object` on both sides `UP` takes the `X1 & B1` rule and gives `T`.
class R<T> {
  T? lower;
  T? upper;
}

void f<T, S extends num?>(R<T> range, T? a, S? s, S? t) {
  final value = range.lower ?? range.upper!;
  final v2 = a ?? range.upper!;
  final v3 = s ?? t!;
  final v4 = range.lower ?? a;
  print([value, v2, v3, v4]);
}
