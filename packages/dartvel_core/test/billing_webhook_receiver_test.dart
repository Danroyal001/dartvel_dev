// A provider says which header carries its signature.
//
// Verification lived on the concrete provider classes and nowhere else, so
// an application holding a DVBillingProvider -- which is what DV.Billing
// hands out -- could not verify a webhook at all. The way past that is to
// downcast to the provider you happen to have configured, or to write the
// HMAC comparison again in the route, and the second one is how a webhook
// endpoint ends up trusting whatever is posted to it.
//
// Naming the header is part of the same job. Stripe signs under
// Stripe-Signature and Paddle under Paddle-Signature, so a caller that has
// to know which provider is configured in order to pull the right header
// has not really been given a provider-independent surface.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('Stripe receives webhooks, and says where its signature is', () {
    final DVStripeBillingProvider p = DVStripeBillingProvider(
      secretKey: 'sk_test',
      webhookSecret: 'whsec_test',
      prices: const <String, String>{},
      entitlements: const <String, Set<Entitlement>>{},
      successUrl: Uri.parse('https://app.example/ok'),
      cancelUrl: Uri.parse('https://app.example/no'),
    );

    expect(p, isA<DVBillingWebhookReceiver>());
    expect(p.signatureHeaderName, 'Stripe-Signature');
  });

  test('Paddle receives webhooks under its own header', () {
    final DVPaddleBillingProvider p = DVPaddleBillingProvider(
      apiKey: 'pdl_live_key',
      webhookSecret: 's',
      prices: const <String, String>{},
      entitlements: const <String, Set<Entitlement>>{},
    );

    expect(p, isA<DVBillingWebhookReceiver>());
    expect(p.signatureHeaderName, 'Paddle-Signature');
  });

  test('the local provider receives none, and is not one', () {
    // Nothing signs a local grant, so there is no signature to check and
    // pretending otherwise would put an unverified path behind the same
    // call as the verified ones.
    expect(DVLocalBillingProvider(), isNot(isA<DVBillingWebhookReceiver>()));
  });
}
