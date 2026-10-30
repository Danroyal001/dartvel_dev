// The obviousness checks compare types with Dart `==`, which ignores a
// typedef alias.
typedef Parameters = Map<Symbol, String>;
typedef Names = List<String>;

void f(bool b, Parameters parameters, Names names, String s) {
  final newParams = b ? {...parameters, Symbol(s): s} : parameters;
  final same = b ? parameters : parameters;
  final list = b ? [s, ...names] : names;
  final copy = names;
  print([newParams, same, list, copy]);
}
