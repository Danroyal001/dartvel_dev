// The subtype match against `Object?` or `Object` compares with Dart `==`,
// which ignores a typedef alias.
typedef Value = Object;
typedef NV = Object?;

abstract class Ref<K, V> {}

List<Object?> a<K>(Ref<K, Value?> refs) => [];
List<Object?> b<K>(Ref<K, NV> refs) => [];
List<Object?> c<K>(Ref<K, Value> refs) => [];
List<Object?> d<K>(Ref<K, Object?> refs) => [];

void g<V, W extends Object>(Ref<int, V> r, Ref<int, W> w, Ref<int, int> n) {
  a(r);
  b(r);
  c(w);
  c(n);
  d(r);
}

extension E<K, V> on Ref<K, V> {
  void m() {
    a(this);
  }
}
