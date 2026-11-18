// Fixture for `--members`: method invocations and property reads on a typed
// receiver, resolved through the interface of the receiver's static type, and
// the integer literals that are arguments of those invocations. Some lines
// are compile-time errors on purpose (unresolved members, nullable receivers,
// members an extension supplies).
import 'dart:async';

class Point {
  final double x;
  final double y;
  int count = 0;
  Point(this.x, this.y);
  double get length => x + y;
  Point scale(double factor) => this;
  Point move({required double dx, double dy = 0}) => this;
  String describe([int precision = 2, num width = 0]) => '';
  bool same(Point other) => true;
  void reset() {}
  static Point origin() => Point(0, 0);
  int _secret = 0;
  int _hidden() => 0;
  T pick<T>(T value) => value;
  get implicitGetter => 1;
  var inferredField = 1;
  final Function callback = () {};
  int Function(int) adder = (int x) => x;
  untypedParameter(x) => x;
  int implicitReturnOverride(int x) => x;
}

class Point3 extends Point {
  final double z;
  Point3(super.x, super.y, this.z);
  @override
  Point3 scale(double factor) => this;
}

class Box<T> {
  final T value;
  Box(this.value);
  T get first => value;
  T replace(T next) => next;
  List<T> toList() => [value];
  Box<List<T>> nest() => Box([value]);
  Map<String, T> keyed(String key) => {key: value};
}

class IntBox extends Box<int> {
  IntBox(super.value);
}

mixin Named {
  String get name => '';
  String greet(String other) => '';
}

class Person with Named {
  int age = 0;
}

abstract class Animal {
  num get weight;
  Object feed(int grams);
}

abstract class Pet {
  int get weight;
  num feed(num grams);
}

abstract class Dog implements Animal, Pet {}

enum Color {
  red,
  green;

  int get code => 0;
  Color next() => this;
}

extension type Meters(double value) {
  Meters plus(Meters other) => this;
  double get raw => value;
}

extension type Celsius(double degrees) implements double {}

extension on Point {
  int get extensionGetter => 0;
  int extensionMethod() => 0;
}

class Overrider extends Point {
  Overrider() : super(0, 0);
  @override
  implicitReturnOverride(x) => x;
}

void functions(
  Point p,
  Point3 p3,
  Box<String> box,
  IntBox ints,
  Person person,
  Dog dog,
  Color color,
  Meters meters,
  Celsius celsius,
  String s,
  int i,
  double d,
  num n,
  List<int> list,
  Map<String, int> map,
  Object o,
  Box<double> doubles,
) {
  p.x;
  p.length;
  p.count;
  p.scale(2);
  p.scale(2.5);
  p.move(dx: 1, dy: 2);
  p.move(dx: (3));
  p.describe();
  p.describe(4);
  p.describe(5, 6);
  p.describe(7, 8, 9);
  p.same(p);
  p.reset();
  p.scale;
  p.describe;
  p.scale(1).length;
  p.scale(1).scale(2).x;
  p.move(dx: 1).describe(3).length;
  p3.z;
  p3.scale(1);
  p3.scale(1).z;
  p3.length;
  box.value;
  box.first;
  box.replace('a');
  box.toList();
  box.nest();
  box.nest().first.first;
  box.keyed('k');
  ints.first;
  ints.replace(10);
  ints.toList().first;
  doubles.replace(11);
  person.name;
  person.greet('x');
  person.age;
  dog.weight;
  dog.feed(12);
  color.code;
  color.next();
  color.index;
  color.next().code;
  meters.raw;
  meters.plus(meters);
  meters.value;
  celsius.isNaN;
  celsius.degrees;
  s.length;
  s.isEmpty;
  s.substring(1);
  s.substring(1, 2);
  s.toUpperCase();
  s.codeUnitAt(0);
  s.padLeft(3, ' ');
  s.split(',');
  i.isEven;
  i.abs();
  i.toDouble();
  i.toString();
  i.bitLength;
  i.compareTo(13);
  i.gcd(14);
  i.remainder(15);
  i.clamp(16, 17);
  d.floor();
  d.isNaN;
  d.toStringAsFixed(2);
  d.compareTo(18);
  n.abs();
  n.round();
  n.toInt();
  list.length;
  list.first;
  list.isEmpty;
  list.contains(19);
  list.indexOf(20);
  list.sublist(1, 2);
  list.reversed;
  list.add(21);
  list.elementAt(22);
  list.join(', ');
  map.length;
  map.keys;
  map.values;
  map.containsKey('a');
  map.isEmpty;
  o.hashCode;
  o.runtimeType;
  o.toString();
  p.hashCode;
  p.toString();
  'abc'.length;
  'abc'.substring(1);
  'a$s'.length;
  'a' 'b'.isEmpty;
  true.toString();
  1.5.floor();
  1.isEven;
  (2).abs();
  (p).x;
  (p.scale(1)).length;
  (s + s).length;
  (i + i).isEven;
  (-i).abs();
  (!true).hashCode;
  (i is int).toString();
  #sym.hashCode;
  s.length.isEven;
  s.substring(1).length.toDouble().floor();
  list.first.isEven;
  list.sublist(0).first;
  print(s.length);
  var local = p.scale(3);
  double typed = p.length;
  String text = '${p.x} ${s.length}';
  [p.x, s.length];
  bool flag = s.isEmpty && list.isEmpty;
  i.compareTo(i.abs());
}

