// A reference to a getter of a generic class whose type mentions the type
// parameter resolves to a fresh `SubstitutedGetterElementImpl`, whose
// `variable` is a fresh `SubstitutedFieldElementImpl`, so
// `canonicalElementsAreEqual` is false for two such references.
class Box<T> {
  Box(this.value);
  T value;
  int count = 0;
}

class Holder {
  static final Box<List<int>> _box = Box<List<int>>(<int>[]);
  final Box<int?> nullable = Box<int?>(null);

  List<int> generic() {
    _box.value = <int>[1];
    return _box.value;
  }

  int plain() {
    _box.count = 2;
    return _box.count;
  }

  int? conditionalGeneric() {
    if (nullable.value == null) {
      nullable.value = 1;
    }
    return nullable.value;
  }

  void conditionalPlain(Box<int?> b) {
    if (_box.count == null) {
      _box.count = 3;
    }
  }
}

List<int> local(Box<List<int>> b) {
  b.value = <int>[];
  return b.value;
}

int localPlain(Box<List<int>> b) {
  b.count = 1;
  return b.count;
}
