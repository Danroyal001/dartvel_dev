// A getter whose type mentions a type parameter of its class is referenced
// through a fresh `SubstitutedGetterElementImpl` in Dart, so two references
// to it are not `==` and cascade_invocations does not report them.
import 'dart:async';

class G<T> {
  final StreamController<T> _controller = StreamController();
  final List<T> l = [];
  final List<int> m = [];

  void a(Object e) {
    _controller.addError(e);
    _controller.close();
  }

  void b() {
    l.clear();
    l.clear();
  }

  void c() {
    m.clear();
    m.clear();
  }

  void d(List<T> p) {
    p.clear();
    p.clear();
  }

  void e(T x) {
    l.add(x);
    m.clear();
    m.add(1);
  }
}

class H {
  final StreamController<int> _controller = StreamController();

  void a(Object e) {
    _controller.addError(e);
    _controller.close();
  }
}
