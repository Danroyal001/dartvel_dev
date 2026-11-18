// Fixture for extension members in `--members` and `--user-operators`:
// implicit application of accessible extensions (declared here, in a part,
// imported, prefixed, hidden), the most specific of several applicable ones,
// generic extensions, nullable receivers, members an interface lacks,
// operators a class lacks, and explicit overrides `E(x).m()`. Some lines are
// compile-time errors on purpose (ambiguous, inapplicable, hidden, static and
// missing members).
import 'dart:async';
import 'extensions_library.dart' hide HiddenOnString, PrefixedOnInt;
import 'extensions_library.dart' as lib show PrefixedOnInt;

part 'extensions_part.dart';

class Shape {
  double get area => 0;
  int get sides => 0;
  set label(String value) {}
}

class Square extends Shape {
  @override
  double get area => 1;
}

class Vector {
  Vector operator +(Vector other) => this;
}

class Matrix {}

extension OwnOnString on String {
  int get ownLength => length;
  String shout([int times = 1]) => this;
  String pad({required int width, double ratio = 1}) => this;
  bool get isShouting => true;
  String Function(int) get repeater => (int n) => this;
  static String make() => '';
  T generic<T>(T value) => value;
  get implicitGetter => 1;
  implicitMethod() => 1;
  int _private() => 0;
  int sides() => 0;
}

extension ShapeExtras on Shape {
  String describe(int precision) => '';
  int get corners => sides;
  double get area => 2;
  int get label => 0;
  Shape operator -() => this;
  Shape operator ~() => this;
  Shape operator [](int index) => this;
  Shape operator *(double factor) => this;
  Shape operator <(Shape other) => this;
}

extension SquareExtras on Square {
  String describe(int precision) => '';
  int get squareOnly => 0;
}

extension NullableShape on Shape? {
  bool get isMissing => this == null;
  String orEmpty() => '';
  Shape operator +(Shape other) => other;
  Shape operator [](int index) => Shape();
  Shape operator -() => Shape();
}

extension Matrices on Matrix {
  Matrix operator +(Matrix other) => this;
  Matrix operator *(int scale) => this;
  Matrix operator -() => this;
  Matrix operator ~() => this;
  int operator [](int row) => row;
  Matrix operator %(Matrix other) => this;
}

extension BoxedList<T> on List<T> {
  T get head => first;
  List<T> twice() => [...this, ...this];
  T at(int index) => this[index];
  Map<K, T> keyedBy<K>(K key) => {key: first};
  T operator -() => first;
  List<T> operator *(int times) => this;
}

extension Numbers<N extends num> on N {
  N get self => this;
  N plus(N other) => this;
  N operator ~/(N other) => this;
}

extension Pairs<A, B> on Map<A, B> {
  A get anyKey => keys.first;
  B get anyValue => values.first;
}

extension OnIterable<T> on Iterable<T> {
  String get kind => 'iterable';
}

extension OnList<T> on List<T> {
  String get kind => 'list';
}

extension FirstAmbiguous on int {
  int get clash => 0;
  int operator -(int other) => 0;
}

extension SecondAmbiguous on int {
  int get clash => 1;
  int operator -(int other) => 1;
}

extension OnNum on num {
  String get numKind => 'num';
  String get specific => 'num';
}

extension OnInt on int {
  String get specific => 'int';
}

extension OnFunction on int Function(int) {
  int get arity => 1;
  int callTwice(int x) => x;
}

extension OnRecord on (int, String) {
  int get first => $1;
  String get $2 => '';
  String describe() => '';
}

extension OnObject on Object {
  String get tag => '';
}

extension OnNullableObject on Object? {
  String get anyTag => '';
}

extension Setters on String {
  set onlySetter(int value) {}
}

extension OnFuture<T> on Future<T> {
  Future<T> later() => this;
}

extension OnType<T extends Shape> on T {
  T get same => this;
}

enum Fruit { apple, pear }

void implicit(
  String s,
  Shape shape,
  Square square,
  Matrix matrix,
  List<int> ints,
  List<String> strings,
  int i,
  double d,
  num n,
  Map<String, int> map,
  Set<double> doubles,
  Fruit fruit,
  int Function(int) function,
  (int, String) record,
  Future<int> future,
  Vector vector,
) {
  s.ownLength;
  s.shout();
  s.shout(3);
  s.pad(width: 4);
  s.pad(width: 5, ratio: 6);
  s.isShouting;
  s.shout;
  s.repeater;
  s.repeater(7);
  s.importedLength;
  s.importedShout(8);
  s.libraryTag;
  s.tag;
  s.anyTag;
  s.shout().ownLength;
  s.importedShout(9).shout(10).ownLength;
  'literal'.ownLength;
  ('paren').shout(11);
  s.length.prefixedTwice;
  i.prefixedTwice;
  i.prefixedPlus(12);
  shape.describe(13);
  shape.corners;
  shape.area;
  shape.label;
  shape.isMissing;
  shape.orEmpty();
  square.describe(14);
  square.squareOnly;
  square.corners;
  square.same;
  shape.same;
  matrix.tag;
  ints.head;
  ints.twice();
  ints.at(15);
  ints.twice().head;
  strings.head;
  strings.at(16).ownLength;
  ints.kind;
  doubles.kind;
  i.self;
  d.self;
  n.self;
  i.plus(17);
  d.plus(18);
  n.plus(19);
  map.anyKey;
  map.anyValue;
  i.numKind;
  i.specific;
  d.specific;
  fruit.name;
  ints.firstOrNull;
  ints.elementAtOrNull(20);
  function.arity;
  function.callTwice(21);
  record.describe();
  record.first;
  record.$2;
  future.later();
  future.ignore();
  i.tag;
  vector.tag;
  i.clash;
  s.onlySetter;
  s.hiddenLength;
  s.unnamedImported;
  s.make();
  s.generic(22);
  s.implicitGetter;
  s.implicitMethod();
  s._private();
  s.missing;
  shape.sides;
}

