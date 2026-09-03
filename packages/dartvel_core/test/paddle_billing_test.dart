// Paddle as a billing provider: transactions and signed webhooks.
//
// The Billing section names Paddle beside Stripe. Same two boundaries: the
// request that creates a checkout carries the API key and nothing echoes it,
// and a webhook is believed only when its Paddle-Signature is right. Paddle's
// scheme differs from Stripe's in the details -- `ts=<unix>;h1=<hex>`, HMAC
// over "<ts>:<payload>" -- and the details are what a copy-paste of the
// Stripe verifier would get wrong while still looking like it verified.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const BillingPlan pro = BillingPlan(
    id: 'pro', displayName: 'Pro', priceMinorUnits: 4000, currency: 'USD');

String sign(String payload, int ts, {String secret = 'pdl_ntf_secret'}) {
  final String h1 = Hmac(sha256, utf8.encode(secret))
      .convert(utf8.encode('$ts:$payload'))
      .toString();
  return 'ts=$ts;h1=$h1';
}

String subscriptionEvent({required String type, required String status, String customer = 'ctm_1', String price = 'pri_pro'}) =>
    jsonEncode(<String, Object?>{
      'event_id': 'evt_1',
      'event_type': type,
      'data': <String, Object?>{
        'id': 'sub_1',
        'customer_id': customer,
        'status': status,
        'items': <Object?>[
          <String, Object?>{'price': <String, Object?>{'id': price}},
        ],
      },
    });

