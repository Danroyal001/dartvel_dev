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
  test('DV.Rust.Float is an f64 and follows Rust where Dart differs', () {
    final DVRustFloat a = DV.Rust.Float(1.5);
    final DVRustFloat b = DV.Rust.Float(2.25);

    expect((a + b).value, 3.75);
    expect((b - a).value, 0.75);
    expect((a * b).value, 3.375);
    expect((DV.Rust.Float(1) / DV.Rust.Float(4)).value, 0.25);
    // f64 division by zero is infinity in Rust, not an error.
    expect((DV.Rust.Float(1) / DV.Rust.Float(0)).value, double.infinity);
    // Rust's % on f64 is the remainder, signed like the dividend:
    // -7.5 % 2.0 == -1.5. Dart's % is Euclidean and would give 0.5 --
    // a plausible wrong answer, which is why it is asserted.
    expect((DV.Rust.Float(-7.5) % DV.Rust.Float(2)).value, -1.5);
    expect((DV.Rust.Float(7.5) % DV.Rust.Float(-2)).value, 1.5);
    expect('${DV.Rust.Float(0.5)}', '0.5');
    expect(DV.Rust.Float(2) == DV.Rust.Float(2), isTrue);
  });
}
