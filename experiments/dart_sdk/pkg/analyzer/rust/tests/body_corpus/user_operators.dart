// Fixture for `--user-operators`: invocations of `==`, `!=` and user-definable
// binary, unary and index operators, resolved through the interface of the
// receiver's static type, and the integer literals that are their operands.
// Some lines are compile-time errors on purpose (unresolved operators,
// nullable receivers, operators an extension supplies).
import 'dart:async';

class Vector {
  final double x;
  Vector(this.x);
  Vector operator +(Vector other) => Vector(x + other.x);
  Vector operator -() => this;
  Vector operator *(double factor) => this;
  double operator [](int index) => x;
  bool operator <(Vector other) => true;
  int operator ~() => 0;
  Vector operator -(Vector other) => super + other;
}

class Implicit {
  operator +(other) => 1;
  bool operator ==(other) => true;
  operator -(int x) => 2;
  operator [](int i) => 3;
  Implicit operator *(int x) => this;
}

class ImplicitEquality {
  operator ==(Object other) => true;
  ImplicitEquality operator *(int x) => this;
}

class Sub extends Vector {
  Sub(super.x);
}

mixin Halver on Vector {
  Vector operator /(int divisor) => this;
}

class Mixed extends Vector with Halver {
  Mixed(super.x);
}

class Box<T> {
  T operator [](int i) => throw 0;
  Box<T> operator +(Box<T> other) => this;
  T operator -() => throw 0;
}

class StringBox extends Box<String> {}

class Base {
  int operator +(int x) => x;
}

abstract class Other {
  int operator +(int x);
}

class Both extends Base implements Other {}

class Wide {
  num operator *(num x) => x;
}

abstract class Narrow {
  int operator *(num x);
}

abstract class Combined implements Wide, Narrow {}

extension on String {
  String operator -(String other) => this;
  String operator ~() => this;
}

extension type Meters(int value) {
  Meters operator +(Meters other) => this;
  Meters operator -() => this;
  Bare operator ~() => Bare(value);
}

extension type Wrapped(int value) implements int {}

extension type Bare(int value) {}

enum Level {
  low;

  Level operator +(int steps) => this;
}

void numbers(int i, double d, num n, int? maybe, dynamic dyn, Object o) {
  i + 1;
  i + i;
  i - d;
  d * 2;
  n + 1;
  n + d;
  i / 2;
  i ~/ 2;
  i % 3;
  i << 1;
  i >> 1;
  i >>> 1;
  i & 1;
  i | 1;
  i ^ 1;
  i < 2;
  i <= 2;
  i > 2;
  i >= 2;
  -i;
  ~i;
  -d;
  -n;
  1 + 2;
  1 + 2.5;
  1.5 + 2;
  -1;
  -(1);
  - -1;
  ~1;
  (1) + (2);
  ((i)) + 1;
  1 + 2 + 3;
  i + (i + 1);
  i + (n + 1);
  i * -1;
  n * -1;
  1 == 2;
  1 != 2;
  'a' == 'b';
  null == 1;
  null != 1;
  1 == null;
  maybe + 1;
  -maybe;
  dyn + 1;
  -dyn;
  ~dyn;
  dyn[0];
  o + 1;
  -o;
  o[0];
  'a' + 'b';
  'a' * 3;
  'abc'[1];
  'abc'[1] + 'd';
  'a' - 'b';
  ~'a';
  true & false;
  true | false;
  true ^ true;
  !true == false;
  (1 is int) == true;
  (throw 0) + 1;
  -(throw 0);
  (throw 0)[1];
  (throw 0) == 1;
  (throw 0) != 1;
  1 === 2;
  '${1 + 2}';
  '${n + 1}';
  #a == #b;
  1 < 2 == true;
  (1 + 2) * (3 - 4);
  ((1 + 2)) * 3;
  1.5 + 2.5;
  -1.5;
  i + 1.5;
  d + i;
  d + n;
}

