// @dart=3.5
// A function literal's own type parameters are not in the scope that
// `resolveNameInScope` finds for its parameter list: a function expression
// has no name scope, so the lookup starts at the enclosing block.
void f() {
  final foo = <_>(i, _) {};
  final bar = <T>(T) {};
  final baz = <T>(x) {
    final inner = (T) {};
    inner(0);
  };
  foo<int>(0, 1);
  bar<int>(0);
  baz<int>(0);
}

void g<T>(T) {}

class C<T> {
  void m(T) {}
}
