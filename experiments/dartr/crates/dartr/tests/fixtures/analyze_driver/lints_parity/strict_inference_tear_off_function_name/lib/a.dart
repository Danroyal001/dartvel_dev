// A generic function instantiation reports the inference failure on the
// `SimpleIdentifier` with the function's name
// (`inference_failure_on_function_invocation`), not on the function type.
A id<A>(A a) => a;

abstract class C<F> {
  B foldLeft<A, B>(F fa, B z, B f(B previous, A a));
  F prependElement<A>(F fa, A a);
  F empty();
  F map<A, B>(F fa, B f(A a));

  F reverse(F fa) => foldLeft(fa, empty(), prependElement);
  F m(F fa) => map(fa, id);
}

T apply<T>(T Function(T) f, T t) => f(t);

void g(C<int> c) {
  apply(id, 1);
  final h = id;
  final i = c.prependElement;
  int Function(int, Object?) j = c.prependElement;
  print([h, i, j]);
}
