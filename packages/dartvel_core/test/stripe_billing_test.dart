// Stripe as a billing provider: checkout sessions and signed webhooks.
//
// The Billing section names Stripe first and nothing implemented it; the
// local provider was the only one. What a real provider has to get right is
// not the happy path but the two places money and trust cross a boundary:
// the request that creates a checkout session must carry the secret key and
// nothing else must ever echo it, and a webhook must be believed only when
// its signature is Stripe's -- an unsigned "subscription activated" is how
// someone grants themselves a plan.
//
// HTTP is an injected function and the clock is injected, so nothing here
// touches Stripe and the timestamp tolerance is tested at its edge rather
// than by waiting five minutes.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const BillingPlan pro = BillingPlan(
    id: 'pro', displayName: 'Pro', priceMinorUnits: 4000, currency: 'USD');

/// Stripe's signature header for [payload] at [timestamp].
String sign(String payload, int timestamp, {String secret = 'whsec_test'}) {
  final Hmac hmac = Hmac(sha256, utf8.encode(secret));
  final String v1 = hmac.convert(utf8.encode('$timestamp.$payload')).toString();
  return 't=$timestamp,v1=$v1';
}

String subscriptionEvent({
  required String type,
  required String status,
  String customer = 'cus_123',
  String price = 'price_pro',
}) =>
    jsonEncode(<String, Object?>{
      'id': 'evt_1',
      'type': type,
      'data': <String, Object?>{
        'object': <String, Object?>{
          'id': 'sub_1',
          'customer': customer,
          'status': status,
          'items': <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'price': <String, Object?>{'id': price},
              },
            ],
          },
        },
      },
    });

