// Bachs as a billing provider: checkout sessions, signed webhooks,
// subscriptions and the customer portal.
//
// Bachs (bachs.io) is the payments and billing service Lagos Life took
// payments through before 6 October 2026, per its own terms and privacy
// pages. It looks like Stripe from a distance and differs in every detail a
// copied integration gets wrong: money is a decimal string rather than minor
// units, objects come back unwrapped, a subscription is created only by
// completing a checkout, and the webhook signature is HMAC-SHA256 over
// "<t>.<raw body>" carried as `X-Bachs-Signature-V2: t=<unix>,v1=<hex>`, with
// one v1 per live secret during a rotation.
//
// Every response here is a recorded shape from the Bachs API reference
// (docs.bachs.io, OpenAPI 1.0.0); nothing talks to Bachs.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const BillingPlan team = BillingPlan(
    id: 'team', displayName: 'Team', priceMinorUnits: 4900, currency: 'USD');
const BillingPlan business = BillingPlan(
    id: 'business',
    displayName: 'Business',
    priceMinorUnits: 9900,
    currency: 'USD');
const BillingPlan lifetime = BillingPlan(
    id: 'lifetime',
    displayName: 'Lifetime',
    priceMinorUnits: 2500000,
    currency: 'NGN');

const Entitlement reports = Entitlement('reports');
const Entitlement exports = Entitlement('exports');

const String secret = 'whsec_bachs_signing_secret';
const String apiKey = 'sk_live_bachs_apikey_0123456789';

final DateTime now = DateTime.utc(2026, 10, 9, 12);
int get nowSeconds => now.millisecondsSinceEpoch ~/ 1000;

String sign(String payload, int t, {List<String> secrets = const <String>[secret]}) {
  final List<String> parts = <String>['t=$t'];
  for (final String key in secrets) {
    parts.add('v1=${Hmac(sha256, utf8.encode(key)).convert(utf8.encode('$t.$payload'))}');
  }
  return parts.join(',');
}

String product(String id, String amount, String currency,
        {Map<String, Object?>? trial}) =>
    jsonEncode(<String, Object?>{
      'id': id,
      'name': id,
      'status': 'active',
      'price': <String, Object?>{
        'currency': currency,
        'price_type': 'fixed',
        'amount': amount,
      },
      'billing_cycle': <String, Object?>{'interval': 'month', 'frequency': 1},
      'trial_period': trial,
    });

String subscriptionEvent({
  required String type,
  required String status,
  String customer = 'cust_1',
  String productId = 'prod_team',
  String subscription = 'sub_1',
  String createdAt = '2026-10-09T11:59:00.000000+00:00',
}) =>
    jsonEncode(<String, Object?>{
      'id': 'evt_${type}_$status',
      'type': type,
      'created_at': createdAt,
      'organization_id': 'acct_1',
      'data': <String, Object?>{
        'subscription_id': subscription,
        'customer': <String, Object?>{
          'customer_id': customer,
          'email': 'ada@example.com',
        },
        'product_id': productId,
        'status': status,
        'currency': 'USD',
        'amount': '49.00',
        'cancel_at_period_end': false,
        'items': <Object?>[],
      },
    });

typedef Sent = (String method, Uri url, Map<String, String> headers, String? body);

