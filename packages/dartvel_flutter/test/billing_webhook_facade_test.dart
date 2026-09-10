// A webhook can be verified through DV.Billing.
//
// Signature checking existed only on the concrete provider classes, and
// DV.Billing hands out a DVBillingProvider, so the route that receives a
// webhook either downcast to whichever provider happened to be configured
// or verified the payload itself. Written a second time in a route, that
// check is the one that gets simplified until an unsigned "subscription
// activated" is accepted -- which is somebody granting themselves a plan.
//
// The facade finds the signature by asking the provider which header it
// signs under, so the calling route does not have to know whether Stripe or
// Paddle is configured.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const int at = 1788436800; // 2026-09-03T12:00:00Z, matching the clock below.

String event(String status) => jsonEncode(<String, Object?>{
      'id': 'evt_1',
      'type': 'customer.subscription.updated',
      'created': at,
      'data': <String, Object?>{
        'object': <String, Object?>{
          'id': 'sub_1',
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

String sign(String payload) =>
    't=$at,v1=${Hmac(sha256, utf8.encode('whsec_test')).convert(utf8.encode('$at.$payload')).toString()}';

DVStripeBillingProvider stripe() => DVStripeBillingProvider(
      secretKey: 'sk_test',
      webhookSecret: 'whsec_test',
      prices: const <String, String>{'pro': 'price_pro'},
      entitlements: <String, Set<Entitlement>>{
        'price_pro': <Entitlement>{Entitlement.analytics},
      },
      successUrl: Uri.parse('https://app.example/ok'),
      cancelUrl: Uri.parse('https://app.example/no'),
      clock: () => DateTime.fromMillisecondsSinceEpoch(at * 1000, isUtc: true),
    );

void main() {
  tearDown(DV.Test.resetBillingProvider);

  test('a signed event applies through the facade', () async {
    DV.Billing.useProvider(stripe());
    final String payload = event('active');

    final DVBillingWebhookResult result = await DV.Billing.handleWebhook(
      payload,
      <String, String>{'Stripe-Signature': sign(payload)},
    );

    expect(result.handled, isTrue);
    expect(
        await DV.Billing.hasEntitlement('cus_123', Entitlement.analytics),
        isTrue);
  });

  test('the header is found whatever case it arrives in', () async {
    // HTTP header names are case-insensitive, and different servers hand
    // them over differently. A lookup that missed would refuse a genuine
    // webhook, which fails closed but for a reason nobody could find.
    DV.Billing.useProvider(stripe());
    final String payload = event('active');

    final DVBillingWebhookResult result = await DV.Billing.handleWebhook(
      payload,
      <String, String>{'stripe-signature': sign(payload)},
    );

    expect(result.handled, isTrue);
  });

  test('a request with no signature grants nothing', () async {
    DV.Billing.useProvider(stripe());
    final String payload = event('active');

    // A closure: with no header there is nothing to verify, so the refusal
    // comes before there is a future to attach it to.
    await expectLater(
      () => DV.Billing.handleWebhook(payload, const <String, String>{}),
      throwsA(isA<DVBillingError>()),
    );
    expect(
        await DV.Billing.hasEntitlement('cus_123', Entitlement.analytics),
        isFalse);
  });

  test('a forged signature grants nothing', () async {
    DV.Billing.useProvider(stripe());
    final String payload = event('active');

    await expectLater(
      DV.Billing.handleWebhook(payload, <String, String>{
        'Stripe-Signature': 't=$at,v1=deadbeef',
      }),
      throwsA(isA<DVBillingError>()),
    );
    expect(
        await DV.Billing.hasEntitlement('cus_123', Entitlement.analytics),
        isFalse);
  });

  test('a provider with no webhooks says so instead of accepting one',
      () async {
    // Nothing signs a local grant. Answering this call by applying the
    // payload would be an unverified path behind the same method name as
    // the verified ones.
    DV.Billing.useProvider(DVLocalBillingProvider());

    await expectLater(
      () => DV.Billing.handleWebhook(event('active'), const <String, String>{}),
      throwsA(isA<StateError>()),
    );
  });
}
