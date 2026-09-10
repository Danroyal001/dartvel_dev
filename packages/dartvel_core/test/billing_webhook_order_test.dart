// A webhook that arrives late does not undo a decision made from a newer one.
//
// Stripe says plainly that its events are not guaranteed to arrive in the
// order they happened, and Paddle's retries have the same property: a
// delivery that fails and is retried lands after whatever was sent in the
// meantime. Both providers were being applied in arrival order, so a
// subscription cancelled at 12:05 and a stale "active" from 12:00 that
// showed up at 12:06 left the customer holding the entitlement they had
// just lost.
//
// That is the worst shape a billing bug takes. Nothing throws, the webhook
// is signed and genuine, the endpoint returns 200, and access quietly
// outlives the subscription that paid for it. The only place it shows up is
// a revenue report nobody reads against an access log nobody reads either.
//
// Being late is not the same as being wrong, so a stale event is still
// acknowledged: an unacknowledged webhook is retried for days.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

String stripeSign(String payload, int timestamp,
    {String secret = 'whsec_test'}) {
  final String v1 = Hmac(sha256, utf8.encode(secret))
      .convert(utf8.encode('$timestamp.$payload'))
      .toString();
  return 't=$timestamp,v1=$v1';
}

String stripeEvent({
  required String type,
  required String status,
  required int created,
  String subscription = 'sub_1',
}) =>
    jsonEncode(<String, Object?>{
      'id': 'evt_$created',
      'type': type,
      'created': created,
      'data': <String, Object?>{
        'object': <String, Object?>{
          'id': subscription,
          'customer': 'cus_123',
          'status': status,
          'items': <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'price': <String, Object?>{'id': 'price_pro'},
              },
            ],
          },
        },
      },
    });

String paddleSign(String payload, int ts, {String secret = 'pdl_ntf_secret'}) {
  final String h1 = Hmac(sha256, utf8.encode(secret))
      .convert(utf8.encode('$ts:$payload'))
      .toString();
  return 'ts=$ts;h1=$h1';
}

String paddleEvent({
  required String type,
  required String status,
  required DateTime occurredAt,
}) =>
    jsonEncode(<String, Object?>{
      'event_id': 'evt_${occurredAt.millisecondsSinceEpoch}',
      'event_type': type,
      'occurred_at': occurredAt.toIso8601String(),
      'data': <String, Object?>{
        'id': 'sub_1',
        'customer_id': 'ctm_1',
        'status': status,
        'items': <Object?>[
          <String, Object?>{
            'price': <String, Object?>{'id': 'pri_pro'},
          },
        ],
      },
    });

