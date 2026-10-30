// The parameters of a function type written in the return type of a local
// function belong to a `GenericFunctionTypeElement`, not to an executable.
void h() {
  void Function({int x}) k() => ({int x = 0}) {};
  final v = k();
  v(x: 1);
  k()(x: 0);
  var unused = 1;
  print(unused);
}

class C<T> {
  void Function({T? x}) f = ({T? x}) {};

  void m() {
    f(x: null);
    var unused = 1;
    print(unused);
  }
}
