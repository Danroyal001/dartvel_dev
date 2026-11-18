// Library that extensions.dart imports for `--members` and
// `--user-operators`: extensions that become accessible through imports, a
// prefixed import, a `hide` combinator, and an unnamed extension that is not
// exported.
extension ImportedOnString on String {
  int get importedLength => length;
  String importedShout(int times) => this;
  String operator /(int parts) => this;
}

extension HiddenOnString on String {
  int get hiddenLength => length;
}

extension PrefixedOnInt on int {
  int get prefixedTwice => this * 2;
  int prefixedPlus(int other) => this + other;
}

extension on String {
  int get unnamedImported => length;
}

extension LibraryOnObject on Object {
  String get libraryTag => '';
}