void main() {
  late List<(Uri, Map<String, String>, String)> requests;

  DVStripeBillingProvider provider({
    Map<String, (int, String)> responses = const <String, (int, String)>{},
    DateTime? now,
  }) {
    requests = <(Uri, Map<String, String>, String)>[];
    return DVStripeBillingProvider(
      secretKey: 'sk_test_secret',
      webhookSecret: 'whsec_test',
      prices: <String, String>{'pro': 'price_pro'},
      entitlements: <String, Set<Entitlement>>{
        'price_pro': <Entitlement>{Entitlement.analytics},
      },
      successUrl: Uri.parse('https://app.example/billing/success'),
      cancelUrl: Uri.parse('https://app.example/billing/cancel'),
      fetch: (Uri url, Map<String, String> headers, String body) async {
        requests.add((url, headers, body));
        return responses[url.path] ?? (404, '{"error":{"message":"no"}}');
      },
      clock: () => now ?? DateTime.utc(2026, 9, 3, 12),
    );
  }

  group('checkout', () {
    test('creates a session with the key in the header and the plan as a price',
        () async {
      final DVStripeBillingProvider p = provider(responses: <String, (int, String)>{
        '/v1/checkout/sessions': (200, '{"id":"cs_1","url":"https://checkout.stripe.com/c/cs_1"}'),
      });

      final DVBillingCheckoutSession session =
          await p.checkout(plan: pro, customer: 'user_7');

      expect(session.id, 'cs_1');
      expect(session.checkoutUrl, Uri.parse('https://checkout.stripe.com/c/cs_1'));
      final (Uri url, Map<String, String> headers, String body) = requests.single;
      expect(url.host, 'api.stripe.com');
      expect(headers['Authorization'], 'Bearer sk_test_secret');
      expect(body, contains('line_items%5B0%5D%5Bprice%5D=price_pro'));
      expect(body, contains('mode=subscription'));
      expect(body, contains('client_reference_id=user_7'));
      expect(body, contains('success_url='));
    });

    test('a plan with no price configured is refused before any request',
        () async {
      const BillingPlan unknown = BillingPlan(
          id: 'enterprise', displayName: 'E', priceMinorUnits: 0, currency: 'USD');
      final DVStripeBillingProvider p = provider();
      await expectLater(p.checkout(plan: unknown, customer: 'u'),
          throwsA(isA<DVBillingError>()));
      expect(requests, isEmpty);
    });

    test('a refused key says key, and never contains it', () async {
      final DVStripeBillingProvider p = provider(responses: <String, (int, String)>{
        '/v1/checkout/sessions': (401, '{"error":{"message":"Invalid API Key provided: sk_test_******cret"}}'),
      });
      try {
        await p.checkout(plan: pro, customer: 'u');
        fail('expected an error');
      } on DVBillingError catch (e) {
        expect(e.message.toLowerCase(), contains('key'));
        expect(e.toString(), isNot(contains('sk_test_secret')));
      }
    });

    test('a Stripe error message is surfaced', () async {
      final DVStripeBillingProvider p = provider(responses: <String, (int, String)>{
        '/v1/checkout/sessions': (400, '{"error":{"message":"No such price: price_pro"}}'),
      });
      await expectLater(
        p.checkout(plan: pro, customer: 'u'),
        throwsA(isA<DVBillingError>().having(
            (DVBillingError e) => e.message, 'message', contains('No such price'))),
      );
    });
  });

  group('webhooks', () {
    test('a correctly signed subscription activation grants the plan\'s entitlements',
        () async {
      final DVStripeBillingProvider p = provider();
      final String payload = subscriptionEvent(
          type: 'customer.subscription.updated', status: 'active');
      final int t = DateTime.utc(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000;

      final DVBillingWebhookResult result =
          await p.handleWebhook(payload, sign(payload, t));

      expect(result.handled, isTrue);
      expect(result.type, 'customer.subscription.updated');
      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isTrue);
    });

    test('a cancelled subscription revokes them', () async {
      final DVStripeBillingProvider p = provider();
      final int t = DateTime.utc(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000;
      final String on = subscriptionEvent(type: 'customer.subscription.updated', status: 'active');
      await p.handleWebhook(on, sign(on, t));
      final String off = subscriptionEvent(type: 'customer.subscription.deleted', status: 'canceled');
      await p.handleWebhook(off, sign(off, t));

      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isFalse);
    });

    test('a bad signature is refused and grants nothing', () async {
      // The whole point: an unsigned "activated" is how someone grants
      // themselves a plan.
      final DVStripeBillingProvider p = provider();
      final String payload = subscriptionEvent(type: 'customer.subscription.updated', status: 'active');
      final int t = DateTime.utc(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000;

      await expectLater(
        p.handleWebhook(payload, sign(payload, t, secret: 'whsec_wrong')),
        throwsA(isA<DVBillingError>()),
      );
      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isFalse);
    });

    test('a tampered payload is refused', () async {
      final DVStripeBillingProvider p = provider();
      final String payload = subscriptionEvent(type: 'customer.subscription.updated', status: 'active');
      final int t = DateTime.utc(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000;
      final String header = sign(payload, t);
      final String tampered = payload.replaceAll('cus_123', 'cus_999');

      await expectLater(p.handleWebhook(tampered, header), throwsA(isA<DVBillingError>()));
    });

    test('a signature older than the tolerance is refused, at the edge', () async {
      // Replay protection. Signed at 12:00; accepted at 12:04:59, refused at
      // 12:05:01.
      final String payload = subscriptionEvent(type: 'customer.subscription.updated', status: 'active');
      final int t = DateTime.utc(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000;

      final DVStripeBillingProvider inside = provider(now: DateTime.utc(2026, 9, 3, 12, 4, 59));
      expect((await inside.handleWebhook(payload, sign(payload, t))).handled, isTrue);

      final DVStripeBillingProvider outside = provider(now: DateTime.utc(2026, 9, 3, 12, 5, 1));
      await expectLater(outside.handleWebhook(payload, sign(payload, t)),
          throwsA(isA<DVBillingError>()));
    });

    test('a malformed header is refused, not a crash', () async {
      final DVStripeBillingProvider p = provider();
      for (final String header in <String>['', 'nonsense', 't=abc,v1=', 'v1=deadbeef']) {
        await expectLater(p.handleWebhook('{}', header), throwsA(isA<DVBillingError>()),
            reason: header);
      }
    });

    test('an event type this provider does not act on is acknowledged, not an error',
        () async {
      // Stripe retries a webhook that is not acknowledged. Refusing
      // invoice.paid because nothing here acts on it would make Stripe
      // hammer the endpoint for days.
      final DVStripeBillingProvider p = provider();
      final String payload = jsonEncode(<String, Object?>{'id': 'evt_2', 'type': 'invoice.paid', 'data': <String, Object?>{'object': <String, Object?>{}}});
      final int t = DateTime.utc(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000;

      final DVBillingWebhookResult result = await p.handleWebhook(payload, sign(payload, t));
      expect(result.handled, isFalse);
      expect(result.type, 'invoice.paid');
    });

    test('a subscription for a price with no entitlements grants nothing, and says so',
        () async {
      final DVStripeBillingProvider p = provider();
      final String payload = subscriptionEvent(type: 'customer.subscription.updated', status: 'active', price: 'price_unknown');
      final int t = DateTime.utc(2026, 9, 3, 12).millisecondsSinceEpoch ~/ 1000;

      final DVBillingWebhookResult result = await p.handleWebhook(payload, sign(payload, t));
      expect(result.handled, isTrue);
      expect(result.granted, isEmpty);
      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isFalse);
    });
  });
}