double contexts(int i, num n, double d) {
  double a = n + 1;
  double b = i + 1;
  num c = n + 1;
  int e = i + 1;
  double f = -1;
  double? g = n * 2;
  Object h = n + 1;
  dynamic k = n % 3;
  FutureOr<double> l = n - 1;
  var m = n + 1;
  final o = i + 1;
  print(n + 1);
  print(i + 1);
  print(i < 1);
  print(d + 1);
  double p = n + (n + 1);
  double q = n + -1;
  double r = (n + 1) * 2;
  double s = n + (1);
  double t = d + 1;
  double u = 1 + 2;
  int v = n + 1;
  return n * 2;
}

Future<double> asyncContext(num n) async => n + 1;

Future<int> asyncInt(num n) async {
  return n + 1;
}

FutureOr<double> futureOrContext(num n) => n - 1;

List<double> elements(num n) => <double>[n + 1, n * 2, if (true) n - 1];

Map<double, num> entries(num n) => <double, num>{n + 1: n + 2};

double defaults(num n, [double x = 1 + 2]) => x;

double get getter => 1 + 1;

const topLevel = 1 + 2;

final double typedTopLevel = 2 * 3;

class Fields {
  static const double scale = 1 + 1;
  final int count = 2 + 3;
}

void classes(
  Vector v,
  Vector w,
  Sub s,
  Mixed m,
  Box<String> box,
  StringBox stringBox,
  Implicit imp,
  Meters meters,
  Wrapped wrapped,
  Bare bare,
  Level level,
  Both both,
  Combined combined,
) {
  v + w;
  -v;
  v * 2;
  v * 2.5;
  v[0];
  v[0] + 1;
  v < w;
  ~v;
  v - w;
  s + v;
  s[1];
  m / 2;
  m + v;
  box[0];
  box + box;
  -box;
  stringBox[0];
  stringBox + box;
  imp + 1;
  imp - 1;
  imp[0];
  meters + meters;
  -meters;
  wrapped + 1;
  bare + 1;
  level + 1;
  both + 1;
  combined * 2;
  1 + v;
}

/// `==` and `!=` promote their operands, so the receivers here are
/// expressions rather than reads.
void equalities(Vector v, Vector w, Implicit imp, ImplicitEquality equality, Meters meters, Bare bare, int i) {
  (v + w) == (v + w);
  (v + w) != (v + w);
  (imp * 1) == 1;
  (imp * 1) != 1;
  (equality * 1) == 1;
  (equality * 1) != 1;
  (meters + meters) != 1;
  (-meters) != 1;
  (i + 1) != 1;
  (i + 1) == (i + 2);
  [1][0] != 1;
}

void generics<T extends num, U, V extends int?, W extends dynamic, X extends Never, Y extends Vector>(
  T t,
  U u,
  V v,
  W w,
  X x,
  Y y,
) {
  t + 1;
  t * 2;
  t + 1.5;
  -t;
  ~t;
  u + 1;
  -u;
  v + 1;
  w + 1;
  -w;
  w[0];
  x + 1;
  -x;
  x[0];
  y + y;
  y * 2;
  y[0];
  -y;
}

void collections(List<int> ints, Map<String, double> map, List<double> doubles, List<List<int>> nested) {
  ints[0];
  ints[0] + 1;
  map['a'];
  doubles[1] * 2;
  ints + ints;
  nested[0][1];
  nested[0][1] + 1;
  ints[1 + 1];
  ints[-1];
  doubles[0] + doubles[1];
}

void records((int, int) record, int Function() function, void nothing) {
  function + 1;
  -function;
  function[0];
  nothing[0];
}

class Users {
  int value = 0;

  void method(int i) {
    this + 1;
    i + value;
  }

  int operator +(int other) => other;
}

void cascades(List<int> ints, int i) {
  ints..[0];
  ints[0]..sign;
  i += 1;
  i++;
}

void closures(num n) {
  double Function() f = () => n + 1;
  var g = (int i) => i * 2;
  double h() => n + 1;
}

void nullAware(List<int> ints) {
  ints?[0];
  ints?[0 + 1];
}

void bareEquality(Meters meters) {
  (~meters) != 1;
  (~meters) == 1;
}
