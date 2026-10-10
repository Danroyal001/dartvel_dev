// The server half for what the device half sells: consumables, Telegram
// Stars, the gateway on the web, and notifications that carry nothing to
// apply.
//
// Each of these fails quietly when it is wrong. A consumable credited twice
// for one receipt is free coins; a consumable treated as an entitlement is a
// pack of coins that never runs out; a store "test" notification refused as
// a bad signature makes the store retry it for days; a web build that sends a
// digital good to a gateway nobody configured shows a button that does
// nothing.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const Entitlement pro = Entitlement('pro');

const DVPurchaseProduct coins = DVPurchaseProduct(
  'coins_100',
  billable: DVBillable.digital(
    appStore: 'com.example.coins100',
    play: 'coins_100',
    telegram: 'coins_100',
    telegramStars: 50,
  ),
  entitlements: <Entitlement>{},
  kind: DVPurchaseKind.consumable,
);

const DVPurchaseProduct monthly = DVPurchaseProduct(
  'pro_monthly',
  billable: DVBillable.digital(appStore: 'com.example.pro', play: 'pro'),
  entitlements: <Entitlement>{pro},
);

final DateTime start = DateTime.utc(2026, 10, 1, 12);

class _NothingToApply extends DVFakeStoreAdapter {
  _NothingToApply() : super(DVStore.appStore, signingKey: 'k');

  @override
  Future<DVStoreNotification> verifyNotification(
          String body, Map<String, String> headers) async =>
      throw const DVStoreNothingToApply('a TEST notification');
}

class _CatalogStore extends DVFakeStoreAdapter implements DVStoreCatalogAware {
  _CatalogStore() : super(DVStore.play, signingKey: 'k');
  Map<String, DVPurchaseKind>? catalog;

  @override
  void useCatalog(Map<String, DVPurchaseKind> storeProducts) =>
      catalog = storeProducts;
}

class _Gateway extends DVLocalBillingProvider {
  final List<String> plans = <String>[];

  @override
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) async {
    plans.add(plan.id);
    return DVBillingCheckoutSession(
      id: 'cs_1',
      plan: plan,
      customer: customer,
      createdAt: start,
      checkoutUrl: Uri.parse('https://checkout.example/cs_1'),
    );
  }
}

const BillingPlan proPlan = BillingPlan(
  id: 'pro',
  displayName: 'Pro',
  priceMinorUnits: 0,
  currency: 'USD',
);

DVStoreTransaction tx(
  String original, {
  DVStore store = DVStore.play,
  String product = 'coins_100',
  DateTime? revokedAt,
  DateTime? signedAt,
  Duration? expiresIn,
}) =>
    DVStoreTransaction(
      store: store,
      originalTransactionId: original,
      transactionId: original,
      storeProductId: product,
      purchasedAt: start,
      signedAt: signedAt ?? start,
      expiresAt: expiresIn == null ? null : start.add(expiresIn),
      revokedAt: revokedAt,
      acknowledged: true,
    );

