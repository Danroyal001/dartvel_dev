// Promotions: eligibility decided on the server at charge time, stacking
// declared, and a limit that holds when the requests arrive together.
//
// Discount fraud does not throw. A 20% coupon silently meeting a 30% campaign
// sells at half price to everybody who reads a forum; a coupon limited to a
// hundred uses and checked-then-counted in two steps is redeemed a hundred and
// twenty times by the requests that arrived in the same second; a percentage
// rounded per line gives away a cent the total never agreed to.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVMoney usd(int amount) => DVMoney(amount: amount, currency: 'USD');

DVOrderLine line(String ref, int cents,
        {String product = 'widget', int quantity = 1}) =>
    DVOrderLine(
      reference: ref,
      productId: product,
      unitPrice: usd(cents),
      quantity: quantity,
      category: DVTaxCategory.physicalGood,
    );

class Customer implements DVBillingCustomer {
  const Customer(this.id, {this.eligible = true});
  final String id;
  final bool eligible;

  @override
  String get billingCustomerId => 'customer:$id';
}

/// The policy the specification writes as `@DVPolicy(Coupon) redeem(...)`.
class CouponPolicy implements DVPromotionPolicy {
  final List<String> asked = <String>[];

  @override
  FutureOr<bool> redeem(Object customer, DVPromotion promotion) {
    asked.add(promotion.id);
    return (customer as Customer).eligible;
  }
}

const Customer alice = Customer('alice');
const Customer bob = Customer('bob');

final DateTime now = DateTime.utc(2026, 9, 14, 12);

const DVPromotion coupon20 = DVPromotion(
  id: 'coupon20',
  code: 'SAVE20',
  discount: DVDiscount.percent(20),
  stacking: DVPromotionStacking.group('coupons'),
);
const DVPromotion coupon15 = DVPromotion(
  id: 'coupon15',
  code: 'SAVE15',
  discount: DVDiscount.percent(15),
  stacking: DVPromotionStacking.group('coupons'),
);
const DVPromotion campaign30 = DVPromotion(
  id: 'campaign30',
  discount: DVDiscount.percent(30),
  stacking: DVPromotionStacking.group('campaigns'),
);
const DVPromotion flash50 = DVPromotion(
  id: 'flash50',
  code: 'FLASH',
  discount: DVDiscount.percent(50),
  stacking: DVPromotionStacking.exclusive(),
);
const DVPromotion flash10 = DVPromotion(
  id: 'flash10',
  code: 'TINY',
  discount: DVDiscount.percent(10),
  stacking: DVPromotionStacking.exclusive(),
);

