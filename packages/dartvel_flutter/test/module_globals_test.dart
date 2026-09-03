// A module's globals are its own.
//
// The specification gives modules scoped DV.global registries -- Dartvel
// adds no separate dependency-injection primitive -- and a generated
// convenience for reaching one: DV.Modules.store.global<Cart>(). Two
// modules that each keep a Cart must keep two carts; one registry for both
// is the bug the namespace exists to prevent.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class Cart {
  Cart(this.owner);
  final String owner;
}

/// A type nothing registers, so reading it is a read of nothing. The
/// registry is static, so a type another test has written is written for
/// every test after it.
class Wishlist {}

void main() {
  setUp(() {
    DV.Modules.resetForTesting();
    DV.Modules.register(id: 'store', mountPath: '/store');
    DV.Modules.register(id: 'blog', mountPath: '/blog');
  });

  test('a module\'s global is scoped to that module', () {
    DV.Modules('store').global<Cart>(Cart('store'));
    DV.Modules('blog').global<Cart>(Cart('blog'));

    expect(DV.Modules('store').global<Cart>().owner, 'store');
    expect(DV.Modules('blog').global<Cart>().owner, 'blog');
  });

  test('a module\'s global is not the application\'s', () {
    DV.global<Cart>(Cart('app'));
    DV.Modules('store').global<Cart>(Cart('store'));

    expect(DV.global<Cart>().owner, 'app');
    expect(DV.Modules('store').global<Cart>().owner, 'store');
  });

  test('reading before writing fails, naming the module it looked in', () {
    // Not a null that spreads: an unregistered global is a mistake to see
    // where it is made, and which registry was searched is half the answer.
    expect(
      () => DV.Modules('store').global<Wishlist>(),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('store'))),
    );
  });
}
