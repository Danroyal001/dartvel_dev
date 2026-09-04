// A module's globals are its own, and what it shares is declared.
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

/// Something the parent owns and a module may be given.
class CurrentTenant {
  CurrentTenant(this.name);
  final String name;
}

void main() {
  setUp(() {
    DV.Modules.resetForTesting();
    // What each module shares, as its own pubspec declares it: the
    // specification isolates module globals by default and asks for sharing
    // to be written down.
    DV.Modules.register(id: 'store', mountPath: '/store', config: const <String, Object?>{
      'globals': <String, Object?>{
        'export': <String>['cart'],
        'inherit': <String>['currentTenant'],
      },
    });
    DV.Modules.register(id: 'blog', mountPath: '/blog', config: const <String, Object?>{
      'globals': <String, Object?>{'export': <String>['cart']},
    });
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

  test('a global the module does not export is not readable from outside', () {
    // Isolated by default, shared deliberately. Without this the parent
    // reaches into any module's state and the boundary the module was split
    // along stops meaning anything -- and nothing tells the module's author
    // that a field they thought was private is now somebody's dependency.
    DV.global<Wishlist>(Wishlist(), 'store');

    expect(
      () => DV.Modules('store').global<Wishlist>(),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
          allOf(contains('store'), contains('wishlist'), contains('export')))),
    );
  });

  test('an inherited global comes from the application', () {
    // What inherit: [currentTenant] buys: the module reads the parent's
    // value without naming the parent, so the same module standing alone
    // reads its own.
    DV.global<CurrentTenant>(CurrentTenant('acme'));

    expect(DV.Modules('store').global<CurrentTenant>().name, 'acme');
  });

  test('a global the module does not inherit does not fall through', () {
    // The blog inherits nothing. Falling back to the application anyway
    // would make every module read the parent's state by accident, which is
    // the isolation being asked for.
    DV.global<CurrentTenant>(CurrentTenant('acme'));

    expect(
      () => DV.Modules('blog').global<CurrentTenant>(),
      throwsA(isA<StateError>()),
    );
  });
}
