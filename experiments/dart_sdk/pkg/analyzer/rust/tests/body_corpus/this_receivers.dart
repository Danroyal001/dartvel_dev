// Fixture for `this` and implicit `this` receivers in `--members` and
// `--user-operators`: `this` as the receiver of member accesses and as an
// operand of operators, unqualified invocations and reads of instance
// members (through the interface of the type of `this`, an applicable
// extension, or the enclosing extension itself), and where `this` is not
// known (static members, initializers, defaults, factories, members where
// flow analysis may promote `this`). Some lines are compile-time errors on
// purpose.
import 'dart:async';

int topLevel() => 0;
int get topGetter => 0;

class Base {
  int inherited(int x) => x;
  String get baseName => '';
}

class Counter extends Base {
  final int count;
  double ratio = 0;
  int Function(int) adder = (int x) => x;
  late int lateField = count + size;
  int initialized = 0;
  int _private = 0;
  var inferred = 1;
  get untyped => 1;

  Counter(this.count) : initialized = 1;

  Counter.named(int count)
      : count = count,
        ratio = 1 {
    describe(1);
    this.describe(2);
    size;
  }

  factory Counter.make() {
    return Counter(0);
  }

  int get size => count;
  String describe(int precision) => '';
  void scale(double factor, {num offset = 0, double? cap}) {}
  T pick<T>(T value) => value;
  int operator +(int other) => count;
  int operator -() => count;
  bool operator [](int index) => true;
  static int make() => 0;
  static int staticUse() => make();
  int _hidden() => 0;

  void members() {
    this.count;
    this.ratio;
    this.size;
    this.describe(3);
    this.describe;
    this.inherited(4);
    this.baseName;
    this.hashCode;
    this.toString();
    (this).size;
    this.size.isEven;
    count;
    ratio;
    size;
    describe(5);
    describe;
    inherited(6);
    baseName;
    hashCode;
    toString();
    size.isEven;
    describe(7).length;
    adder(8);
    scale(9, offset: 10, cap: 11);
    this.scale(12, offset: 13);
    topLevel();
    topGetter;
    _private;
    _hidden();
    this._private;
    inferred;
    untyped;
    pick(14);
    pick<int>(15);
    make();
    missing();
    missingGetter;
    var local = () => size + describe(16).length;
    void nested() {
      count;
      this.count;
    }
  }

  void operators() {
    this + 1;
    -this;
    this[2];
    (this) + 3;
    this + count;
  }

  void shadowed(int count, String Function(int) describe) {
    count;
    describe(17);
    size;
  }

  void cascades() {
    this..describe(18);
    this?.size;
  }

  String withDefault([int value = 0]) => describe(value);
}

class Promoted extends Base {
  int get size => 0;

  bool operator ==(Object other) => this == other || size == 0;

  void tested() {
    if (this is Counter) {
      size;
    }
    this.size;
  }

  void untested() {
    size;
    this.size;
  }
}

class Box<T> {
  final T value;
  Box(this.value);
  T get first => value;
  List<T> all() => [value];
  T take(T next) => next;

  void use() {
    first;
    all();
    this.first;
    this.all().first;
    take(value);
    this;
    this.value;
  }
}

class IntBox extends Box<int> {
  IntBox(super.value);
  void use2() {
    first;
    all();
    this.first.isEven;
  }
}

mixin Named on Base {
  String get name => '';
  void greet() {
    name;
    baseName;
    inherited(19);
    this.name;
  }
}

enum Color {
  red,
  green;

  int get weight => index * 2;
  String label() => name;
  void show() {
    index;
    name;
    weight;
    this.index;
    label();
  }
}

extension type Meters(double value) {
  double get doubled => value * 2;
  Meters plus(Meters other) => this;
  void use() {
    value;
    doubled;
    plus(this);
    this.doubled;
    this.value;
  }
}

extension Strings on String {
  int get size => length;
  String twice() => this + this;
  String pad(double width) => this;
  void use() {
    length;
    this.length;
    size;
    this.size;
    twice();
    this.twice();
    pad(20);
    toUpperCase();
    shout;
    this.shout;
    isEmpty;
    this + '!';
    this[0];
    codeUnitAt(21);
  }
}

extension Loud on String {
  String get shout => toUpperCase();
}

extension MaybeStrings on String? {
  bool get missing => true;
  void use() {
    hashCode;
    toString();
    missing;
    length;
    this.hashCode;
  }
}

extension Lists<T> on List<T> {
  T get head => first;
  T at(int index) => this[index];
  void use() {
    first;
    head;
    at(22);
    this.first;
    length;
    this.head;
    isEmpty;
  }
}

extension Ints on int {
  int get twice => this * 2;
  void use() {
    isEven;
    twice;
    remainder(2);
    this.remainder(3);
    this + 1;
    -this;
    abs();
    this.abs();
  }
}

extension Dynamics on dynamic {
  int get one => 1;
  void use() {
    one;
    foo;
    this.one;
  }
}

extension Futures<T> on Future<T> {
  void use() {
    then((value) => value);
    ignore();
  }
}

extension Setters on String {
  set store(int value) {}
  void use() {
    store;
  }
}

extension Statics on String {
  static int make() => 0;
  int get viaStatic => make();
}
