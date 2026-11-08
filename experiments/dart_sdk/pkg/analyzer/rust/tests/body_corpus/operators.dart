// Expressions whose static type their operator fixes: `is`, `is!`, `!`,
// `&&`, `||`, `throw`, `rethrow`, and parentheses around those or literals.
// Operands are deliberately of every kind, resolved or not.
const both = true && false;
const either = (true || false);
final negated = !both;
bool check(Object value, bool flag) =>
    value is int && !flag || (value is! String) && ((flag));
Never fail(String message) => throw message;

class Box {
  final bool open;
  const Box(this.open) : assert(open || !open);
  bool get closed => !open;
  bool test(Object? other) => other is Box && other.open == open;
}

void statements(Object? value, List<int> items) {
  if (value is String || value == null) {}
  while (!(value is int)) {
    break;
  }
  for (var i = 0; i < items.length && items[i] > 0; i++) {}
  var unresolved = undefinedName is int || !undefinedFlag;
  var closure = () => throw StateError('closure');
  try {
    throw ArgumentError(value is num ? 'n' : 's');
  } on ArgumentError {
    rethrow;
  } catch (error) {
    if (!(error is Exception)) rethrow;
  }
  switch (value) {
    case int number when number > 0 && !(number == 3):
      print((('nested')));
    case _:
      (throw 'unreachable');
  }
  var list = [if (value is bool && value) 1, for (var x in items) x is int];
  assert(!(items.isEmpty || items.length > 9), 'message');
  value ?? (throw 'missing');
  return;
  var dead = value is int && (true || false);
}