void nullable(
  String? maybe,
  Shape? maybeShape,
  Matrix? maybeMatrix,
  int? maybeInt,
  Object? object,
  Null nothing,
) {
  maybe.hashCode;
  maybe.toString();
  maybe.runtimeType;
  maybe.anyTag;
  maybe.ownLength;
  maybe.tag;
  maybeShape.isMissing;
  maybeShape.orEmpty();
  maybeShape.describe(23);
  maybeShape.area;
  maybeShape.hashCode;
  maybeInt.toString();
  maybeInt.isEven;
  object.anyTag;
  object.hashCode;
  nothing.toString();
  nothing.anyTag;
}

void nullAware(String? maybe, Shape? maybeShape) {
  maybe?.ownLength;
  maybeShape?.describe(24);
}

void operators(
  Shape shape,
  Shape? maybeShape,
  Matrix matrix,
  Matrix? maybeMatrix,
  List<int> ints,
  List<String> strings,
  int i,
  double d,
  String s,
  Vector vector,
) {
  -shape;
  ~shape;
  shape[0];
  shape * 2;
  shape * 2.5;
  shape < shape;
  matrix + matrix;
  matrix * 3;
  matrix * (4);
  -matrix;
  ~matrix;
  matrix[5];
  matrix[5] + 6;
  matrix % matrix;
  (matrix + matrix) * 7;
  -(matrix * 8);
  maybeShape + shape;
  maybeShape[9];
  -maybeShape;
  maybeMatrix + matrix;
  -maybeMatrix;
  -ints;
  -strings;
  ints * 10;
  i ~/ 11;
  d ~/ 12;
  i - 13;
  s / 14;
  vector + vector;
  shape + shape;
}

void overrides(
  String s,
  Shape shape,
  Square square,
  Matrix matrix,
  List<int> ints,
  int i,
  double d,
  Shape? maybeShape,
  Map<String, int> map,
) {
  OwnOnString(s).ownLength;
  OwnOnString(s).shout();
  OwnOnString(s).shout(25);
  OwnOnString(s).pad(width: 26);
  OwnOnString(s).shout;
  OwnOnString(s).repeater(27);
  OwnOnString('lit').ownLength;
  OwnOnString(s.shout()).ownLength;
  OwnOnString(s).shout().ownLength;
  ShapeExtras(square).describe(28);
  SquareExtras(square).describe(29);
  ShapeExtras(shape).area;
  ShapeExtras(shape).corners;
  NullableShape(maybeShape).isMissing;
  NullableShape(shape).orEmpty();
  BoxedList(ints).head;
  BoxedList(ints).at(30);
  BoxedList<num>(ints).head;
  BoxedList<num>(ints).at(31);
  BoxedList<int, int>(ints).head;
  Numbers(i).plus(32);
  Numbers(d).self;
  Numbers<num>(i).plus(33);
  Pairs(map).anyValue;
  Pairs<Object, num>(map).anyKey;
  lib.PrefixedOnInt(i).prefixedTwice;
  lib.PrefixedOnInt(i).prefixedPlus(34);
  FirstAmbiguous(i).clash;
  SecondAmbiguous(i).clash;
  OnNum(i).specific;
  OwnOnString(i).ownLength;
  OwnOnString(s).make();
  OwnOnString(s).missing;
  OwnOnString(s).generic(35);
  OwnOnString(s, s).ownLength;
  OwnOnString(s)..ownLength;
  -ShapeExtras(shape);
  ~ShapeExtras(shape);
  ShapeExtras(shape)[36];
  ShapeExtras(shape) * 37;
  Matrices(matrix) + matrix;
  Matrices(matrix) * 38;
  -Matrices(matrix);
  Matrices(matrix)[39];
  -BoxedList(ints);
  -BoxedList<num>(ints);
  BoxedList(ints) * 40;
  Numbers(i) ~/ 41;
  Numbers<num>(i) ~/ 42;
  FirstAmbiguous(i) - 43;
  NullableShape(maybeShape) + shape;
  NullableShape(maybeShape)[44];
  Matrices(matrix) - matrix;
  OwnOnString(s).sides();
}

extension Inside on String {
  int get insideLength => 0;

  void method(String other) {
    other.insideLength;
    insideLength;
    this.insideLength;
    other.ownLength;
  }
}

class Host {
  int get ownLength => 0;

  void method(String s) {
    s.ownLength;
    OwnOnString(s).ownLength;
  }
}

void nullAwareOverride(String s) {
  OwnOnString(s)?.ownLength;
}

void overrideEquality(Matrix matrix) {
  Matrices(matrix) == matrix;
}

void shadowed(String s) {
  var OwnOnString = (String x) => x;
  OwnOnString(s).length;
}

void contexts(String s, Matrix matrix) {
  double typed = s.pad(width: 45).ownLength.toDouble();
  String text = '${s.ownLength} ${matrix * 46}';
  var local = OwnOnString(s).shout(47);
  print(s.importedLength);
}