void main() {
  late List<Sent> sent;

  DVBachsBillingProvider provider({
    Map<String, (int, String)> responses = const <String, (int, String)>{},
    String key = apiKey,
  }) {
    sent = <Sent>[];
    final Map<String, (int, String)> answers = <String, (int, String)>{
      'GET /v1/products/prod_team': (200, product('prod_team', '49.00', 'USD')),
      'GET /v1/products/prod_business':
          (200, product('prod_business', '99.00', 'USD')),
      'GET /v1/products/prod_lifetime':
          (200, product('prod_lifetime', '25000.00', 'NGN')),
      ...responses,
    };
    return DVBachsBillingProvider(
      secretKey: key,
      webhookSecret: secret,
      products: const <String, String>{
        'team': 'prod_team',
        'business': 'prod_business',
        'lifetime': 'prod_lifetime',
      },
      entitlements: <String, Set<Entitlement>>{
        'prod_team': <Entitlement>{reports},
        'prod_business': <Entitlement>{reports, exports},
        'prod_lifetime': <Entitlement>{exports},
      },
      successUrl: Uri.parse('https://example.com/billing/done'),
      cancelUrl: Uri.parse('https://example.com/pricing'),
      fetch: (String method, Uri url, Map<String, String> headers,
          String? body) async {
        sent.add((method, url, headers, body));
        return answers['$method ${url.path}'] ??
            (404, '{"detail":"Not found","error_code":"NOT_FOUND"}');
      },
      clock: () => now,
    );
  }

  group('checkout', () {
    test('creates a checkout session for the plan product, as the customer',
        () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'POST /v1/checkout-sessions': (
          201,
          '{"checkout_id":"chk_1","checkout_url":"https://pay.bachs.io/c/chk_1",'
              '"status":"open","expires_at":"2026-10-09T13:00:00Z",'
              '"created_at":"2026-10-09T12:00:00Z","reference":null}'
        ),
      });

      final DVBillingCheckoutSession session =
          await bachs.checkout(plan: team, customer: 'cust_1');

      expect(session.id, 'chk_1');
      expect(session.checkoutUrl, Uri.parse('https://pay.bachs.io/c/chk_1'));
      final Sent create = sent.last;
      expect(create.$1, 'POST');
      expect(create.$2.host, 'api.bachs.io');
      expect(create.$2.path, '/v1/checkout-sessions');
      expect(create.$3['Authorization'], 'Bearer $apiKey');
      // A retried create must not open a second checkout.
      expect(create.$3['Idempotency-Key'], isNotEmpty);
      final Map<String, Object?> body =
          (jsonDecode(create.$4!) as Map<Object?, Object?>).cast<String, Object?>();
      expect(body['product_cart'], <Object?>[
        <String, Object?>{'product_id': 'prod_team', 'quantity': 1},
      ]);
      // A recurring checkout needs a customer record, so the key is one.
      expect(body['customer'], <String, Object?>{'customer_id': 'cust_1'});
      expect(body['success_url'], 'https://example.com/billing/done');
      expect(body['cancel_url'], 'https://example.com/pricing');
      expect((body['metadata'] as Map<Object?, Object?>)['dartvel_plan'], 'team');
    });

    test('a sandbox key talks to the sandbox host, decided by the key',
        () async {
      final DVBachsBillingProvider bachs = provider(
        key: 'sk_sandbox_abc',
        responses: <String, (int, String)>{
          'POST /v1/checkout-sessions':
              (201, '{"checkout_id":"chk_2","checkout_url":"https://x/y"}'),
        },
      );
      await bachs.checkout(plan: team, customer: 'cust_1');
      expect(sent.map((Sent s) => s.$2.host).toSet(),
          <String>{'sandbox-api.bachs.io'});
    });

    test('reads the decimal-string price and refuses one that disagrees',
        () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'GET /v1/products/prod_team':
            (200, product('prod_team', '59.00', 'USD')),
      });
      await expectLater(
        bachs.checkout(plan: team, customer: 'cust_1'),
        throwsA(isA<DVBillingError>().having((DVBillingError e) => e.message,
            'message', allOf(contains('49.00 USD'), contains('59.00 USD')))),
      );
      expect(sent.where((Sent s) => s.$1 == 'POST'), isEmpty);
    });

    test('a currency with no minor unit is compared in whole units', () async {
      const BillingPlan yen = BillingPlan(
          id: 'team', displayName: 'Team', priceMinorUnits: 4900, currency: 'JPY');
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'GET /v1/products/prod_team': (200, product('prod_team', '4900', 'JPY')),
        'POST /v1/checkout-sessions':
            (201, '{"checkout_id":"chk_3","checkout_url":"https://x/y"}'),
      });
      final DVBillingCheckoutSession session =
          await bachs.checkout(plan: yen, customer: 'cust_1');
      expect(session.id, 'chk_3');
    });

    test('an amount with more decimals than the currency has is refused',
        () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'GET /v1/products/prod_team':
            (200, product('prod_team', '49.005', 'USD')),
      });
      await expectLater(bachs.checkout(plan: team, customer: 'cust_1'),
          throwsA(isA<DVBillingError>()));
    });

    test('a trial the product gives and the plan does not declare is refused',
        () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'GET /v1/products/prod_team': (
          200,
          product('prod_team', '49.00', 'USD',
              trial: <String, Object?>{'interval': 'week', 'frequency': 1})
        ),
      });
      await expectLater(
        bachs.checkout(plan: team, customer: 'cust_1'),
        throwsA(isA<DVBillingError>().having(
            (DVBillingError e) => e.message, 'message', contains('7'))),
      );
    });

    test('a plan with no product configured is refused before any request',
        () async {
      final DVBachsBillingProvider bachs = provider();
      await expectLater(
        bachs.checkout(
            plan: const BillingPlan(
                id: 'ghost', displayName: 'G', priceMinorUnits: 0, currency: 'USD'),
            customer: 'cust_1'),
        throwsA(isA<DVBillingError>()),
      );
      expect(sent, isEmpty);
    });

    test('a refused key is reported without echoing it', () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'GET /v1/products/prod_team':
            (401, '{"detail":"Invalid key $apiKey","error_code":"UNAUTHORIZED"}'),
      });
      await expectLater(
        bachs.checkout(plan: team, customer: 'cust_1'),
        throwsA(isA<DVBillingError>().having(
            (DVBillingError e) => e.message, 'message', isNot(contains(apiKey)))),
      );
    });

    test('an error detail that quotes the key has it struck out', () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'POST /v1/checkout-sessions':
            (400, '{"detail":"bad request for $apiKey","error_code":"VALIDATION_ERROR"}'),
      });
      await expectLater(
        bachs.checkout(plan: team, customer: 'cust_1'),
        throwsA(isA<DVBillingError>().having((DVBillingError e) => e.message,
            'message', allOf(isNot(contains(apiKey)), contains('[key]')))),
      );
    });
  });

  group('verifying a checkout', () {
    test('reads the session back and reports paid only on a succeeded payment',
        () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'GET /v1/checkout-sessions/chk_1': (
          200,
          jsonEncode(<String, Object?>{
            'checkout_id': 'chk_1',
            'status': 'completed',
            'payment_status': 'succeeded',
            'amount': '25000.00',
            'currency': 'NGN',
            'customer': <String, Object?>{'customer_id': 'cust_1'},
            'metadata': <String, Object?>{'dartvel_plan': 'lifetime'},
          })
        ),
        'GET /v1/checkout-sessions/chk_2': (
          200,
          jsonEncode(<String, Object?>{
            'checkout_id': 'chk_2',
            'status': 'open',
            'payment_status': 'processing',
            'amount': '49.00',
            'currency': 'USD',
            'customer': null,
          })
        ),
      });

      final DVBachsCheckout paid = await bachs.verifyCheckout('chk_1');
      expect(paid.paid, isTrue);
      expect(paid.amount, DVMoney(amount: 2500000, currency: 'NGN'));
      expect(paid.customer, 'cust_1');
      expect(paid.plan, 'lifetime');

      final DVBachsCheckout open = await bachs.verifyCheckout('chk_2');
      expect(open.paid, isFalse);
      expect(open.status, 'open');
    });
  });

  group('webhooks', () {
    test('a signed subscription.created grants the product entitlements',
        () async {
      final DVBachsBillingProvider bachs = provider();
      final String payload = subscriptionEvent(
          type: 'customer.subscription.created', status: 'active');

      final DVBillingWebhookResult result =
          await bachs.handleWebhook(payload, sign(payload, nowSeconds));

      expect(result.handled, isTrue);
      expect(result.customer, 'cust_1');
      expect(result.granted, <Entitlement>{reports});
      expect(await bachs.hasEntitlement('cust_1', reports), isTrue);
    });

    test('the signature header is X-Bachs-Signature-V2', () {
      expect(provider().signatureHeaderName, 'X-Bachs-Signature-V2');
    });

    test('during a secret rotation any listed v1 may match', () async {
      final DVBachsBillingProvider bachs = provider();
      final String payload = subscriptionEvent(
          type: 'customer.subscription.created', status: 'trialing');
      final DVBillingWebhookResult result = await bachs.handleWebhook(
          payload,
          sign(payload, nowSeconds,
              secrets: <String>['whsec_old_secret_value', secret]));
      expect(result.handled, isTrue);
    });

    test('a forged signature changes nothing', () async {
      final DVBachsBillingProvider bachs = provider();
      final String payload = subscriptionEvent(
          type: 'customer.subscription.created', status: 'active');
      await expectLater(
          bachs.handleWebhook(payload,
              sign(payload, nowSeconds, secrets: <String>['whsec_wrong'])),
          throwsA(isA<DVBillingError>()));
      expect(await bachs.hasEntitlement('cust_1', reports), isFalse);
    });

    test('a body changed after signing is refused', () async {
      final DVBachsBillingProvider bachs = provider();
      final String payload = subscriptionEvent(
          type: 'customer.subscription.created', status: 'active');
      final String header = sign(payload, nowSeconds);
      final String tampered = payload.replaceFirst('cust_1', 'cust_2');
      await expectLater(bachs.handleWebhook(tampered, header),
          throwsA(isA<DVBillingError>()));
    });

    test('a signature older than the tolerance is a replay', () async {
      final DVBachsBillingProvider bachs = provider();
      final String payload = subscriptionEvent(
          type: 'customer.subscription.created', status: 'active');
      await expectLater(
          bachs.handleWebhook(payload, sign(payload, nowSeconds - 301)),
          throwsA(isA<DVBillingError>()));
    });

    test('Stripe and Paddle shaped headers are not Bachs signatures', () async {
      final DVBachsBillingProvider bachs = provider();
      final String payload = subscriptionEvent(
          type: 'customer.subscription.created', status: 'active');
      final String digest = Hmac(sha256, utf8.encode(secret))
          .convert(utf8.encode('$nowSeconds.$payload'))
          .toString();
      for (final String header in <String>[
        't=$nowSeconds,v0=$digest',
        'ts=$nowSeconds;h1=$digest',
        digest,
      ]) {
        await expectLater(bachs.handleWebhook(payload, header),
            throwsA(isA<DVBillingError>()), reason: header);
      }
    });

    test('a cancellation revokes, and a stale active behind it does not '
        'hand the plan back', () async {
      final DVBachsBillingProvider bachs = provider();
      final String active = subscriptionEvent(
          type: 'customer.subscription.created',
          status: 'active',
          createdAt: '2026-10-09T11:00:00Z');
      final String canceled = subscriptionEvent(
          type: 'customer.subscription.deleted',
          status: 'canceled',
          createdAt: '2026-10-09T11:30:00Z');
      final String retried = subscriptionEvent(
          type: 'customer.subscription.updated',
          status: 'active',
          createdAt: '2026-10-09T11:10:00Z');

      await bachs.handleWebhook(active, sign(active, nowSeconds));
      final DVBillingWebhookResult revoked =
          await bachs.handleWebhook(canceled, sign(canceled, nowSeconds));
      expect(revoked.revoked, <Entitlement>{reports});
      final DVBillingWebhookResult stale =
          await bachs.handleWebhook(retried, sign(retried, nowSeconds));

      expect(stale.stale, isTrue);
      expect(stale.handled, isFalse);
      expect(await bachs.hasEntitlement('cust_1', reports), isFalse);
    });

    test('a plan change takes away what only the old plan gave', () async {
      final DVBachsBillingProvider bachs = provider();
      final String onBusiness = subscriptionEvent(
          type: 'customer.subscription.created',
          status: 'active',
          productId: 'prod_business',
          createdAt: '2026-10-09T11:00:00Z');
      final String downgraded = subscriptionEvent(
          type: 'customer.subscription.updated',
          status: 'active',
          productId: 'prod_team',
          createdAt: '2026-10-09T11:05:00Z');

      await bachs.handleWebhook(onBusiness, sign(onBusiness, nowSeconds));
      expect(await bachs.hasEntitlement('cust_1', exports), isTrue);
      final DVBillingWebhookResult result =
          await bachs.handleWebhook(downgraded, sign(downgraded, nowSeconds));

      expect(result.revoked, <Entitlement>{exports});
      expect(await bachs.hasEntitlement('cust_1', reports), isTrue);
      expect(await bachs.hasEntitlement('cust_1', exports), isFalse);
    });

    test('past_due keeps access until Bachs decides; unpaid and paused end it',
        () async {
      final DVBachsBillingProvider bachs = provider();
      Future<void> deliver(String status, String at) async {
        final String payload = subscriptionEvent(
            type: 'customer.subscription.updated', status: status, createdAt: at);
        await bachs.handleWebhook(payload, sign(payload, nowSeconds));
      }

      await deliver('active', '2026-10-09T10:00:00Z');
      await deliver('past_due', '2026-10-09T10:01:00Z');
      expect(await bachs.hasEntitlement('cust_1', reports), isTrue);
      await deliver('unpaid', '2026-10-09T10:02:00Z');
      expect(await bachs.hasEntitlement('cust_1', reports), isFalse);
      await deliver('active', '2026-10-09T10:03:00Z');
      await deliver('paused', '2026-10-09T10:04:00Z');
      expect(await bachs.hasEntitlement('cust_1', reports), isFalse);
    });

    test('a paid one-time checkout grants what its plan product gives',
        () async {
      final DVBachsBillingProvider bachs = provider();
      String completed(String paymentStatus) => jsonEncode(<String, Object?>{
            'id': 'evt_chk',
            'type': 'checkout.completed',
            'created_at': '2026-10-09T11:59:00Z',
            'data': <String, Object?>{
              'checkout_id': 'chk_9',
              'status': 'completed',
              'mode': 'payment',
              'payment_status': paymentStatus,
              'amount': '25000.00',
              'currency': 'NGN',
              'customer': <String, Object?>{'customer_id': 'cust_9'},
              'subscription': null,
              'metadata': <String, Object?>{'dartvel_plan': 'lifetime'},
            },
          });

      final String free = completed('no_payment_required');
      final DVBillingWebhookResult nothing =
          await bachs.handleWebhook(free, sign(free, nowSeconds));
      expect(nothing.granted, isEmpty);

      final String paid = completed('paid');
      final DVBillingWebhookResult result =
          await bachs.handleWebhook(paid, sign(paid, nowSeconds));
      expect(result.handled, isTrue);
      expect(result.granted, <Entitlement>{exports});
      expect(await bachs.hasEntitlement('cust_9', exports), isTrue);
    });

    test('an event this does not act on is acknowledged and changes nothing',
        () async {
      final DVBachsBillingProvider bachs = provider();
      final String payload = jsonEncode(<String, Object?>{
        'id': 'evt_p',
        'type': 'payout.paid',
        'created_at': '2026-10-09T11:59:00Z',
        'data': <String, Object?>{},
      });
      final DVBillingWebhookResult result =
          await bachs.handleWebhook(payload, sign(payload, nowSeconds));
      expect(result.handled, isFalse);
      expect(result.type, 'payout.paid');
    });
  });

  group('subscription lifecycle', () {
    final String list = jsonEncode(<String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'id': 'sub_old',
          'customer': <String, Object?>{'customer_id': 'cust_1'},
          'status': 'canceled',
          'cancel_at_period_end': false,
        },
        <String, Object?>{
          'id': 'sub_1',
          'customer': <String, Object?>{'customer_id': 'cust_1'},
          'status': 'active',
          'cancel_at_period_end': true,
          'current_period_end': '2026-11-01T00:00:00Z',
        },
      ],
      'pagination': <String, Object?>{'has_more': false},
    });

    test('status reads the current subscription for the customer', () async {
      final DVBachsBillingProvider bachs = provider(
          responses: <String, (int, String)>{'GET /v1/subscriptions': (200, list)});
      final DVSubscriptionStatus status =
          await bachs.subscriptionStatus(customer: 'cust_1');
      expect(status.status, 'active');
      expect(status.cancelAtPeriodEnd, isTrue);
      expect(status.currentPeriodEnd, DateTime.utc(2026, 11));
      expect(sent.single.$2.queryParameters['customer_id'], 'cust_1');
    });

    test('a plan change sends the product and the proration choice', () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'GET /v1/subscriptions': (200, list),
        'PATCH /v1/subscriptions/sub_1': (200, '{"id":"sub_1"}'),
      });
      await bachs.changeSubscriptionPlan(
          customer: 'cust_1', plan: business, prorate: false);
      final Sent patch = sent.last;
      expect(patch.$1, 'PATCH');
      expect(jsonDecode(patch.$4!), <String, Object?>{
        'product_id': 'prod_business',
        'proration_behavior': 'next_cycle',
      });
    });

    test('cancel at period end is a DELETE carrying the flag', () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'GET /v1/subscriptions': (200, list),
        'DELETE /v1/subscriptions/sub_1': (200, '{"id":"sub_1"}'),
      });
      await bachs.cancelSubscription(customer: 'cust_1', atPeriodEnd: true);
      expect(sent.last.$1, 'DELETE');
      expect(jsonDecode(sent.last.$4!), <String, Object?>{'cancel_at_period_end': true});
    });

    test('the customer portal URL comes from a fresh portal session', () async {
      final DVBachsBillingProvider bachs =
          provider(responses: <String, (int, String)>{
        'POST /v1/customers/cust_1/portal-sessions':
            (200, '{"id":"psn_1","url":"https://billing.bachs.io/p/psn_1"}'),
      });
      expect(await bachs.customerPortalUrl(customer: 'cust_1'),
          'https://billing.bachs.io/p/psn_1');
    });

    test('pause and resume are refused rather than faked', () async {
      final DVBachsBillingProvider bachs = provider();
      await expectLater(bachs.pauseSubscription(customer: 'cust_1'),
          throwsA(isA<UnsupportedError>()));
      await expectLater(bachs.resumeSubscription(customer: 'cust_1'),
          throwsA(isA<UnsupportedError>()));
      expect(sent, isEmpty);
    });
  });

  group('what Bachs has no endpoint for', () {
    test('invoices are refused: payments cannot be listed per customer',
        () async {
      await expectLater(provider().invoices('cust_1'),
          throwsA(isA<UnsupportedError>()));
    });

    test('usage is refused rather than dropped', () async {
      await expectLater(
        provider().recordUsage(
          customer: 'cust_1',
          meter: const DVUsageMeter('api_calls'),
          quantity: 1,
          idempotencyKey: 'job_1',
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
