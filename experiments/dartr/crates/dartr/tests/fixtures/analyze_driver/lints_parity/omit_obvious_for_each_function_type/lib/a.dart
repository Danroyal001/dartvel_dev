// `iterableType.elementTypeOfIterable == staticType` is Dart `==` on types:
// structural for function types, not identity.
void f(List<void Function(int)> ls, List<int> li) {
  for (final void Function(int) l in List<void Function(int)>.of(ls)) {
    l(1);
  }
  for (final void Function(int) l in <void Function(int)>[]) {
    l(1);
  }
  for (final void Function(int) l in <void Function(num)>[]) {
    l(1);
  }
  for (final int i in List<int>.of(li)) {
    print(i);
  }
  for (final (int, String) r in <(int, String)>[]) {
    print(r);
  }
}
