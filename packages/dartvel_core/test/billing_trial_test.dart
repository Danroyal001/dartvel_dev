// Trials: the free days a plan promises are the free days the provider gives.
//
// "trials" is in the Billing feature list and BillingPlan had nothing to say
// about them. A pricing page reading "14 days free" off a plan while the
// checkout charges on day one is a support ticket; the opposite, a trial
// configured at the provider that nobody declared, is a week given away
// every signup and no ticket at all.
//
// The two providers need different treatment and it is not a style choice.
// Stripe takes the trial with the checkout session, so the plan's number is
// sent. Paddle keeps the trial on the price, so there is nothing to send and
// the only honest reading is to check that the price agrees.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const BillingPlan trialling = BillingPlan(
  id: 'pro',
  displayName: 'Pro',
  priceMinorUnits: 4000,
  currency: 'USD',
  trialDays: 14,
);

const BillingPlan noTrial = BillingPlan(
    id: 'pro', displayName: 'Pro', priceMinorUnits: 4000, currency: 'USD');

void main() {
  group('Stripe', () {
    late List<String?> bodies;

    DVStripeBillingProvider provider() {
      bodies = <String?>[];
      return DVStripeBillingProvider(
        secretKey: 'sk_test',
        webhookSecret: 'whsec_test',
        prices: const <String, String>{'pro': 'price_pro'},
        entitlements: const <String, Set<Entitlement>>{},
        successUrl: Uri.parse('https://app.example/ok'),
        cancelUrl: Uri.parse('https://app.example/no'),
        fetch: (String method, Uri url, Map<String, String> headers,
            String? body) async {
          bodies.add(body);
          if (url.path == '/v1/prices/price_pro') {
            return (
              200,
              '{"id":"price_pro","unit_amount":4000,"currency":"usd"}'
            );
          }
          return (200, '{"id":"cs_1"}');
        },
        clock: () => DateTime.utc(2026, 9, 3, 12),
      );
    }

    test('the declared trial is sent with the session', () async {
      final DVStripeBillingProvider p = provider();

      await p.checkout(plan: trialling, customer: 'u');

      expect(bodies.last,
          contains('subscription_data%5Btrial_period_days%5D=14'));
    });

    test('a plan with no trial sends no trial', () async {
      // Not zero: a Stripe price can carry its own default trial, and
      // sending a zero would silently cancel it. Saying nothing leaves that
      // decision where it was made.
      final DVStripeBillingProvider p = provider();

      await p.checkout(plan: noTrial, customer: 'u');

      expect(bodies.last, isNot(contains('trial_period_days')));
    });
  });

  group('Paddle', () {
    DVPaddleBillingProvider provider(String priceJson) =>
        DVPaddleBillingProvider(
          apiKey: 'pdl_live_key',
          webhookSecret: 's',
          prices: const <String, String>{'pro': 'pri_pro'},
          entitlements: const <String, Set<Entitlement>>{},
          fetch: (String method, Uri url, Map<String, String> h,
              String? b) async {
            if (url.path == '/prices/pri_pro') return (200, priceJson);
            return (200, '{"data":{"id":"txn_1"}}');
          },
          clock: () => DateTime.utc(2026, 9, 3, 12),
        );

    String price({String trial = 'null'}) =>
        '{"data":{"id":"pri_pro","unit_price":{"amount":"4000",'
        '"currency_code":"USD"},"trial_period":$trial}}';

    test('a trial that matches the plan is accepted', () async {
      final DVPaddleBillingProvider p =
          provider(price(trial: '{"interval":"day","frequency":14}'));

      expect((await p.checkout(plan: trialling, customer: 'u')).id, 'txn_1');
    });

    test('a week counted in weeks is still a week', () async {
      final DVPaddleBillingProvider p =
          provider(price(trial: '{"interval":"week","frequency":2}'));

      expect((await p.checkout(plan: trialling, customer: 'u')).id, 'txn_1');
    });

    test('a promised trial the price does not give is refused', () async {
      final DVPaddleBillingProvider p = provider(price());

      await expectLater(
        p.checkout(plan: trialling, customer: 'u'),
        throwsA(isA<DVBillingError>().having((DVBillingError e) => e.message,
            'message', contains('14'))),
      );
    });

    test('a trial nobody declared is refused too', () async {
      // The direction that never generates a complaint: every customer gets
      // a free week the business did not decide to give.
      final DVPaddleBillingProvider p =
          provider(price(trial: '{"interval":"day","frequency":7}'));

      await expectLater(
          p.checkout(plan: noTrial, customer: 'u'),
          throwsA(isA<DVBillingError>()));
    });

    test('a trial measured in months is refused rather than guessed at',
        () async {
      // A month is not a number of days, so a plan that counts days cannot
      // say whether it agrees. Guessing thirty would be wrong eleven months
      // of the year.
      final DVPaddleBillingProvider p =
          provider(price(trial: '{"interval":"month","frequency":1}'));

      await expectLater(
          p.checkout(plan: trialling, customer: 'u'),
          throwsA(isA<DVBillingError>()));
    });
  });

  test('a negative trial is not a trial', () {
    expect(
      () => BillingPlan(
          id: 'x',
          displayName: 'x',
          priceMinorUnits: 1,
          currency: 'USD',
          trialDays: -1),
      throwsA(isA<AssertionError>()),
    );
  });
}