void excluded(
  Point? maybe,
  Point p,
  dynamic dyn,
  Never never,
  Overrider overrider,
  ({int a, String b}) record,
  int Function(int) function,
  Object? object,
) {
  maybe.x;
  maybe?.x;
  p.extensionGetter;
  p.extensionMethod();
  p._secret;
  p._hidden();
  p.pick(1);
  p.pick<int>(2);
  p.implicitGetter;
  p.inferredField;
  p.callback();
  p.adder(3);
  p.adder;
  p.untypedParameter(4);
  overrider.implicitReturnOverride(5);
  overrider.x;
  Point.origin();
  dyn.x;
  dyn.foo(6);
  never.x;
  record.a;
  record.$1;
  function.call(7);
  object.hashCode;
  unresolved.x;
  p.missing;
  p.missing(8);
  p..scale(9)..x;
  p.scale(1)?.x;
}

class Receivers<T extends Point, U extends T, V> extends Point {
  Receivers() : super(0, 0);

  void method(T t, U u, V v, Box<T> box) {
    t.x;
    t.scale(1);
    u.length;
    v.hashCode;
    box.first.x;
    this.x;
    x;
    scale(2);
    super.scale(3);
  }
}

double returned(Point p) => p.length;

Future<double> asynchronous(Point p) async => p.length;

void contexts(Point p, FutureOr<double> Function(FutureOr<double>) f) {
  FutureOr<double> later = p.length;
}

class Arguments {
  void doubles(double a, double? b, num c, int d, Object e, dynamic f,
      FutureOr<double> g, [double h = 0]) {}
  void named({double a = 0, int b = 0, num? c}) {}
}

void arguments(Arguments args, Box<double> box, Box<num> nums) {
  args.doubles(1, 2, 3, 4, 5, 6, 7);
  args.doubles(1, 2, 3, 4, 5, 6, 7, 8);
  args.doubles(1, 2, 3, 4, 5, 6, 7, 8, 9);
  args.doubles((1), ((2)), 3, 4, 5, 6, 7);
  args.named(a: 1, b: 2, c: 3);
  args.named(c: 1, a: 2);
  args.named(z: 1);
  args.doubles(-1, 2, 3, 4, 5, 6, 7);
  box.replace(1);
  nums.replace(2);
}

// A mixin replaces only the members it declares; a member its interface
// inherits from its superclass constraint is merged with the superclass's.
abstract class Shape {
  num get size;
  Object area();
}

class Square implements Shape {
  int get size => 0;
  int area() => 0;
}

mixin Labelled on Shape {
  String get label => '';
}

mixin Resized on Shape {
  double get size => 0;
}

class LabelledSquare extends Square with Labelled {}

class ResizedSquare extends Square with Resized {}

void mixins(LabelledSquare labelled, ResizedSquare resized) {
  labelled.size;
  labelled.area();
  labelled.label;
  resized.size;
  resized.area();
}

// Valid overrides of different types combine into their top merge.
abstract class Left {
  (Object?, dynamic) pair();
  (Object?, dynamic) get both;
}

abstract class Right {
  (dynamic, Object?) pair();
  (dynamic, Object?) get both;
}

class Pair implements Left, Right {
  (int, int) pair() => (1, 2);
  (int, int) get both => (1, 2);
}

extension type Combined(Pair p) implements Left, Right {}

abstract class Joined implements Left, Right {}

void combined(Combined c, Joined j) {
  c.pair();
  c.both;
  j.pair();
  j.both;
}

// A return type that does not resolve makes the invocation invalid, with the
// method in the recovery.
class Unresolved {
  Missing make() => throw 0;
  Missing get missing => throw 0;
}

void unresolved(Unresolved u) {
  u.make();
  u.missing;
}
