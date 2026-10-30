// An argument is its own checked node (`checkedNode ??= node`), so a
// block-bodied function literal passed for a parameter whose type returns
// `FutureOr<void>` has its return type checked.
import 'dart:async';

void f(Future<int> future, Future<void> g) {
  future.whenComplete(() {
    return Future<int>.value(31);
  });
  future.whenComplete(() {
    return 1;
  });
  future.whenComplete(() => Future<int>.value(31));
  g.whenComplete(() {
    return Future<int>.value(31);
  });
  h(() {
    return Future<int>.value(31);
  });
  h(() {
    return 3;
  });
}

void h(FutureOr<void> Function() action) {}

class K {
  K(FutureOr<void> Function() action);
}

K k() => K(() {
  return 4;
});

void l(void Function() action) {}

void m() {
  l(() {
    return;
  });
}
