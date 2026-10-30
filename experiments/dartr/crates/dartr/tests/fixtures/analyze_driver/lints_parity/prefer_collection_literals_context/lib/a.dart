// `InstanceCreationExpression.approximateContextType`: an assignment, a
// named or positional argument, a return or a field initializer whose
// context is a `LinkedHashMap`/`LinkedHashSet` allows the constructor call.
import 'dart:collection';

class Token {
  LinkedHashMap<Object, String> data;
  LinkedHashSet<int>? set;
  Token({required this.data});
  Token.positional(this.data);
  Token.init() : data = LinkedHashMap(), set = LinkedHashSet();
}

LinkedHashMap<Object, String>? field;
LinkedHashSet<int>? setField;

LinkedHashMap<int, int> returned() {
  return LinkedHashMap();
}

LinkedHashSet<int> arrow() => LinkedHashSet();

void f(Map<int, int> m, Set<int> s) {
  final a = field = LinkedHashMap<Object, String>();
  setField = LinkedHashSet();
  Token(data: LinkedHashMap<Object, String>());
  Token.positional(LinkedHashMap());
  final b = LinkedHashMap<int, int>();
  final c = LinkedHashSet<int>();
  final Map<int, int> d = LinkedHashMap();
  final e = (LinkedHashMap<int, int>());
  m = LinkedHashMap();
  s = LinkedHashSet();
  final g = Map<int, int>();
  final h = Set<int>.from([1]);
  final i = [1].toSet();
  print([a, b, c, d, e, g, h, i, m, s]);
}
