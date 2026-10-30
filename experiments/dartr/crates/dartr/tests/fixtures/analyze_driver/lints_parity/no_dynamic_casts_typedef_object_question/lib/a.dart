// `targetType == objectQuestionType` is Dart `==`, which ignores a typedef
// alias of `Object?`.
typedef Value = Object?;
typedef Model = Map<String, Value>;

void take(Value v) {}

void f(dynamic d, List<dynamic> list, Model model, Iterable raw) {
  take(d);
  model['k'] = d;
  for (Value v in list) {
    take(v);
  }
  Value x = d;
  x = d;
  print(x);
  raw.map((e) => take(e));
  int i = d;
  print(i);
}