void main() {
  final DateTime now = DateTime.utc(2026, 9, 3, 12, 6);
  final int nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

  group('Stripe', () {
    DVStripeBillingProvider provider() => DVStripeBillingProvider(
          secretKey: 'sk_test',
          webhookSecret: 'whsec_test',
          prices: const <String, String>{'pro': 'price_pro'},
          entitlements: <String, Set<Entitlement>>{
            'price_pro': <Entitlement>{Entitlement.analytics},
          },
          successUrl: Uri.parse('https://app.example/ok'),
          cancelUrl: Uri.parse('https://app.example/no'),
          clock: () => now,
        );

    test('an activation that happened before the cancellation does not bring '
        'the entitlement back', () async {
      final DVStripeBillingProvider p = provider();
      final String cancelled = stripeEvent(
          type: 'customer.subscription.updated',
          status: 'canceled',
          created: nowSeconds - 60);
      final String stale = stripeEvent(
          type: 'customer.subscription.updated',
          status: 'active',
          created: nowSeconds - 360);

      await p.handleWebhook(cancelled, stripeSign(cancelled, nowSeconds));
      final DVBillingWebhookResult result =
          await p.handleWebhook(stale, stripeSign(stale, nowSeconds));

      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isFalse);
      expect(result.stale, isTrue);
      // Still acknowledged. Stripe retries what it does not hear back on.
      expect(result.granted, isEmpty);
    });

    test('a newer event still applies', () async {
      final DVStripeBillingProvider p = provider();
      final String older = stripeEvent(
          type: 'customer.subscription.updated',
          status: 'active',
          created: nowSeconds - 360);
      final String newer = stripeEvent(
          type: 'customer.subscription.updated',
          status: 'canceled',
          created: nowSeconds - 60);

      await p.handleWebhook(older, stripeSign(older, nowSeconds));
      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isTrue);

      final DVBillingWebhookResult result =
          await p.handleWebhook(newer, stripeSign(newer, nowSeconds));

      expect(result.stale, isFalse);
      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isFalse);
    });

    test('order is tracked per subscription, not across them', () async {
      // Two subscriptions move independently. Keeping one high-water mark
      // for the whole provider would drop every event for a subscription
      // that happened to be updated a moment ago.
      final DVStripeBillingProvider p = provider();
      final String other = stripeEvent(
          type: 'customer.subscription.updated',
          status: 'active',
          created: nowSeconds - 10,
          subscription: 'sub_2');
      final String mine = stripeEvent(
          type: 'customer.subscription.updated',
          status: 'active',
          created: nowSeconds - 300);

      await p.handleWebhook(other, stripeSign(other, nowSeconds));
      final DVBillingWebhookResult result =
          await p.handleWebhook(mine, stripeSign(mine, nowSeconds));

      expect(result.stale, isFalse);
      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isTrue);
    });

    test('two events in the same second are applied in arrival order', () async {
      // Stripe's created is whole seconds, so an update and the deletion
      // that follows it can share one. Refusing the second would leave the
      // subscription looking alive.
      final DVStripeBillingProvider p = provider();
      final String on = stripeEvent(
          type: 'customer.subscription.updated',
          status: 'active',
          created: nowSeconds - 60);
      final String off = stripeEvent(
          type: 'customer.subscription.deleted',
          status: 'canceled',
          created: nowSeconds - 60);

      await p.handleWebhook(on, stripeSign(on, nowSeconds));
      await p.handleWebhook(off, stripeSign(off, nowSeconds));

      expect(await p.hasEntitlement('cus_123', Entitlement.analytics), isFalse);
    });
  });

  group('Paddle', () {
    DVPaddleBillingProvider provider() => DVPaddleBillingProvider(
          apiKey: 'pdl_live_key',
          webhookSecret: 'pdl_ntf_secret',
          prices: const <String, String>{'pro': 'pri_pro'},
          entitlements: <String, Set<Entitlement>>{
            'pri_pro': <Entitlement>{Entitlement.analytics},
          },
          clock: () => now,
        );

    test('a retried activation does not undo a later cancellation', () async {
      final DVPaddleBillingProvider p = provider();
      final String cancelled = paddleEvent(
          type: 'subscription.canceled',
          status: 'canceled',
          occurredAt: now.subtract(const Duration(minutes: 1)));
      final String stale = paddleEvent(
          type: 'subscription.activated',
          status: 'active',
          occurredAt: now.subtract(const Duration(minutes: 6)));

      await p.handleWebhook(cancelled, paddleSign(cancelled, nowSeconds));
      final DVBillingWebhookResult result =
          await p.handleWebhook(stale, paddleSign(stale, nowSeconds));

      expect(result.stale, isTrue);
      expect(await p.hasEntitlement('ctm_1', Entitlement.analytics), isFalse);
    });

    test('a newer event still applies', () async {
      final DVPaddleBillingProvider p = provider();
      final String on = paddleEvent(
          type: 'subscription.activated',
          status: 'active',
          occurredAt: now.subtract(const Duration(minutes: 6)));
      final String off = paddleEvent(
          type: 'subscription.canceled',
          status: 'canceled',
          occurredAt: now.subtract(const Duration(minutes: 1)));

      await p.handleWebhook(on, paddleSign(on, nowSeconds));
      expect(await p.hasEntitlement('ctm_1', Entitlement.analytics), isTrue);

      final DVBillingWebhookResult result =
          await p.handleWebhook(off, paddleSign(off, nowSeconds));

      expect(result.stale, isFalse);
      expect(await p.hasEntitlement('ctm_1', Entitlement.analytics), isFalse);
    });
  });
}
