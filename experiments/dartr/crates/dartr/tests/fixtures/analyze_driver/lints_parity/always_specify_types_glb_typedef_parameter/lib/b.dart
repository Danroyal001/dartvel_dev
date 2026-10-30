typedef G = int Function(String);
typedef R = ({int a});

class F {
  static int test({required int x, G g = _d, R? r, int? y}) => 0;
}

class D {
  static int test({required int x, bool z = true, G g = _d, R? r, int? y}) =>
      0;
}

int _d(String s) => 0;