void main() {
  late DVFakeStoreAdapter play;
  late List<DVPurchaseChange> changes;
  late DVPurchases purchases;

  setUp(() {
    play = DVFakeStoreAdapter(DVStore.play,
        signingKey: 'k', acknowledgementWindow: const Duration(days: 3));
    changes = <DVPurchaseChange>[];
    purchases = DVPurchases(
      products: const <DVPurchaseProduct>[coins, monthly],
      stores: <DVStoreAdapter>[play],
      ledger: DVMemoryPurchaseLedger(),
      clock: () => start.add(const Duration(minutes: 1)),
      onChange: changes.add,
      logger: DVLogger(sinks: <DVLogSink>[DVMemoryLogSink()]),
    );
  });

  group('a consumable', () {
    test('is credited once per purchase and grants no entitlement', () async {
      play.issue('r1', tx('tok_1'));

      final DVPurchaseResult first =
          await purchases.verifyPurchase(DVStore.play, 'r1', customer: 'alice');
      final DVPurchaseResult again =
          await purchases.verifyPurchase(DVStore.play, 'r1', customer: 'alice');

      expect(first.consumed, <String>{'coins_100'});
      expect(again.consumed, isEmpty,
          reason: 'the same receipt presented twice is one purchase');
      expect(changes, hasLength(1));
      expect(changes.single.consumed, <String>{'coins_100'});
      expect(await purchases.snapshots('alice'), isEmpty,
          reason: 'a consumable is spent, not held');
    });

    test('a second purchase of the same product is credited again', () async {
      play.issue('r1', tx('tok_1'));
      play.issue('r2', tx('tok_2'));
      await purchases.verifyPurchase(DVStore.play, 'r1', customer: 'alice');
      final DVPurchaseResult second =
          await purchases.verifyPurchase(DVStore.play, 'r2', customer: 'alice');
      expect(second.consumed, <String>{'coins_100'});
      expect(changes.expand((DVPurchaseChange c) => c.consumed), hasLength(2));
    });

    test('a refund is reported as a reversal, with when it happened',
        () async {
      play.issue('r1', tx('tok_1'));
      await purchases.verifyPurchase(DVStore.play, 'r1', customer: 'alice');
      final DateTime refunded = start.add(const Duration(seconds: 30));
      final DVSignedStoreNotification signed = play.sign(DVStoreNotification(
        notificationId: 'n1',
        type: 'voided',
        signedAt: refunded,
        transaction: tx('tok_1', revokedAt: refunded, signedAt: refunded),
      ));

      await purchases.acceptNotification(DVContext(), DVStore.play,
          body: signed.body, headers: signed.headers);

      expect(changes.last.refunded, <String>{'coins_100'});
      expect(changes.last.revokedAt, refunded);
      expect(changes.last.consumed, isEmpty);
    });
  });

  test('a notification with nothing to apply is acknowledged, not refused',
      () async {
    final DVPurchases apple = DVPurchases(
      products: const <DVPurchaseProduct>[monthly],
      stores: <DVStoreAdapter>[_NothingToApply()],
      ledger: DVMemoryPurchaseLedger(),
    );
    final DVPurchaseResult result = await apple.acceptNotification(
        DVContext(), DVStore.appStore,
        body: '{}', headers: const <String, String>{});
    expect(result.ignored, isTrue);
    expect(result.handled, isFalse);
  });

  test('an adapter that needs the catalog is told every product kind', () {
    final _CatalogStore store = _CatalogStore();
    DVPurchases(
      products: const <DVPurchaseProduct>[coins, monthly],
      stores: <DVStoreAdapter>[store],
      ledger: DVMemoryPurchaseLedger(),
    );
    expect(store.catalog, <String, DVPurchaseKind>{
      'coins_100': DVPurchaseKind.consumable,
      'pro': DVPurchaseKind.subscription,
    });
  });

  group('Telegram', () {
    test('a digital good in a Mini App goes to Stars', () {
      expect(
          purchases.route(coins, channel: DVPurchaseChannel.telegram),
          DVPurchaseRoute.store);
    });

    test('a digital good with no Stars product cannot be sold there', () {
      expect(
        () => purchases.route(monthly, channel: DVPurchaseChannel.telegram),
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', contains('DV-PURCHASE-002'))),
      );
    });

    test('the telegram store id is the declared one', () {
      expect(coins.identifierOn(DVStore.telegram), 'coins_100');
    });
  });

  group('the gateway', () {
    test('refuses cleanly when none is configured', () async {
      await expectLater(
        purchases.checkout(monthly, customer: 'alice'),
        throwsA(isA<DVPurchaseRefused>()
            .having((DVPurchaseRefused r) => r.code, 'code', 'DV-PURCHASE-009')),
      );
    });

    test('refuses a product with no plan rather than charging another',
        () async {
      final DVPurchases withGateway = DVPurchases(
        products: const <DVPurchaseProduct>[coins, monthly],
        stores: <DVStoreAdapter>[play],
        ledger: DVMemoryPurchaseLedger(),
        gateway: _Gateway(),
        gatewayPlans: const <String, BillingPlan>{'pro_monthly': proPlan},
      );
      await expectLater(
        withGateway.checkout(coins, customer: 'alice'),
        throwsA(isA<DVPurchaseRefused>()
            .having((DVPurchaseRefused r) => r.code, 'code', 'DV-PURCHASE-009')),
      );
    });

    test('opens the plan the product names, and its grant reaches devices',
        () async {
      final _Gateway gateway = _Gateway();
      final DVPurchases withGateway = DVPurchases(
        products: const <DVPurchaseProduct>[coins, monthly],
        stores: <DVStoreAdapter>[play],
        ledger: DVMemoryPurchaseLedger(),
        gateway: gateway,
        gatewayPlans: const <String, BillingPlan>{'pro_monthly': proPlan},
        clock: () => start,
      );

      final Uri url = await withGateway.checkout(monthly, customer: 'alice');
      expect(url, Uri.parse('https://checkout.example/cs_1'));
      expect(gateway.plans, <String>['pro']);

      expect(await withGateway.entitled('alice', pro), isFalse);
      gateway.grant('alice', pro);
      expect(await withGateway.entitled('alice', pro), isTrue);
      final List<DVEntitlementSnapshot> held =
          await withGateway.snapshots('alice');
      expect(held.single.entitlement, 'pro');
      expect(held.single.notAfter, start.add(const Duration(days: 7)));
    });
  });

  test('restore on the server still needs what it restores', () async {
    await expectLater(purchases.restore(customer: 'alice'), throwsArgumentError);
  });
}
