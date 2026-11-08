// Reads of local variables and formal parameters with declared types
// (body_dump --identifiers), and reads it must leave out.
import 'dart:async' as async;
import 'dart:async';

typedef Callback = int Function(String);
typedef Pair<T> = (T, T);
typedef MaybeInt = int?;

/// Mentions [a] in a comment reference, which is not a read.
int topLevel(int a, [List<String>? b, Map<String, int> c = const {}]) {
  a;
  b;
  c;
  return a;
}

void named({required double d, Object? e, dynamic f, int g(String s)?}) {
  d;
  e;
  f;
  g;
  h(String s) => s.length;
  h;
}

class C<T> {
  final int field;
  final T value;

  C(int start, this.value, {int? unused}) : field = start {
    start;
  }

  C.named(this.field, T other) : value = other;

  set setter(Callback callback) {
    callback;
    callback('x');
  }

  int operator +(C<T> other) => other.field;

  S method<S extends num>(S s, T t, List<T> ts, Pair<S> pair) {
    s;
    t;
    ts;
    pair;
    T local = t;
    local;
    S Function<R>(R) generic = <R>(R r) => s;
    generic;
    return s;
  }

  static void statics(async.Future<int> future, FutureOr<String> futureOr) {
    future;
    futureOr;
  }
}

void locals(int parameter, String shadowed, int typeParameter) {
  int counter = 0;
  counter = counter + 1;
  counter++;
  counter;
  late final String later;
  later = 'x';
  later;
  (int, {String name}) record = (1, name: 'n');
  record;
  Pair<double> pair = (1.0, 2.0);
  pair;
  Callback callback = (s) => 1;
  callback;
  callback('a');
  callback('b').isEven;
  callback('c').toString().length;
  Function function = () {};
  function;
  MaybeInt maybe = 1;
  maybe;
  Unknown unknown;
  unknown;
  void Function() closure = () {
    parameter;
    counter;
  };
  closure;
  for (int i = 0; i < 3; i++) {
    i;
  }
  for (String s in ['a']) {
    s;
  }
  [for (final int e in [1]) e];
  var untyped = 1;
  untyped;
  {
    String parameter = 'inner';
    parameter;
  }
  {
    var shadowed = 1;
    shadowed;
  }
  {
    void shadowed() {}
    shadowed;
  }
  void generic<typeParameter>(typeParameter value) {
    typeParameter;
    value;
  }
  try {} on FormatException catch (parameter) {
    parameter;
  }
  if (record case (var parameter, name: _)) {
    parameter;
  }
  switch (pair) {
    case (var shadowed, _):
      shadowed;
  }
  parameter;
}

void promoted(int? n, num q, Object o, int? w, int? z, List<int>? xs,
    Object scrutinee, int? assigned, bool flag, int kept) {
  if (n != null) n;
  if (q is int) q;
  o as int;
  w;
  w = 1;
  w;
  z!;
  xs?.length;
  xs?[0];
  switch (scrutinee) {
    case int():
  }
  assigned ??= 2;
  assigned;
  flag ? [1] : [2];
  (kept);
  kept;
}

void wildcards(int _, int __) {
  __;
}

void beforeDeclaration() {
  int declaredLater = 1;
  {
    declaredLater;
  }
}

void initialized([int? defaulted = 1, int? plain]) {
  defaulted;
  plain;
  int? initializedNullable = 1;
  initializedNullable;
  int? uninitialized;
  uninitialized;
  for (int? element in [1]) {
    element;
  }
}

typedef Contravariant<X> = Function(X);
class Bounded<X extends Contravariant<Y>, Y> {}
class One<T> {}

extension Ext on int {
  int get twice => this * 2;
}

void heldOut(int? viaIdentical, String? viaElement, int? viaOverride) {
  // Raw types instantiate to bounds: a contravariant occurrence becomes
  // Never. A wrong number of type arguments is InvalidType for each.
  void local(Bounded raw, One<int, int> wrong) {
    raw;
    wrong;
  }
  if (!identical(viaIdentical, null)) viaIdentical;
  <String, String>{?viaElement: viaElement};
  Ext(viaOverride)?.twice;
  viaOverride;
  const int annotation = 0;
  @annotation
  int annotated = 1;
  annotated;
}

class Point(int x, int y) {
  int sum = x + y;
  this : assert(x >= 0) {
    y;
  }
}

// A declaring parameter is a parameter in initializers and the field in the
// body (`PrimaryParameterScope` leaves it out).
class Declaring(final int z) {
  int doubled = z * 2;
  this {
    z;
  }
}
