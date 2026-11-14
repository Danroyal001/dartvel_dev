// Integer literals whose context type comes from a declared type annotation,
// or which have none: `double` (or `double?`, `FutureOr<double>`, an alias of
// one) makes an integer literal a `double`, every other context an `int`.
// The annotations are resolved where they are written: through aliases,
// type parameters, members that shadow a name, and imports.
import 'dart:async';
import 'dart:async' as async;
part 'integers_part.dart';

typedef Real = double;
typedef Maybe<T> = FutureOr<T>;
typedef Same<T> = T;
typedef Bounded<T extends double> = T;
typedef Fixed<T> = double;

double real = 1;
double? nullable = -2;
int whole = 3;
num number = 4;
Object object = 5;
dynamic anything = 6;
Real aliased = 7;
Maybe<double> maybeDouble = 8;
Maybe<int> maybeInt = 9;
Maybe raw = 10;
Same<double> same = 11;
Same<double?> sameNullable = 12;
Bounded bounded = 13;
Fixed<int> fixed = 14;
FutureOr<double> futureOr = 15;
FutureOr<double?>? futureOrNullable = 16;
async.FutureOr<double> prefixed = 17;
Future<double>? future = null;
Comparable<num> comparable = 18;
var untyped = 19;
final double parenthesized = (20), negated = (-21), negatedParentheses = -(22);
const double constant = 23, other = 24;
late double late = 25;
Unknown unknown = 26;

double topLevel([double a = 27, int b = 28, Real c = -29]) {
  return 30;
}

double arrow({double named = 31}) => 32;
num numeric() => 33;
Future<double> asynchronous() async => 34;
Future<double> asyncBlock() async {
  return 35;
}

FutureOr<double> futureOrReturn() async => 36;
Future<int> asyncInt() async => 37;
double sync() async => 38;
Iterable<double> generator() sync* {
  yield 39;
}

double get topGetter => 40;
void returnsVoid() => 41;

class Members<T, double> {
  double shadowedByTypeParameter = 42;
  Real alias = 43;
  T typeParameter = 44;
  static FutureOr<Real> futureOfAlias = 45;

  Members([Real initial = 46]);

  double method([double x = 47]) => 48;
  Real get getter => 49;
  Real operator +(Object other) => 50;
  S generic<S>([S? value = null, Real r = 51]) => throw 52;
}

class Shadowing {
  int Real = 0;
  Real field = 53;
  static void FutureOr() {}
  FutureOr<double> other = 54;
}

mixin Mixin {
  Real mixed = 55;
}

enum Kind {
  one;

  final Real value = 56;
  Real get doubled => 57;
}

extension Extension on int {
  Real get extended => 58;
}

extension type Wrapper(double value) {
  Real get unwrapped => 59;
}

void locals(double parameter, [double defaulted = 60]) {
  double local = 61;
  Real aliased = 62;
  int whole = 63;
  final double finalLocal = 64, second = (65);
  var inferred = 66;
  for (double i = 67; i < 68; i++) {}
  for (Real r = 69;;) {}
  double nested() => 70;
  Real nestedBlock() {
    return 71;
  }

  num inner() {
    double closure() => 72;
    var function = () {
      return 73;
    };
    return 74;
  }

  var list = <double>[75, -76, (77), if (true) 78 else 79, for (;;) 80];
  var ints = <int>[81, 82];
  var untypedList = [83];
  var set = <Real>{84, if (false) 85};
  var map = <String, double>{'a': 86, if (true) 'b': 87, for (;;) 'c': 88};
  var keys = <double, int>{89: 90};
  var wrong = <double, double>[91];
  var maybeList = <FutureOr<double>>[92];
  93;
  (94);
  -95;
  '${96} ${-97}';
  print(98);
  local + 99;
  local = 100;
  local += 101;
  [102];
  void localDefault([double x = 103, int y = 104]) {}
  var closureDefault = ([double x = 105]) => x;
  if (local > 106) {}
}

class Local {
  void shadows(int double) {
    double x = 107;
  }

  void localShadows() {
    var Real = 1;
    Real r = 108;
  }

  void genericShadows<Real>() {
    Real r = 109;
  }
}
