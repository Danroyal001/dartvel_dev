// Fixture for the super, null-aware index and cascade index and assignment
// slice of the body oracle: `super.m(...)` and `super.p` resolved through the
// superclass chain (`getMember(forSuper: true)`, with the abstract member as
// the recovery), `r?[i]` with null shorting, `t..[i]` and `t?..[i]`, and
// `t..p = v` whose value is typed; and what stays out.

class Box {
  String label = '';
  int count = 0;
  List<int> items = [];
  Map<String, String> names = {};
  Box get self => this;
  int operator [](int i) => i;
  void operator []=(int i, int v) {}
}

class Gauge {
  double operator [](double d) => d;
}

typedef Callback = int Function(int);

abstract class Root {
  int get depth => 0;
  String rootName() => '';
}

abstract class Base<T> extends Root {
  T get value;
  String describe() => '';
  int get count => 0;
  int measure(int width, {int height = 0}) => width;
  Callback get callback => (int x) => x;
  late List<String> tags;
  E pick<E>(E e) => e;
  var untyped = 0;
  int _hidden() => 0;
  static int make() => 0;
}

mixin Loud on Base<int> {
  String describe() => super.describe();
  int louder() => super.measure(2) + super.count;
}

mixin Plain {
  String plainName() => super.toString();
  int plainHash() => super.hashCode;
}

mixin Holder<T> {
  T get item => throw 0;
}

mixin Twice on Root, Comparable<int> {
  int twice() => super.compareTo(1) + super.depth;
}

class Impl extends Base<int> with Loud, Holder<String> {
  int get value => 1;
  int get count => 2;

  String describe() {
    super.value;
    super.count;
    super.depth;
    super.rootName();
    super.item;
    super.item.length;
    super.measure(3, height: 4);
    super.measure;
    super.callback(5);
    super.tags;
    super.describe().isEmpty;
    super.louder();
    var closure = () => super.describe();
    closure();
    return super.describe();
  }

  int get total => super.count + super.measure(1);

  operator -() => super.value;

  set total(int v) {
    super.count;
  }

  Impl() {
    super.describe();
  }

  Impl.named() : super() {
    super.value;
  }

  // Stays out: generic, implicitly typed, private, static, missing,
  // null-aware, operators, an initializer and a static member.
  void outside() {
    super.pick(1);
    super.untyped;
    super._hidden();
    super.missing();
    super?.describe();
    super == 1;
  }

  static void statics() {
    super.describe();
  }

  int field = 0;
}

class Promoted extends Base<int> {
  int get value => 1;

  void promoting() {
    super.describe();
    if (this is Impl) {}
  }
}

enum Colour {
  red;

  String show() => super.toString();
  int get code => super.hashCode;
}

extension type Id(int raw) {
  String text() => super.toString();
}

extension Ext on Box {
  String text() => super.toString();
}

extension on List<int>? {
  int? first2() => this?[0];
}

class Wrap {
  Box? box;
  List<int>? numbers;
}

void indexes(List<Box?> boxes, List<List<int>?> lists, Map<String, List<int>?> map, Gauge? gauge) {
  boxes[0]?[1];
  boxes[0]?[1].isEven;
  lists[0]?[1];
  lists[0]?[1].isEven;
  (lists[0]?[1]);
  print(lists[0]?[1]);
  map['a']?[0];
  -lists[0]?[1];
  lists[0]?[1] == 2;
  lists[0]?[1] + 1;
  [lists[0]?[1]];
  gauge?[1];
  lists[0]?..[1]..[2];
  boxes[0]?..label = 'z';
}

void cascades(Box b, Box? n, Gauge g, String text, dynamic d, Wrap w, Map<String, String> m) {
  b..[0];
  b..[1]..[2];
  b..[0].isEven;
  n?..[0];
  n?..[0]..[1];
  g..[3];
  'abc'..[0];
  b..items[0];
  b..label = text;
  b..label = 'x';
  b..label = (text);
  b..label = text..label = 'y';
  n?..label = text;
  b..self.label = text;
  m..['k'] = text;
  d..anything = text;
  b..label = b.label;
  b..label = '$text';
  // Stays out: integer and context-dependent values, compound and if-null
  // assignments, writes and a cascade on an extension override.
  b..count = 1;
  b..count = -1;
  b..label += 'z';
  b..label ??= 'z';
  b..[0] = 1;
  Ext(b)..label;
}

class Sections {
  int operator [](int i) => i;
  String label = '';

  void method(String text) {
    this..[0];
    this..label = text;
  }
}
