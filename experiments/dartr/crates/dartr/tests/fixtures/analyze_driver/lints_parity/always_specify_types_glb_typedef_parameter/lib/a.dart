// `DOWN(T, T) = T` is `identical(T1, T2)` in Dart: the parameter types of
// two declarations written with the same typedef are distinct objects, so
// their lower bound is a new function or record type without the alias.
import 'b.dart';

void k() {
  final r1 = [F.test, D.test];
  for (final y in r1) {
    print(y);
  }
  final r2 = [(name: 'a', run: F.test), (name: 'b', run: D.test)];
  for (final x in r2) {
    print(x);
  }
  int v = r1;
  print(v);
}
