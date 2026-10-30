// The inherited default value is used only when its type is a subtype of
// the super parameter's type.
class D {
  D({Object? v = 'a', Object? w = 1});
}

class E extends D {
  E({int? super.v, int? super.w});
}

void e() {
  E(v: 'a', w: 1);
}