void main() {
  late DVMemoryLogSink logs;
  late CouponPolicy policy;

  List<String> codes() =>
      logs.records.map((DVLogRecord r) => r.code).whereType<String>().toList();

  setUp(() {
    logs = DVMemoryLogSink();
    policy = CouponPolicy();
  });

  DVPromotions promotions(
    List<DVPromotion> declared, {
    DVPromotionLedger? ledger,
  }) =>
      DVPromotions(
        promotions: declared,
        policy: policy,
        ledger: ledger ?? DVMemoryPromotionLedger(),
        clock: () => now,
        logger: DVLogger(sinks: <DVLogSink>[logs]),
      );

  Map<String, DVRefusedPromotion> refusedById(DVPromotionResolution r) =>
      <String, DVRefusedPromotion>{
        for (final DVRefusedPromotion x in r.refused) x.promotionId ?? x.code!: x,
      };

  group('amounts', () {
    test('a percentage rounds once on the total and allocates exactly', () async {
      const DVPromotion ten = DVPromotion(
        id: 'ten',
        code: 'TEN',
        discount: DVDiscount.percent(10),
        stacking: DVPromotionStacking.group('coupons'),
      );
      // 10% of 9.99 is 99.9 cents: 100 on the total, 33 + 33 + 33 per line.
      final DVPromotionResolution r = await promotions(<DVPromotion>[ten])
          .resolve(
              customer: alice,
              lines: <DVOrderLine>[line('a', 333), line('b', 333), line('c', 333)],
              codes: <String>['TEN']);
      expect(r.discount, usd(100));
      expect(r.total, usd(899));
      expect(<int>[
        for (final String ref in <String>['a', 'b', 'c'])
          r.discountFor(ref).amount,
      ], <int>[34, 33, 33]);
    });

    test('a fixed amount is allocated in proportion and capped at the order',
        () async {
      final DVPromotion off = DVPromotion(
        id: 'off',
        code: 'OFF',
        discount: DVDiscount.fixed(usd(100)),
        stacking: const DVPromotionStacking.group('coupons'),
      );
      final DVPromotionResolution r = await promotions(<DVPromotion>[off])
          .resolve(
              customer: alice,
              lines: <DVOrderLine>[line('a', 100), line('b', 200)],
              codes: <String>['OFF']);
      expect(r.discountFor('a'), usd(33));
      expect(r.discountFor('b'), usd(67));

      final DVPromotion huge = DVPromotion(
        id: 'huge',
        code: 'HUGE',
        discount: DVDiscount.fixed(usd(5000)),
        stacking: const DVPromotionStacking.group('coupons'),
      );
      final DVPromotionResolution capped = await promotions(<DVPromotion>[huge])
          .resolve(
              customer: alice,
              lines: <DVOrderLine>[line('a', 100), line('b', 300)],
              codes: <String>['HUGE']);
      expect(capped.discount, usd(400));
      expect(capped.total, usd(0));
    });

    test('a fixed amount in another currency does not apply', () async {
      final DVPromotion euros = DVPromotion(
        id: 'euros',
        code: 'EUR5',
        discount: DVDiscount.fixed(DVMoney(amount: 500, currency: 'EUR')),
        stacking: const DVPromotionStacking.group('coupons'),
      );
      final DVPromotionResolution r = await promotions(<DVPromotion>[euros])
          .resolve(
              customer: alice,
              lines: <DVOrderLine>[line('a', 1000)],
              codes: <String>['EUR5']);
      expect(r.discount, usd(0));
      expect(refusedById(r)['euros']!.reason, DVPromotionRefusal.notApplicable);
    });

    test('a product-scoped promotion discounts only its products', () async {
      const DVPromotion books = DVPromotion(
        id: 'books',
        code: 'BOOKS',
        discount: DVDiscount.percent(50),
        stacking: DVPromotionStacking.group('coupons'),
        products: <String>{'book'},
      );
      final DVPromotionResolution r = await promotions(<DVPromotion>[books])
          .resolve(customer: alice, lines: <DVOrderLine>[
        line('a', 1000, product: 'book'),
        line('b', 1000, product: 'pen'),
      ], codes: <String>[
        'BOOKS'
      ]);
      expect(r.discountFor('a'), usd(500));
      expect(r.discountFor('b'), usd(0));

      final DVPromotionResolution none = await promotions(<DVPromotion>[books])
          .resolve(
              customer: alice,
              lines: <DVOrderLine>[line('b', 1000, product: 'pen')],
              codes: <String>['BOOKS']);
      expect(refusedById(none)['books']!.reason,
          DVPromotionRefusal.notApplicable);
    });

    test('allocations always sum to the discount', () async {
      const DVPromotion odd = DVPromotion(
        id: 'odd',
        code: 'ODD',
        discount: DVDiscount.basisPoints(1337),
        stacking: DVPromotionStacking.group('a'),
      );
      final DVPromotion fixed = DVPromotion(
        id: 'fixed',
        discount: DVDiscount.fixed(usd(777)),
        stacking: const DVPromotionStacking.group('b'),
      );
      final DVPromotions subject = promotions(<DVPromotion>[odd, fixed]);
      for (int seed = 1; seed < 150; seed++) {
        final List<DVOrderLine> lines = <DVOrderLine>[
          for (int i = 0; i < 1 + seed % 6; i++)
            line('l$i', 1 + (seed * 7919 + i * 104729) % 5003,
                quantity: 1 + i % 3),
        ];
        final DVPromotionResolution r = await subject.resolve(
            customer: alice, lines: lines, codes: <String>['ODD']);
        final int allocated = lines.fold<int>(
            0, (int s, DVOrderLine l) => s + r.discountFor(l.reference).amount);
        expect(allocated, r.discount.amount, reason: 'seed $seed');
        expect(
          r.applied.fold<int>(0, (int s, DVAppliedPromotion a) => s + a.amount.amount),
          r.discount.amount,
          reason: 'seed $seed',
        );
        for (final DVOrderLine l in lines) {
          expect(r.discountFor(l.reference).amount,
              lessThanOrEqualTo(l.amount.amount));
        }
      }
    });
  });

  group('stacking', () {
    test('promotions in different groups combine, each on what is left',
        () async {
      // The campaign applies automatically; the coupon is typed. 30% of
      // 100.00 is 30.00, and 20% of the 70.00 left is 14.00: 44.00, not the
      // 50.00 that adding the percentages gives.
      final DVPromotionResolution r =
          await promotions(<DVPromotion>[coupon20, campaign30]).resolve(
              customer: alice,
              lines: <DVOrderLine>[line('a', 10000)],
              codes: <String>['SAVE20']);
      expect(r.applied.map((DVAppliedPromotion a) => a.promotion.id),
          <String>['campaign30', 'coupon20']);
      expect(r.discount, usd(4400));
    });

    test('at most one promotion applies from each group', () async {
      final DVPromotionResolution r =
          await promotions(<DVPromotion>[coupon20, coupon15]).resolve(
              customer: alice,
              lines: <DVOrderLine>[line('a', 10000)],
              codes: <String>['SAVE15', 'SAVE20']);
      expect(r.applied.map((DVAppliedPromotion a) => a.promotion.id),
          <String>['coupon20']);
      expect(r.discount, usd(2000));
      expect(refusedById(r)['coupon15']!.reason, DVPromotionRefusal.notStacked);
    });

    test('an exclusive promotion combines with nothing', () async {
      final DVPromotions subject =
          promotions(<DVPromotion>[coupon20, campaign30, flash50, flash10]);
      final DVPromotionResolution big = await subject.resolve(
          customer: alice,
          lines: <DVOrderLine>[line('a', 10000)],
          codes: <String>['SAVE20', 'FLASH']);
      expect(big.applied.map((DVAppliedPromotion a) => a.promotion.id),
          <String>['flash50']);
      expect(big.discount, usd(5000));
      expect(refusedById(big)['coupon20']!.reason, DVPromotionRefusal.notStacked);
      expect(
          refusedById(big)['campaign30']!.reason, DVPromotionRefusal.notStacked);

      final DVPromotionResolution small = await subject.resolve(
          customer: alice,
          lines: <DVOrderLine>[line('a', 10000)],
          codes: <String>['SAVE20', 'TINY']);
      expect(small.applied.map((DVAppliedPromotion a) => a.promotion.id),
          <String>['campaign30', 'coupon20']);
      expect(refusedById(small)['flash10']!.reason, DVPromotionRefusal.notStacked);
    });

    test('a code typed twice is applied once', () async {
      final DVPromotionResolution r = await promotions(<DVPromotion>[coupon20])
          .resolve(
              customer: alice,
              lines: <DVOrderLine>[line('a', 10000)],
              codes: <String>['SAVE20', 'save20']);
      expect(r.discount, usd(2000));
      expect(r.refused.single.reason, DVPromotionRefusal.duplicate);
    });

    test('an unknown code is refused, not an error', () async {
      final DVPromotionResolution r = await promotions(<DVPromotion>[coupon20])
          .resolve(
              customer: alice,
              lines: <DVOrderLine>[line('a', 10000)],
              codes: <String>['NOPE']);
      expect(r.discount, usd(0));
      expect(r.refused.single.reason, DVPromotionRefusal.unknown);
      expect(r.refused.single.code, 'NOPE');
    });

    test('a promotion must declare how it stacks', () {
      expect(
        () => DVPromotions(
          promotions: const <DVPromotion>[coupon20, coupon20],
          policy: policy,
          ledger: DVMemoryPromotionLedger(),
        ),
        throwsArgumentError,
      );
      expect(
        () => DVPromotions(
          promotions: const <DVPromotion>[
            coupon20,
            DVPromotion(
              id: 'other',
              code: 'save20',
              discount: DVDiscount.percent(5),
              stacking: DVPromotionStacking.group('coupons'),
            ),
          ],
          policy: policy,
          ledger: DVMemoryPromotionLedger(),
        ),
        throwsArgumentError,
      );
      expect(() => const DVDiscount.percent(0).validate(), throwsArgumentError);
      expect(() => const DVDiscount.basisPoints(10001).validate(), throwsArgumentError);
    });
  });

  group('eligibility', () {
    test('the policy decides, on the server, and a refusal is DV-COMMERCE-003',
        () async {
      final DVPromotionResolution r =
          await promotions(<DVPromotion>[coupon20]).resolve(
              customer: const Customer('mallory', eligible: false),
              lines: <DVOrderLine>[line('a', 10000)],
              codes: <String>['SAVE20']);
      expect(r.discount, usd(0));
      expect(r.refused.single.reason, DVPromotionRefusal.ineligible);
      expect(policy.asked, <String>['coupon20']);
      expect(codes(), <String>['DV-COMMERCE-003']);
      expect(logs.records.single.level, DVLogLevel.info);
    });

    test('a promotion outside its window is not live', () async {
      final DVPromotionResolution r = await promotions(<DVPromotion>[
        DVPromotion(
          id: 'early',
          code: 'EARLY',
          discount: const DVDiscount.percent(10),
          stacking: const DVPromotionStacking.group('a'),
          startsAt: now.add(const Duration(seconds: 1)),
        ),
        DVPromotion(
          id: 'late',
          code: 'LATE',
          discount: const DVDiscount.percent(10),
          stacking: const DVPromotionStacking.group('b'),
          endsAt: now,
        ),
      ]).resolve(
          customer: alice,
          lines: <DVOrderLine>[line('a', 10000)],
          codes: <String>['EARLY', 'LATE']);
      expect(r.discount, usd(0));
      expect(r.refused.map((DVRefusedPromotion x) => x.reason),
          everyElement(DVPromotionRefusal.notLive));
      expect(policy.asked, isEmpty);
    });

    test('a minimum order is checked against the order before discounts',
        () async {
      final DVPromotion minimum = DVPromotion(
        id: 'min',
        code: 'MIN',
        discount: const DVDiscount.percent(10),
        stacking: const DVPromotionStacking.group('coupons'),
        minimumSubtotal: usd(5000),
      );
      final DVPromotions subject = promotions(<DVPromotion>[minimum]);
      final DVPromotionResolution below = await subject.resolve(
          customer: alice,
          lines: <DVOrderLine>[line('a', 4999)],
          codes: <String>['MIN']);
      expect(below.refused.single.reason, DVPromotionRefusal.belowMinimum);
      final DVPromotionResolution at = await subject.resolve(
          customer: alice,
          lines: <DVOrderLine>[line('a', 5000)],
          codes: <String>['MIN']);
      expect(at.discount, usd(500));
    });
  });

  for (final (String name, DVPromotionLedger Function() open)
      in <(String, DVPromotionLedger Function())>[
    ('memory ledger', DVMemoryPromotionLedger.new),
    (
      'database ledger on sqlite',
      () => DVDatabasePromotionLedger(SqliteDVDatabaseAdapter.memory())
    ),
  ]) {
    group('redemption on the $name', () {
      const DVPromotion limited = DVPromotion(
        id: 'limited',
        code: 'LIMITED',
        discount: DVDiscount.percent(10),
        stacking: DVPromotionStacking.group('coupons'),
        maxRedemptions: 5,
      );
      const DVPromotion once = DVPromotion(
        id: 'once',
        code: 'ONCE',
        discount: DVDiscount.percent(10),
        stacking: DVPromotionStacking.group('coupons'),
        maxRedemptionsPerCustomer: 1,
      );

      late DVPromotionLedger ledger;
      setUp(() => ledger = open());

      Future<DVPromotionResolution> charge(
        DVPromotions subject, {
        required Object customer,
        required String orderId,
        required String code,
        bool failAfter = false,
      }) =>
          DVTransactionRunner().call((DVContext context) async {
            final DVPromotionResolution r = await subject.redeem(
              context,
              customer: customer,
              lines: <DVOrderLine>[line('a', 10000)],
              codes: <String>[code],
              orderId: orderId,
            );
            if (failAfter) throw StateError('the capture failed');
            return r;
          });

      test('a limit holds when every request arrives at once', () async {
        final DVPromotions subject =
            promotions(<DVPromotion>[limited], ledger: ledger);
        final List<Object> outcomes = await Future.wait(<Future<Object>>[
          for (int i = 0; i < 20; i++)
            charge(subject,
                    customer: Customer('c$i'), orderId: 'o$i', code: 'LIMITED')
                .then<Object>((DVPromotionResolution r) => r)
                .catchError((Object e) => e),
        ]);
        expect(outcomes.whereType<DVPromotionResolution>(), hasLength(5));
        expect(
          outcomes.whereType<DVPromotionUnavailable>().map(
              (DVPromotionUnavailable e) => e.reason),
          everyElement(DVPromotionRefusal.limitReached),
        );
        expect(outcomes.whereType<DVPromotionUnavailable>(), hasLength(15));
        expect(await ledger.redeemed('limited'), 5);

        // And the limit is visible before a charge is attempted.
        final DVPromotionResolution r = await subject.resolve(
            customer: const Customer('late'),
            lines: <DVOrderLine>[line('a', 10000)],
            codes: <String>['LIMITED']);
        expect(r.refused.single.reason, DVPromotionRefusal.limitReached);
      });

      test('a per-customer limit holds under concurrency too', () async {
        final DVPromotions subject =
            promotions(<DVPromotion>[once], ledger: ledger);
        final List<Object> outcomes = await Future.wait(<Future<Object>>[
          for (int i = 0; i < 10; i++)
            charge(subject, customer: alice, orderId: 'o$i', code: 'ONCE')
                .then<Object>((DVPromotionResolution r) => r)
                .catchError((Object e) => e),
        ]);
        expect(outcomes.whereType<DVPromotionResolution>(), hasLength(1));
        expect(
          outcomes.whereType<DVPromotionUnavailable>().map(
              (DVPromotionUnavailable e) => e.reason),
          everyElement(DVPromotionRefusal.customerLimitReached),
        );
        expect(await ledger.redeemedBy('once', 'customer:alice'), 1);
        await charge(subject, customer: bob, orderId: 'bob1', code: 'ONCE');
        expect(await ledger.redeemed('once'), 2);
      });

      test('the same order redeemed twice counts once', () async {
        final DVPromotions subject =
            promotions(<DVPromotion>[limited], ledger: ledger);
        await charge(subject, customer: alice, orderId: 'o1', code: 'LIMITED');
        await charge(subject, customer: alice, orderId: 'o1', code: 'LIMITED');
        expect(await ledger.redeemed('limited'), 1);
      });

      test('a charge that fails gives the redemption back', () async {
        final DVPromotions subject =
            promotions(<DVPromotion>[limited, once], ledger: ledger);
        await expectLater(
          charge(subject,
              customer: alice, orderId: 'o1', code: 'LIMITED', failAfter: true),
          throwsStateError,
        );
        expect(await ledger.redeemed('limited'), 0);
        await expectLater(
          charge(subject,
              customer: alice, orderId: 'o2', code: 'ONCE', failAfter: true),
          throwsStateError,
        );
        expect(await ledger.redeemedBy('once', 'customer:alice'), 0);
        await charge(subject, customer: alice, orderId: 'o3', code: 'ONCE');
        expect(await ledger.redeemedBy('once', 'customer:alice'), 1);
      });

      test('an unlimited promotion is still counted', () async {
        final DVPromotions subject =
            promotions(<DVPromotion>[coupon20], ledger: ledger);
        await charge(subject, customer: alice, orderId: 'o1', code: 'SAVE20');
        await charge(subject, customer: bob, orderId: 'o2', code: 'SAVE20');
        expect(await ledger.redeemed('coupon20'), 2);
        expect(await ledger.redeemedBy('coupon20', 'customer:bob'), 1);
      });
    });
  }
}
