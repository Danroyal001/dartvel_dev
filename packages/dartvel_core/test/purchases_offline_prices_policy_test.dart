// What the device holds, what it shows, and where a purchase goes.
//
// Offline, an entitlement holds until its notAfter and then stops: without
// the end, a refunded annual subscription keeps working on a device that
// never reconnects. A price comes from the store in the customer's currency
// or not at all: a converted price above a sheet charging a different tier is
// a mismatch the customer sees at the moment of paying. And a store price is
// counted in integers, because a price held as a double is occasionally
// 9.999999999999998.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const Entitlement analytics = Entitlement('analytics');

const DVPurchaseProduct pro = DVPurchaseProduct(
  'book_pro',
  billable: DVBillable.digital(
    appStore: 'com.example.book.pro',
    play: 'book_pro',
  ),
  entitlements: <Entitlement>{analytics},
);

const DVPurchaseProduct mug = DVPurchaseProduct(
  'mug',
  billable: DVBillable.physical(nativePrice: 1200),
  entitlements: <Entitlement>{},
);

class FixedPrices implements DVStorePriceSource {
  FixedPrices(this.answer);
  final Map<String, DVMoney> answer;
  final List<Set<String>> asked = <Set<String>>[];

  @override
  Future<Map<String, DVMoney>> prices(DVStore store, Set<String> ids) async {
    asked.add(ids);
    return answer;
  }
}

class UnreachablePrices implements DVStorePriceSource {
  @override
  Future<Map<String, DVMoney>> prices(DVStore store, Set<String> ids) async =>
      throw const DVStoreUnavailable('no network');
}

