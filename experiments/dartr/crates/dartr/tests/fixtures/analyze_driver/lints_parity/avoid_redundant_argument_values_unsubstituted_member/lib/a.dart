// A member of a generic class keeps its own parameters, and their default
// values, unless the class substitution changes its function type: the
// method's own type parameters do not count (`_TypeSubstitutor`).
import 'dart:async';

abstract class B<T> {
  void g<E>([E? x]);
  void k([int? x]);
  void t([T? x]);
  void u<E>([T? x]);
  void v<E>([E? x, T? y]);
  E w<E>([E? x]);
  void q<E extends T>([int? a]);
  void s({int? a, T? b});
}

extension X<T> on List<T> {
  void eg<E>([E? x]) {}
  void et([T? x]) {}
}

void h(B<int> b, B<int>? n, List<int> l, StreamSubscription<int> sub) {
  b.g(null);
  b.g<int>(null);
  b.k(null);
  b.t(null);
  b.u(null);
  b.v(null);
  b.v(null, null);
  b.w(null);
  b.q(null);
  b.s(a: null);
  b..g(null);
  n?.g(null);
  l.eg(null);
  l.et(null);
  sub.asFuture(null);
}

// An implicit `this` invocation finds an interface member as a member of
// `thisType`; an extension member is found as declared.
class C<T> {
  void m(T a, [int i = 1]) {}
  void k([int i = 1]) {}
  static void s(Object? a, [int i = 1]) {}
  void n(T a) {
    m(a, 1);
    this.m(a, 1);
    k(1);
    s(a, 1);
    void local() {
      m(a, 1);
    }

    local();
    [1].forEach((e) => m(a, 1));
  }
}

class D extends C<int> {
  void p() {
    m(1, 1);
    k(1);
  }
}

mixin M<T> {
  void m(T a, [int i = 1]) {}
  void n(T a) {
    m(a, 1);
  }
}

extension E<T> on List<T> {
  void m(T a, [int i = 1]) {}
  void k([int i = 1]) {}
  void n(T a) {
    m(a, 1);
    k(1);
  }
}

extension type X<T>(List<T> l) {
  void m(T a, [int i = 1]) {}
  void k([int i = 1]) {}
  void n(T a) {
    m(a, 1);
    k(1);
  }
}

enum En<T> {
  a;

  void m(T? a, [int i = 1]) {}
  void n(T? x) {
    m(x, 1);
  }
}

class F {
  void m(int a, [int i = 1]) {}
  void n() {
    m(1, 1);
  }
}
