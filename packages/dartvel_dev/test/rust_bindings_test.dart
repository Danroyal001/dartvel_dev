// Package Structure: "Dartvel also supports rust bindings ... e.g.
// `var a = DV.Rust.Int(1);`". The bindings barrel exported DV, DVRust and
// DVRustInt, and DV had no Rust member, so the spec's own example did not
// compile: the only way in was constructing DVRust by hand.
import 'package:dartvel_dev/dartvel_rust_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the spec example compiles and adds through DV.Rust', () {
    final DVRustInt a = DV.Rust.Int(1);
    final DVRustInt b = DV.Rust.Int(2);
    final DVRustInt c = a + b;

    expect(c.value, 3);
    expect('$c', '3');
  });

  test('DV.Rust is the same surface DVRust constructs', () {
    expect(DV.Rust, isA<DVRust>());
    expect((DV.Rust.Int(7) - DV.Rust.Int(2)).value, 5);
    expect((DV.Rust.Int(6) * DV.Rust.Int(7)).value, 42);
  });
}
