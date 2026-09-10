// The price a plan declares is checked against the price the provider will
// charge, before a customer is sent anywhere.
//
// `BillingPlan.priceMinorUnits` and `BillingPlan.currency` were required
// constructor arguments that nothing read. Neither provider looked at them:
// Stripe and Paddle both took `prices[plan.id]`, sent the customer to
// whatever that identifier costs at the provider, and never compared. So a
// pricing page could say 40.00 USD -- the example's does, off the model's
// declared price -- while the checkout charged 49.00 because somebody edited
// it in a dashboard, and nothing in the code was in a position to notice.
// The wrong number is plausible and the checkout still works, which is what
// makes it worth a network round trip to catch.
//
// The check is a lookup before the session, not a comparison afterwards: a
// session created and then refused is an orphan at the provider, and the
// point is that the customer never reaches a checkout at the wrong price.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const BillingPlan pro = BillingPlan(
    id: 'pro', displayName: 'Pro', priceMinorUnits: 4000, currency: 'USD');

/// A plan that declares no price: the provider is the authority on what it
/// costs. Metered plans have no unit price at all.
const BillingPlan metered = BillingPlan(
    id: 'metered', displayName: 'Metered', priceMinorUnits: 0, currency: 'USD');

void main() {
  group('Stripe', () {
    late List<(String, Uri, String?)> calls;

    DVStripeBillingProvider provider(Map<String, (int, String)> responses) {
      calls = <(String, Uri, String?)>[];
      return DVStripeBillingProvider(
        secretKey: 'sk_test_secret',
        webhookSecret: 'whsec_test',
        prices: <String, String>{'pro': 'price_pro', 'metered': 'price_m'},
        entitlements: const <String, Set<Entitlement>>{},
        successUrl: Uri.parse('https://app.example/ok'),
        cancelUrl: Uri.parse('https://app.example/no'),
        fetch: (String method, Uri url, Map<String, String> headers,
            String? body) async {
          calls.add((method, url, body));
          return responses[url.path] ??
              (404, '{"error":{"message":"no such price"}}');
        },
        clock: () => DateTime.utc(2026, 9, 3, 12),
      );
    }

    test('a price that costs more than the plan says stops the checkout',
        () async {
      final DVStripeBillingProvider p = provider(<String, (int, String)>{
        '/v1/prices/price_pro':
            (200, '{"id":"price_pro","unit_amount":4900,"currency":"usd"}'),
        '/v1/checkout/sessions':
            (200, '{"id":"cs_1","url":"https://checkout.stripe.com/c/cs_1"}'),
      });

      await expectLater(
        p.checkout(plan: pro, customer: 'user_7'),
        throwsA(isA<DVBillingError>().having((DVBillingError e) => e.message,
            'message', allOf(contains('40.00 USD'), contains('49.00 USD')))),
      );
      // Nothing was created. A refusal after the POST leaves a session the
      // customer could still be handed.
      expect(calls.map((c) => c.$2.path), <String>['/v1/prices/price_pro']);
    });

    test('a price in another currency stops the checkout', () async {
      final DVStripeBillingProvider p = provider(<String, (int, String)>{
        '/v1/prices/price_pro':
            (200, '{"id":"price_pro","unit_amount":4000,"currency":"eur"}'),
        '/v1/checkout/sessions': (200, '{"id":"cs_1"}'),
      });

      await expectLater(
        p.checkout(plan: pro, customer: 'u'),
        throwsA(isA<DVBillingError>().having((DVBillingError e) => e.message,
            'message', allOf(contains('USD'), contains('EUR')))),
      );
    });

    test('a price that agrees is checked and then charged', () async {
      final DVStripeBillingProvider p = provider(<String, (int, String)>{
        '/v1/prices/price_pro':
            (200, '{"id":"price_pro","unit_amount":4000,"currency":"usd"}'),
        '/v1/checkout/sessions':
            (200, '{"id":"cs_1","url":"https://checkout.stripe.com/c/cs_1"}'),
      });

      final DVBillingCheckoutSession session =
          await p.checkout(plan: pro, customer: 'user_7');

      expect(session.id, 'cs_1');
      expect(calls.map((c) => '${c.$1} ${c.$2.path}'), <String>[
        'GET /v1/prices/price_pro',
        'POST /v1/checkout/sessions',
      ]);
      // The lookup is a read, and a GET that carried a form body would be
      // rejected by Stripe as one.
      expect(calls.first.$3, isNull);
    });

    test('a plan that declares no price is not checked against one', () async {
      final DVStripeBillingProvider p = provider(<String, (int, String)>{
        '/v1/checkout/sessions': (200, '{"id":"cs_2"}'),
      });

      final DVBillingCheckoutSession session =
          await p.checkout(plan: metered, customer: 'u');

      expect(session.id, 'cs_2');
      expect(calls.map((c) => c.$2.path), <String>['/v1/checkout/sessions']);
    });

    test(
        'a tiered price has no single amount, and is refused rather than skipped',
        () async {
      // unit_amount is null for tiered and metered Stripe prices. Treating
      // that as "nothing to compare" would let exactly the mismatch this
      // exists to catch through, so the contradiction is the error: a plan
      // declaring 40.00 is pointed at a price that has no one amount.
      final DVStripeBillingProvider p = provider(<String, (int, String)>{
        '/v1/prices/price_pro': (
          200,
          '{"id":"price_pro","unit_amount":null,"currency":"usd","billing_scheme":"tiered"}'
        ),
        '/v1/checkout/sessions': (200, '{"id":"cs_1"}'),
      });

      await expectLater(
          p.checkout(plan: pro, customer: 'u'), throwsA(isA<DVBillingError>()));
      expect(calls, hasLength(1));
    });

    test('a price identifier the provider does not have stops the checkout',
        () async {
      final DVStripeBillingProvider p = provider(const <String, (int, String)>{});

      await expectLater(
          p.checkout(plan: pro, customer: 'u'), throwsA(isA<DVBillingError>()));
      expect(calls, hasLength(1));
    });
  });

  group('Paddle', () {
    late List<(String, Uri, String?)> calls;

    DVPaddleBillingProvider provider(Map<String, (int, String)> responses) {
      calls = <(String, Uri, String?)>[];
      return DVPaddleBillingProvider(
        apiKey: 'pdl_live_key',
        webhookSecret: 'pdl_ntfset_secret',
        prices: <String, String>{'pro': 'pri_pro', 'metered': 'pri_m'},
        entitlements: const <String, Set<Entitlement>>{},
        fetch: (String method, Uri url, Map<String, String> headers,
            String? body) async {
          calls.add((method, url, body));
          return responses[url.path] ?? (404, '{"error":{"detail":"not found"}}');
        },
        clock: () => DateTime.utc(2026, 9, 3, 12),
      );
    }

    test('a price that costs more than the plan says stops the checkout',
        () async {
      // Paddle sends the amount as a string of minor units.
      final DVPaddleBillingProvider p = provider(<String, (int, String)>{
        '/prices/pri_pro': (
          200,
          '{"data":{"id":"pri_pro","unit_price":{"amount":"4900","currency_code":"USD"}}}'
        ),
        '/transactions': (200, '{"data":{"id":"txn_1"}}'),
      });

      await expectLater(
        p.checkout(plan: pro, customer: 'u'),
        throwsA(isA<DVBillingError>().having((DVBillingError e) => e.message,
            'message', allOf(contains('40.00 USD'), contains('49.00 USD')))),
      );
      expect(calls.map((c) => c.$2.path), <String>['/prices/pri_pro']);
    });

    test('a price that agrees is checked and then charged', () async {
      final DVPaddleBillingProvider p = provider(<String, (int, String)>{
        '/prices/pri_pro': (
          200,
          '{"data":{"id":"pri_pro","unit_price":{"amount":"4000","currency_code":"USD"}}}'
        ),
        '/transactions': (
          200,
          '{"data":{"id":"txn_1","checkout":{"url":"https://pay.paddle.com/txn_1"}}}'
        ),
      });

      final DVBillingCheckoutSession session =
          await p.checkout(plan: pro, customer: 'u');

      expect(session.id, 'txn_1');
      expect(calls.map((c) => '${c.$1} ${c.$2.path}'), <String>[
        'GET /prices/pri_pro',
        'POST /transactions',
      ]);
    });

    test('a plan that declares no price is not checked against one', () async {
      final DVPaddleBillingProvider p = provider(<String, (int, String)>{
        '/transactions': (200, '{"data":{"id":"txn_2"}}'),
      });

      expect((await p.checkout(plan: metered, customer: 'u')).id, 'txn_2');
      expect(calls.map((c) => c.$2.path), <String>['/transactions']);
    });
  });
}
