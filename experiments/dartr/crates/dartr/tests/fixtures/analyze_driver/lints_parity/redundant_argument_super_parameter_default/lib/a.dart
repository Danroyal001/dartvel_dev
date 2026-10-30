// A super parameter without a default of its own takes the default value of
// the super constructor parameter (`null` for an optional one without a
// default), from this library or another one.
class A {
  A({int? x, int y = 2, this.z});
  final int? z;
}

class B extends A {
  B({super.x, super.y, super.z});
}

class C extends B {
  C({super.x, super.y});
}

void local() {
  B(x: null, y: 2, z: null);
  C(x: null, y: 2);
  A(x: null, y: 2, z: null);
}
