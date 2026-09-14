// A sale, and the refund that reverses it.
//
// Money failures that stay silent: a charge retried by a double-click that
// captures twice; a promotion redeemed for a charge that then failed; two
// partial refunds that each fit what is left and together exceed what was
// captured; the tax on three partial refunds rounded one at a time and summing
// to a cent more than was collected; a refund that revokes an entitlement the
// customer still holds from another sale; a reversal half-done because a
// compensation failed, which nobody hears about. A refund is a reversible
// transaction: the entitlement, the stock and the credit all move, or none do,
// and a compensation that fails is DV-COMMERCE-004.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String table = '''
{
  "asOf": "2026-09-01",
  "rounding": {"mode": "halfUp", "scope": "document"},
  "jurisdictions": {
    "GB": {"discountBasis": "afterDiscount",
           "rates": {"digitalService": "20", "physicalGood": "20"}}
  }
}
''';

const DVTaxAddress london = DVTaxAddress(country: 'GB');
const Entitlement pro = Entitlement('pro');

DVMoney gbp(int amount) => DVMoney(amount: amount, currency: 'GBP');

DVOrderLine line(String ref, int pence, {int quantity = 1}) => DVOrderLine(
      reference: ref,
      productId: 'course',
      unitPrice: gbp(pence),
      quantity: quantity,
      category: DVTaxCategory.digitalService,
    );

class Customer implements DVBillingCustomer {
  const Customer(this.id);
  final String id;
  @override
  String get billingCustomerId => 'customer:$id';
}

const Customer alice = Customer('alice');

/// A gateway that, like a real one, answers a repeated idempotency key with
/// the first answer.
class FakeGateway implements DVPaymentGateway {
  final Map<String, DVGatewayCharge> charges = <String, DVGatewayCharge>{};
  final Map<String, DVGatewayRefund> refunds = <String, DVGatewayRefund>{};
  int chargeCalls = 0;
  int refundCalls = 0;
  bool failCharges = false;
  bool failRefunds = false;
  int? captureInstead;

  int get refunded => refunds.values
      .fold<int>(0, (int s, DVGatewayRefund r) => s + r.amount.amount);

  @override
  Future<DVGatewayCharge> charge({
    required String orderId,
    required String customerKey,
    required DVMoney amount,
    required String idempotencyKey,
  }) async {
    chargeCalls++;
    await Future<void>.delayed(Duration.zero);
    if (failCharges) throw StateError('card_declined');
    return charges.putIfAbsent(
      idempotencyKey,
      () => DVGatewayCharge(
        reference: 'ch_${charges.length + 1}',
        amount: captureInstead == null
            ? amount
            : DVMoney(amount: captureInstead!, currency: amount.currency),
      ),
    );
  }

  @override
  Future<DVGatewayRefund> refund({
    required String chargeReference,
    required DVMoney amount,
    required String idempotencyKey,
  }) async {
    refundCalls++;
    await Future<void>.delayed(Duration.zero);
    if (failRefunds) throw StateError('refund failed at the gateway');
    return refunds.putIfAbsent(
      idempotencyKey,
      () => DVGatewayRefund(
          reference: 're_${refunds.length + 1}', amount: amount),
    );
  }
}

class Unreachable implements DVTaxProvider {
  @override
  Future<DVTaxQuote> quote(DVTaxRequest request) async =>
      throw const DVTaxUnavailable('connection refused');
}

void main() {
  final DateTime now = DateTime.utc(2026, 9, 14, 12);
  late DVMemoryLogSink logs;
  late DVLogger logger;
  late FakeGateway gateway;
  late DVLocalBillingProvider billing;
  late DVMemoryCommerceLedger ledger;
  late DVMemoryPromotionLedger redemptions;
  late DVCommerce commerce;

  List<String> codes() =>
      logs.records.map((DVLogRecord r) => r.code).whereType<String>().toList();

  DVCommerce build({DVTaxProvider? provider, DVOfflineTaxTable? offline}) =>
      DVCommerce(
        tax: DVTax(
          provider: provider ??
              DVTableTaxProvider(DVTaxTable.fromJson(table), clock: () => now),
          offline: offline,
          clock: () => now,
          logger: logger,
        ),
        gateway: gateway,
        ledger: ledger,
        promotions: DVPromotions(
          promotions: const <DVPromotion>[
            DVPromotion(
              id: 'save10',
              code: 'SAVE10',
              discount: DVDiscount.percent(10),
              stacking: DVPromotionStacking.group('coupons'),
              maxRedemptions: 1,
            ),
          ],
          policy: const DVAnyCustomerPromotionPolicy(),
          ledger: redemptions,
          clock: () => now,
          logger: logger,
        ),
        grants: DVLocalBillingGrants(billing),
        clock: () => now,
        logger: logger,
      );

  setUp(() {
    logs = DVMemoryLogSink();
    logger = DVLogger(sinks: <DVLogSink>[logs]);
    gateway = FakeGateway();
    billing = DVLocalBillingProvider();
    ledger = DVMemoryCommerceLedger();
    redemptions = DVMemoryPromotionLedger();
    commerce = build();
  });

  Future<DVSale> sell(String orderId,
          {List<String> codes = const <String>[], List<DVOrderLine>? lines}) =>
      commerce.charge(
        orderId: orderId,
        customer: alice,
        lines: lines ?? <DVOrderLine>[line('a', 1000)],
        to: london,
        codes: codes,
        entitlements: const <Entitlement>{pro},
      );

  Future<bool> entitled() => billing.hasEntitlement('customer:alice', pro);

  group('a charge', () {
    test('is priced on the server: discount, then tax on what is left',
        () async {
      final DVSale sale = await sell('o1',
          codes: <String>['SAVE10'],
          lines: <DVOrderLine>[line('a', 1000), line('b', 500, quantity: 2)]);
      expect(sale.subtotal, gbp(2000));
      expect(sale.discount, gbp(200));
      expect(sale.tax, gbp(360));
      expect(sale.total, gbp(2160));
      expect(sale.status, DVSaleStatus.captured);
      expect(sale.promotions, <String>['save10']);
      expect(gateway.charges['charge:o1']!.amount, gbp(2160));
      expect(sale.chargeReference, 'ch_1');
      expect(
          sale.lines.fold<int>(0, (int s, DVSaleLine l) => s + l.discount.amount),
          200);
      expect(sale.lines.fold<int>(0, (int s, DVSaleLine l) => s + l.tax.amount),
          360);
      expect(await entitled(), isTrue);
      expect(await redemptions.redeemed('save10'), 1);
    });

    test('for the same order twice captures once', () async {
      final DVSale first = await sell('o1');
      final DVSale second = await sell('o1');
      expect(second.chargeReference, first.chargeReference);
      expect(gateway.chargeCalls, 1);
    });

    test('for the same order at the same moment captures once', () async {
      final List<DVSale> sales = await Future.wait(<Future<DVSale>>[
        for (int i = 0; i < 5; i++) sell('o1'),
      ]);
      expect(gateway.chargeCalls, 1);
      expect(sales.map((DVSale s) => s.id).toSet(), <String>{'o1'});
    });

    test('refused by tax captures nothing and gives the promotion back',
        () async {
      commerce = build(provider: Unreachable());
      await expectLater(
        sell('o1', codes: <String>['SAVE10']),
        throwsA(isA<DVSaleRefused>()),
      );
      expect(gateway.chargeCalls, 0);
      expect(await redemptions.redeemed('save10'), 0);
      expect(await ledger.find('o1'), isNull);
      expect(await entitled(), isFalse);
    });

    test('declined at the gateway undoes everything before it', () async {
      gateway.failCharges = true;
      await expectLater(
          sell('o1', codes: <String>['SAVE10']), throwsStateError);
      expect(await redemptions.redeemed('save10'), 0);
      expect(await ledger.find('o1'), isNull);
      expect(await entitled(), isFalse);
    });

    test('that captured a different amount is reversed, not recorded',
        () async {
      gateway.captureInstead = 999;
      await expectLater(sell('o1'), throwsStateError);
      expect(await ledger.find('o1'), isNull);
      expect(gateway.refunded, 999);
    });

    test('priced from the offline table is marked on the record', () async {
      commerce = build(
        provider: Unreachable(),
        offline: DVOfflineTaxTable(
          table: DVTaxTable.fromJson(table),
          staleAfter: const Duration(days: 30),
        ),
      );
      final DVSale sale = await sell('o1');
      expect(sale.needsRerating, isTrue);
      expect(sale.taxSource, DVTaxSource.offlineTable);
      expect((await ledger.needingRerating()).map((DVSale s) => s.id),
          <String>['o1']);
      expect(codes(), contains('DV-COMMERCE-001'));
    });
  });

  group('a refund', () {
    test('cannot exceed what was captured', () async {
      final DVSale sale = await sell('o1'); // 1200
      await commerce.refund(saleId: sale.id, refundId: 'r1', amount: gbp(1000));
      await expectLater(
        commerce.refund(saleId: sale.id, refundId: 'r2', amount: gbp(201)),
        throwsA(isA<DVRefundRefused>().having(
            (DVRefundRefused e) => e.remaining, 'remaining', gbp(200))),
      );
      expect(gateway.refunded, 1000);
      final DVRefund rest =
          await commerce.refund(saleId: sale.id, refundId: 'r3');
      expect(rest.amount, gbp(200));
      expect((await ledger.find('o1'))!.refunded, gbp(1200));
    });

    test('cannot exceed what was captured when refunds arrive together',
        () async {
      final DVSale sale = await sell('o1'); // 1200
      final List<Object> outcomes = await Future.wait(<Future<Object>>[
        for (int i = 0; i < 5; i++)
          commerce
              .refund(saleId: sale.id, refundId: 'r$i', amount: gbp(500))
              .then<Object>((DVRefund r) => r)
              .catchError((Object e) => e),
      ]);
      expect(outcomes.whereType<DVRefund>(), hasLength(2));
      expect(outcomes.whereType<DVRefundRefused>(), hasLength(3));
      expect(gateway.refunded, 1000);
    });

    test('reverses tax cumulatively, so partial refunds sum to the tax',
        () async {
      final DVSale sale = await sell('o1'); // 1000 + 200 tax
      final List<int> taxes = <int>[
        for (int i = 0; i < 3; i++)
          (await commerce.refund(
                  saleId: sale.id, refundId: 'r$i', amount: gbp(400)))
              .tax
              .amount,
      ];
      // Each alone is 66.67p, which rounds to 67p three times: 201p.
      expect(taxes, <int>[67, 66, 67]);
      expect(taxes.reduce((int a, int b) => a + b), sale.tax.amount);
    });

    test('with the same refund id is made once', () async {
      final DVSale sale = await sell('o1');
      await commerce.refund(saleId: sale.id, refundId: 'r1', amount: gbp(100));
      await commerce.refund(saleId: sale.id, refundId: 'r1', amount: gbp(100));
      expect(gateway.refundCalls, 1);
      expect((await ledger.find('o1'))!.refunded, gbp(100));
    });

    test('in full revokes what the sale granted, unless another sale holds it',
        () async {
      final DVSale first = await sell('o1');
      final DVSale second = await sell('o2');
      await commerce.refund(saleId: first.id, refundId: 'r1', amount: gbp(600));
      expect(await entitled(), isTrue,
          reason: 'a partial refund keeps the purchase');
      await commerce.refund(saleId: first.id, refundId: 'r2');
      expect(await entitled(), isTrue,
          reason: 'the second sale still grants it');
      await commerce.refund(saleId: second.id, refundId: 'r3');
      expect(await entitled(), isFalse);
    });

    test('that fails at the gateway leaves nothing half-reversed', () async {
      final DVSale sale = await sell('o1');
      final List<String> stock = <String>['course'];
      gateway.failRefunds = true;
      await expectLater(
        commerce.refund(
          saleId: sale.id,
          refundId: 'r1',
          restock: (DVContext context, DVRefund refund) {
            stock.add('course');
            context.compensate(() => stock.removeLast());
          },
        ),
        throwsStateError,
      );
      expect(stock, <String>['course']);
      expect((await ledger.find('o1'))!.refunded, gbp(0));
      expect((await ledger.find('o1'))!.revokedAt, isNull);
      expect(await entitled(), isTrue);
      expect(codes(), isNot(contains('DV-COMMERCE-004')));

      gateway.failRefunds = false;
      final DVRefund retried =
          await commerce.refund(saleId: sale.id, refundId: 'r1');
      expect(retried.amount, gbp(1200));
      expect(await entitled(), isFalse);
    });

    test('whose compensation fails is reported, not left for somebody to find',
        () async {
      final DVSale sale = await sell('o1');
      gateway.failRefunds = true;
      await expectLater(
        commerce.refund(
          saleId: sale.id,
          refundId: 'r1',
          restock: (DVContext context, DVRefund refund) {
            context.compensate(() => throw StateError('stock system is down'));
          },
        ),
        throwsA(isA<DVRefundIncomplete>()
            .having((DVRefundIncomplete e) => e.refundId, 'refundId', 'r1')),
      );
      final DVLogRecord record = logs.records
          .firstWhere((DVLogRecord r) => r.code == 'DV-COMMERCE-004');
      expect(record.level, DVLogLevel.error);
    });

    test('of a sale that does not exist is an error', () async {
      await expectLater(
        commerce.refund(saleId: 'nope', refundId: 'r1'),
        throwsArgumentError,
      );
    });
  });

  group('a store refund', () {
    const DVPurchaseProduct book = DVPurchaseProduct(
      'book_pro',
      billable: DVBillable.digital(play: 'book_pro'),
      entitlements: <Entitlement>{pro},
    );

    late DateTime clock;
    late DVFakeStoreAdapter play;
    late List<DVPurchaseChange> reversed;
    late DVPurchases purchases;
    late FutureOr<void> Function(DVContext, DVPurchaseChange) reverse;

    DVStoreTransaction bought({DateTime? revokedAt, DateTime? signedAt}) =>
        DVStoreTransaction(
          store: DVStore.play,
          originalTransactionId: 'otx',
          transactionId: 'otx_1',
          storeProductId: 'book_pro',
          purchasedAt: now,
          signedAt: signedAt ?? now,
          expiresAt: now.add(const Duration(hours: 2)),
          revokedAt: revokedAt,
          acknowledged: true,
        );

    Future<void> notify(String id, DVStoreTransaction transaction) async {
      final DVSignedStoreNotification signed = play.sign(DVStoreNotification(
        notificationId: id,
        type: 'TEST',
        signedAt: transaction.signedAt,
        transaction: transaction,
      ));
      await purchases.acceptNotification(DVContext(), DVStore.play,
          body: signed.body, headers: signed.headers);
      await pumpEventQueue();
    }

    setUp(() async {
      clock = now;
      reversed = <DVPurchaseChange>[];
      reverse = (DVContext context, DVPurchaseChange change) {
        reversed.add(change);
      };
      play = DVFakeStoreAdapter(DVStore.play, signingKey: 'k');
      purchases = DVPurchases(
        products: const <DVPurchaseProduct>[book],
        stores: <DVStoreAdapter>[play],
        ledger: DVMemoryPurchaseLedger(),
        clock: () => clock,
        logger: logger,
        onChange: commerce.storeRevocations(
            (DVContext context, DVPurchaseChange change) =>
                reverse(context, change)),
      );
      play.issue('receipt', bought());
      await purchases.verifyPurchase(DVStore.play, 'receipt', customer: alice);
    });

    test('runs the reversal when the store took the purchase back', () async {
      final DateTime at = now.add(const Duration(minutes: 30));
      clock = at;
      await notify('n1', bought(revokedAt: at, signedAt: at));
      expect(reversed, hasLength(1));
      expect(reversed.single.revoked, <String>{'pro'});
      expect(reversed.single.revokedAt, at);
    });

    test('does not run it for a subscription that simply lapsed', () async {
      final DateTime at = now.add(const Duration(hours: 3));
      clock = at;
      await notify('n1', bought(signedAt: at));
      expect(reversed, isEmpty);
    });

    test('reports a reversal whose compensation failed, and still acknowledges',
        () async {
      reverse = (DVContext context, DVPurchaseChange change) {
        context.compensate(() => throw StateError('stock system is down'));
        throw StateError('credit note failed');
      };
      final DateTime at = now.add(const Duration(minutes: 30));
      clock = at;
      await notify('n1', bought(revokedAt: at, signedAt: at));
      expect(codes(), contains('DV-COMMERCE-004'));
    });
  });
}