void main() {
  final DateTime start = DateTime.utc(2026, 9, 14, 12);
  late DateTime now;
  late DVMemoryLogSink logs;

  setUp(() {
    now = start;
    logs = DVMemoryLogSink();
  });

  tearDown(DVBillingRates.reset);

  group('an entitlement snapshot offline', () {
    DVEntitlementSnapshots held(List<DVEntitlementSnapshot> snapshots) =>
        DVEntitlementSnapshots(
          snapshots,
          clock: () => now,
          logger: DVLogger(sinks: <DVLogSink>[logs]),
        );

    final DVEntitlementSnapshot thirtyDays = DVEntitlementSnapshot(
      entitlement: 'analytics',
      notAfter: DateTime.utc(2026, 10, 14, 12),
    );

    test('holds until notAfter', () {
      now = DateTime.utc(2026, 10, 14, 11, 59);
      expect(held(<DVEntitlementSnapshot>[thirtyDays]).entitled(analytics),
          isTrue);
      expect(logs.records, isEmpty);
    });

    test('stops at notAfter and says DV-PURCHASE-005', () {
      now = DateTime.utc(2026, 10, 14, 12);
      expect(held(<DVEntitlementSnapshot>[thirtyDays]).entitled(analytics),
          isFalse);
      final DVLogRecord record = logs.records.single;
      expect(record.code, 'DV-PURCHASE-005');
      expect(record.level, DVLogLevel.info);
    });

    test('does not unlock a different entitlement', () {
      expect(
        held(<DVEntitlementSnapshot>[thirtyDays])
            .entitled(const Entitlement('exports')),
        isFalse,
      );
      expect(logs.records, isEmpty);
    });

    test('reads a local clock that is not UTC as the same instant', () {
      now = DateTime.utc(2026, 10, 14, 12).toLocal();
      expect(held(<DVEntitlementSnapshot>[thirtyDays]).entitled(analytics),
          isFalse);
    });
  });

  group('store prices', () {
    DVStorePrices prices(DVStorePriceSource source) =>
        DVStorePrices(source, logger: DVLogger(sinks: <DVLogSink>[logs]));

    test('are shown as the store gives them, in its currency', () async {
      final FixedPrices source = FixedPrices(<String, DVMoney>{
        'book_pro': DVMoney(amount: 999, currency: 'EUR'),
      });

      expect(await prices(source).displayPrice(pro, DVStore.play),
          DVMoney(amount: 999, currency: 'EUR'));
      expect(source.asked.single, <String>{'book_pro'});
    });

    test('are absent when the store cannot be reached: DV-PURCHASE-007',
        () async {
      DVBillingRates.set(from: 'USD', to: 'EUR', rate: 0.92);

      expect(
        await prices(UnreachablePrices()).displayPrice(pro, DVStore.play),
        isNull,
      );
      final DVLogRecord record = logs.records.single;
      expect(record.code, 'DV-PURCHASE-007');
      expect(record.level, DVLogLevel.warn);
    });

    test('are absent for a product the store did not return', () async {
      expect(
        await prices(FixedPrices(const <String, DVMoney>{}))
            .displayPrice(pro, DVStore.appStore),
        isNull,
      );
      expect(logs.records.single.code, 'DV-PURCHASE-007');
    });

    test('are not asked of a store for a physical good', () async {
      await expectLater(
        prices(FixedPrices(const <String, DVMoney>{}))
            .displayPrice(mug, DVStore.play),
        throwsArgumentError,
      );
    });
  });

  group('a store amount becomes integer minor units exactly', () {
    test('from App Store milliunits', () {
      expect(DVStoreMoney.fromMilliunits(9990, 'USD'),
          DVMoney(amount: 999, currency: 'USD'));
      expect(DVStoreMoney.fromMilliunits(150000, 'JPY'),
          DVMoney(amount: 150, currency: 'JPY'));
      expect(DVStoreMoney.fromMilliunits(1234, 'KWD'),
          DVMoney(amount: 1234, currency: 'KWD'));
    });

    test('from Play micros, given as the string Play sends', () {
      expect(DVStoreMoney.fromMicros('1990000', 'USD'),
          DVMoney(amount: 199, currency: 'USD'));
      expect(DVStoreMoney.fromMicros('150000000', 'JPY'),
          DVMoney(amount: 150, currency: 'JPY'));
    });

    test('refusing anything that would need rounding', () {
      expect(() => DVStoreMoney.fromMilliunits(9995, 'USD'),
          throwsArgumentError);
      expect(() => DVStoreMoney.fromMicros('1990001', 'USD'),
          throwsArgumentError);
    });

    test('refusing a decimal where an integer count belongs', () {
      expect(() => DVStoreMoney.fromMicros('1.99', 'USD'), throwsFormatException);
      expect(() => DVStoreMoney.fromMicros('1e6', 'USD'), throwsFormatException);
      expect(() => DVStoreMoney.fromMicros('-1000000', 'USD'),
          throwsArgumentError);
    });

    test('without losing precision on a large amount', () {
      // 2^53 + 1 micros: exactly representable as an int, not as a double.
      expect(DVStoreMoney.fromMicros('9007199254740993000000', 'JPY'),
          DVMoney(amount: 9007199254740993, currency: 'JPY'));
    });
  });

  group('the store policy decides the route', () {
    const DVStorePolicy apple = DVAppleStorePolicy();
    const DVStorePolicy google = DVPlayStorePolicy();

    test('a digital good sold in a store build goes to that store', () {
      expect(apple.route(product: pro, channel: DVPurchaseChannel.appStore),
          DVPurchaseRoute.store);
      expect(google.route(product: pro, channel: DVPurchaseChannel.play),
          DVPurchaseRoute.store);
    });

    test('the web and desktop outside a store go to the gateway', () {
      expect(apple.route(product: pro, channel: DVPurchaseChannel.web),
          DVPurchaseRoute.gateway);
      expect(google.route(product: pro, channel: DVPurchaseChannel.desktop),
          DVPurchaseRoute.gateway);
    });

    test('a physical good goes to the gateway, even in a store build', () {
      expect(apple.route(product: mug, channel: DVPurchaseChannel.appStore),
          DVPurchaseRoute.gateway);
      expect(google.route(product: mug, channel: DVPurchaseChannel.play),
          DVPurchaseRoute.gateway);
    });

    test('a digital good with no identifier for the store is DV-PURCHASE-002',
        () {
      const DVPurchaseProduct playOnly = DVPurchaseProduct(
        'book_pro',
        billable: DVBillable.digital(play: 'book_pro'),
        entitlements: <Entitlement>{analytics},
      );

      expect(
        () => apple.route(product: playOnly, channel: DVPurchaseChannel.appStore),
        throwsA(predicate((Object? e) => '$e'.contains('DV-PURCHASE-002'))),
      );
    });

    test('an application policy replaces the default', () {
      final DVPurchases purchases = DVPurchases(
        products: const <DVPurchaseProduct>[pro],
        stores: const <DVStoreAdapter>[],
        ledger: DVMemoryPurchaseLedger(),
        policy: const ExternalLinkPolicy(),
      );

      expect(
        purchases.route(pro,
            channel: DVPurchaseChannel.appStore, jurisdiction: 'NL'),
        DVPurchaseRoute.gateway,
      );
      expect(purchases.route(pro, channel: DVPurchaseChannel.appStore),
          DVPurchaseRoute.store);
    });
  });
}

/// An application operating under a regime that permits an external link,
/// carrying that decision itself.
class ExternalLinkPolicy extends DVAppleStorePolicy {
  const ExternalLinkPolicy();

  @override
  DVPurchaseRoute route({
    required DVPurchaseProduct product,
    required DVPurchaseChannel channel,
    String? jurisdiction,
  }) {
    if (jurisdiction == 'NL') return DVPurchaseRoute.gateway;
    return super.route(
        product: product, channel: channel, jurisdiction: jurisdiction);
  }
}
