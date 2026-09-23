// The shop's own rules: what a cart costs, what placing an order does, and
// who may sign in -- against the generated models on a real store.
import 'dart:async';

import 'package:dartvel_core/framework.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/shop/account.dart';
import 'package:dartvel_example/shop/cart.dart';
import 'package:dartvel_example/shop/catalog.dart';
import 'package:dartvel_example/shop/orders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DVMemoryMailProvider mail;

  setUp(() async {
    DV.Database.configure(MemoryDVDatabaseAdapter());
    resetShopStore();
    mail = DVMemoryMailProvider();
    DV.Notifications.mail.useProvider(mail);
    registerDartvelClientJobs();
    DV.global<Cart>(const Cart());
    DV.global<Account>(const Account());
    await openShopStore();
  });

  tearDown(() async {
    Roastery.instance.stop();
    Roastery.instance = Roastery();
    await DVModelSync.reset();
  });

  Product coffee(String slug) =>
      seedCatalog.firstWhere((Product p) => p.slug == slug);

  group('a cart', () {
    test('adds, changes and removes coffees', () {
      final Cart cart = const Cart().add('huila').add('huila').add('nyeri');
      expect(cart.count, 3);
      expect(cart.quantityOf('huila'), 2);
      expect(cart.setQuantity('huila', 0).quantityOf('huila'), 0);
      expect(cart.setQuantity('huila', 0).count, 1);
    });

    test('charges shipping below the free-shipping line and not above it', () {
      // Huila is 17.00: one bag pays shipping, two do not.
      final Cart one = const Cart().add('huila');
      expect(one.subtotalCents(seedCatalog), 1700);
      expect(one.shippingCentsFor(seedCatalog), shippingCents);
      expect(one.totalCents(seedCatalog), 1700 + shippingCents);

      final Cart two = one.add('huila');
      expect(two.subtotalCents(seedCatalog), 3400);
      expect(two.shippingCentsFor(seedCatalog), 0);
      expect(two.totalCents(seedCatalog), 3400);
    });

    test('an empty cart costs nothing, shipping included', () {
      expect(const Cart().totalCents(seedCatalog), 0);
    });

    test('lists what it holds the way a receipt does', () {
      final Cart cart = const Cart().add('huila', 2).add('nyeri');
      expect(cart.summary(seedCatalog), '2 × Huila, 1 × Nyeri');
    });
  });

  group('the store', () {
    test('holds the catalogue once, however often it is opened', () async {
      resetShopStore();
      await openShopStore();
      final List<Product> all = await Product.all();
      expect(
        all.map((Product p) => p.slug),
        unorderedEquals(seedCatalog.map((Product p) => p.slug)),
      );
      expect(all.firstWhere((Product p) => p.slug == 'nyeri').priceCents, 2100);
    });

    test('prices print as money', () {
      expect(formatPrice(1700), r'$17.00');
      expect(formatPrice(2105), r'$21.05');
    });
  });

  group('placing an order', () {
    test('stores it, empties the cart and mails a receipt', () async {
      final Cart cart = const Cart().add('huila').add('nyeri');
      DV.global<Cart>(cart);

      final Order order = await placeOrder(
        cart: cart,
        catalog: seedCatalog,
        email: demoEmail,
      );

      final Order? stored = await Order.find(order.id);
      expect(stored, isNotNull);
      expect(stored!.status, 'placed');
      expect(stored.summary, '1 × Huila, 1 × Nyeri');
      expect(
        stored.totalCents,
        coffee('huila').priceCents + coffee('nyeri').priceCents,
      );
      expect(DV.global<Cart>().isEmpty, isTrue);

      expect(mail.sent, hasLength(1));
      expect(mail.sent.single.to.single.email, demoEmail);
      expect(mail.sent.single.subject, 'Your order ${order.id}');
    });

    test('moves through every stage, and a watcher hears each one', () async {
      Roastery.instance = Roastery(step: const Duration(milliseconds: 10));
      final List<String> heard = <String>[];
      final Completer<void> delivered = Completer<void>();

      final Order order = await placeOrder(
        cart: const Cart().add('harbour-blend'),
        catalog: seedCatalog,
        email: demoEmail,
      );
      final DVModelWatch watch = await Order.watch((List<Order> orders) {
        final String status = orders
            .firstWhere((Order o) => o.id == order.id)
            .status;
        if (heard.isEmpty || heard.last != status) heard.add(status);
        if (status == 'delivered' && !delivered.isCompleted) {
          delivered.complete();
        }
      });
      await delivered.future.timeout(const Duration(seconds: 5));
      await watch.cancel();

      expect(heard, orderStages);
    });
  });

  group('signing in', () {
    late DVLocalAuthProvider auth;

    setUp(() async {
      auth = DVLocalAuthProvider(hasher: DVPasswordHasher(iterations: 1));
      await registerDemoAccount(auth);
      DV.Auth.configure(auth);
    });

    test('the demo account is registered and left signed out', () {
      expect(auth.accounts, contains(demoEmail));
      expect(DV.Auth.currentUser, isNull);
    });

    test('a wrong password is refused and publishes nobody', () async {
      await expectLater(
        signIn(email: demoEmail, password: 'espresso'),
        throwsA(isA<AuthException>()),
      );
      expect(currentAccount.signedIn, isFalse);
    });

    test('the right one publishes the account', () async {
      final Account account = await signIn(
        email: demoEmail,
        password: demoPassword,
      );
      expect(account.name, demoName);
      expect(currentAccount.email, demoEmail);

      await signOut();
      expect(currentAccount.signedIn, isFalse);
      expect(DV.Auth.currentUser, isNull);
    });
  });
}