void main() {
  late List<(Uri, Map<String, String>, String)> requests;

  DVPaddleBillingProvider provider({Map<String, (int, String)> responses = const <String, (int, String)>{}, DateTime? now}) {
    requests = <(Uri, Map<String, String>, String)>[];
    return DVPaddleBillingProvider(
      apiKey: 'pdl_live_apikey',
      webhookSecret: 'pdl_ntf_secret',
      prices: <String, String>{'pro': 'pri_pro'},
      entitlements: <String, Set<Entitlement>>{'pri_pro': <Entitlement>{Entitlement.analytics}},
      fetch: (Uri url, Map<String, String> headers, String body) async {
        requests.add((url, headers, body));
        return responses[url.path] ?? (404, '{"error":{"detail":"no"}}');
      },
      clock: () => now ?? DateTime.utc(2026, 9, 3, 12),
    );
  }

  group('checkout', () {
    test('creates a transaction with the key as a bearer and the price as an item', () async {
      final DVPaddleBillingProvider p = provider(responses: <String, (int, String)>{
        '/transactions': (201, '{"data":{"id":"txn_1","checkout":{"url":"https://pay.example/txn_1"}}}'),
      });

      final DVBillingCheckoutSession s = await p.checkout(plan: pro, customer: 'user_7');

      expect(s.id, 'txn_1');
      expect(s.checkoutUrl, Uri.parse('https://pay.example/txn_1'));
      final (Uri url, Map<String, String> headers, String body) = requests.single;
      expect(url.host, 'api.paddle.com');
      expect(headers['Authorization'], 'Bearer pdl_live_apikey');
      expect(headers['Content-Type'], contains('application/json'));
      final Map<String, Object?> sent = jsonDecode(body) as Map<String, Object?>;
      expect((sent['items'] as List).single, <String, Object?>{'price_id': 'pri_pro', 'quantity': 1});
      expect((sent['custom_data'] as Map)['customer'], 'user_7');
    });

    test('sandbox keys go to the sandbox host', () async {
      final DVPaddleBillingProvider p = DVPaddleBillingProvider(
        apiKey: 'pdl_sdbx_apikey',
        webhookSecret: 's',
        prices: <String, String>{'pro': 'pri_pro'},
        entitlements: const <String, Set<Entitlement>>{},
        fetch: (Uri url, Map<String, String> h, String b) async {
          expect(url.host, 'sandbox-api.paddle.com');
          return (201, '{"data":{"id":"txn_1"}}');
        },
      );
      await p.checkout(plan: pro, customer: 'u');
    });

    test('a refused key says key and never contains it', () async {
      final DVPaddleBillingProvider p = provider(responses: <String, (int, String)>{
        '/transactions': (403, '{"error":{"code":"authentication_failed","detail":"Authentication header included, but incorrectly formatted"}}'),
      });
      try {
        await p.checkout(plan: pro, customer: 'u');
        fail('expected an error');
      } on DVBillingError catch (e) {
        expect(e.message.toLowerCase(), contains('key'));
        expect(e.toString(), isNot(contains('pdl_live_apikey')));
      }
    });

    test('a plan with no price is refused before any request', () async {
      const BillingPlan other = BillingPlan(id: 'x', displayName: 'x', priceMinorUnits: 1, currency: 'USD');
      await expectLater(provider().checkout(plan: other, customer: 'u'), throwsA(isA<DVBillingError>()));
      expect(requests, isEmpty);
    });
  });

  group('webhooks', () {
    final int t = DateTime.utc(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000;

    test('a signed activation grants the price\'s entitlements', () async {
      final DVPaddleBillingProvider p = provider();
      final String payload = subscriptionEvent(type: 'subscription.activated', status: 'active');
      final DVBillingWebhookResult r = await p.handleWebhook(payload, sign(payload, t));
      expect(r.handled, isTrue);
      expect(await p.hasEntitlement('ctm_1', Entitlement.analytics), isTrue);
    });

    test('a cancellation revokes them', () async {
      final DVPaddleBillingProvider p = provider();
      final String on = subscriptionEvent(type: 'subscription.activated', status: 'active');
      await p.handleWebhook(on, sign(on, t));
      final String off = subscriptionEvent(type: 'subscription.canceled', status: 'canceled');
      await p.handleWebhook(off, sign(off, t));
      expect(await p.hasEntitlement('ctm_1', Entitlement.analytics), isFalse);
    });

    test('a Stripe-shaped signature is not accepted', () async {
      // The scheme is ts=;h1= over "ts:payload". A verifier copied from the
      // Stripe one would compute "ts.payload" and accept nothing, or worse,
      // parse t= and accept anything. This is the header Stripe would send.
      final DVPaddleBillingProvider p = provider();
      final String payload = subscriptionEvent(type: 'subscription.activated', status: 'active');
      final String stripeStyle = 't=$t,v1=${Hmac(sha256, utf8.encode('pdl_ntf_secret')).convert(utf8.encode('$t.$payload'))}';
      await expectLater(p.handleWebhook(payload, stripeStyle), throwsA(isA<DVBillingError>()));
    });

    test('a bad secret is refused and grants nothing', () async {
      final DVPaddleBillingProvider p = provider();
      final String payload = subscriptionEvent(type: 'subscription.activated', status: 'active');
      await expectLater(p.handleWebhook(payload, sign(payload, t, secret: 'wrong')), throwsA(isA<DVBillingError>()));
      expect(await p.hasEntitlement('ctm_1', Entitlement.analytics), isFalse);
    });

    test('a stale timestamp is refused at the edge', () async {
      final String payload = subscriptionEvent(type: 'subscription.activated', status: 'active');
      final DVPaddleBillingProvider inside = provider(now: DateTime.utc(2026, 9, 3, 12, 4, 59));
      expect((await inside.handleWebhook(payload, sign(payload, t))).handled, isTrue);
      final DVPaddleBillingProvider outside = provider(now: DateTime.utc(2026, 9, 3, 12, 5, 1));
      await expectLater(outside.handleWebhook(payload, sign(payload, t)), throwsA(isA<DVBillingError>()));
    });

    test('an event this provider does not act on is acknowledged', () async {
      final DVPaddleBillingProvider p = provider();
      final String payload = jsonEncode(<String, Object?>{'event_type': 'transaction.paid', 'data': <String, Object?>{}});
      final DVBillingWebhookResult r = await p.handleWebhook(payload, sign(payload, t));
      expect(r.handled, isFalse);
      expect(r.type, 'transaction.paid');
    });
  });
}
