// DV.Billing configured from `dartvel.billing`, on the server.
//
// The block names a provider and the secrets that hold its keys. The
// generated server hands it to DV.Billing at start, and DV.Billing builds the
// provider the first time something asks for it -- so a server whose keys are
// not set yet still starts, and says "not set up" at checkout instead of
// refusing to boot. An operator moves to the backup provider with
// DARTVEL_BILLING_PROVIDER, and a staging copy or a spare-port test keeps its
// buyers with DARTVEL_BILLING_SITE_URL, neither needing a rebuild.
//
// What an application used to work out for itself -- which provider is
// configured, a provider by name for its own webhook route, whether a buyer's
// return may confirm a payment -- is answered here, so no application keeps
// a provider layer of its own.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart' as server;
import 'package:test/test.dart';

void main() {
  tearDown(() {
    DVBilling.reset();
    DVSecrets.reset();
    DVHttp.reset();
  });

  final Map<String, Object?> flutterwaveBlock = <String, Object?>{
    'provider': 'flutterwave',
    'successUrl': 'https://shop.example/payments/return',
    'cancelUrl': 'https://shop.example/cart',
  };

  DVBillingConfig flutterwave() => DVBillingConfig.read(flutterwaveBlock);

  void flutterwaveKeys() => DVSecrets.configure(<String, String>{
        'FLUTTERWAVE_SECRET_KEY': 'FLWSECK_TEST-0000000000000000-X',
        'FLUTTERWAVE_WEBHOOK_HASH': 'a-hash-of-our-own-choosing',
      });

  void paystackKeys() => DVSecrets.configure(<String, String>{
        'PAYSTACK_SECRET_KEY': 'sk_test_paystack_0000000000000000',
      });

  DVBillingOrder order(String reference) => DVBillingOrder(
        reference: reference,
        currency: 'NGN',
        lines: const <DVBillingOrderLine>[
          DVBillingOrderLine(name: 'Pro tool', unitMinorUnits: 500000),
        ],
        customerEmail: 'buyer@example.com',
        successUrl: const DVBilling().successUrl!,
        cancelUrl: const DVBilling().cancelUrl!,
      );

  test('the server side DV has the same Billing as the Flutter side', () {
    expect(server.DV.Billing, isA<DVBilling>());
    flutterwaveKeys();
    server.DV.Billing.configure(flutterwave());
    expect(const DVBilling().provider, isA<DVFlutterwaveBillingProvider>());
  });

  test('nothing configured: not set up, no provider, no name', () {
    const DVBilling billing = DVBilling();
    expect(billing.isSetUp, isFalse);
    expect(billing.provider, isNull);
    expect(billing.providerName, isNull);
    expect(billing.confirmsOnReturn, isFalse);
  });

  test('configured without keys: the name is known, the provider is not '
      'built, and checkout says what is missing', () async {
    const DVBilling billing = DVBilling();
    billing.configure(flutterwave());
    expect(billing.providerName, DVBillingProviderName.flutterwave);
    expect(billing.isSetUp, isFalse);
    expect(billing.provider, isNull);
    await expectLater(
      billing.checkoutOrder(order('ord-1')),
      throwsA(isA<DVBillingError>().having((DVBillingError e) => e.message,
          'message', allOf(contains('not set up'), contains('FLUTTERWAVE_SECRET_KEY')))),
    );
  });

  test('keys set after start are picked up at first use, and the provider is '
      'built once', () {
    const DVBilling billing = DVBilling();
    billing.configure(flutterwave());
    expect(billing.isSetUp, isFalse);
    flutterwaveKeys();
    final DVBillingProvider? first = billing.provider;
    expect(first, isA<DVFlutterwaveBillingProvider>());
    expect(identical(billing.provider, first), isTrue,
        reason: 'a webhook applied to one instance must be seen by the next call');
    expect(billing.isSetUp, isTrue);
    expect(billing.successUrl, Uri.parse('https://shop.example/payments/return'));
    expect(billing.cancelUrl, Uri.parse('https://shop.example/cart'));
  });

  test('whether the return may confirm is the provider\'s answer', () {
    expect(DVBillingProviderName.bachs.confirmsOnReturn, isFalse,
        reason: 'Bachs fulfils on its signed webhook only');
    expect(DVBillingProviderName.paystack.confirmsOnReturn, isTrue);
    expect(DVBillingProviderName.flutterwave.confirmsOnReturn, isTrue);
    flutterwaveKeys();
    const DVBilling().configure(flutterwave());
    expect(const DVBilling().confirmsOnReturn, isTrue);
  });

  test('a provider is named from its instance', () {
    paystackKeys();
    final DVBillingProvider paystack = DVBillingConfig.read(<String, Object?>{
      'provider': 'paystack',
      'successUrl': 'https://shop.example/r',
      'cancelUrl': 'https://shop.example/c',
    }).createProvider();
    expect(DVBillingProviderName.of(paystack), DVBillingProviderName.paystack);
    expect(DVBillingProviderName.of(DVLocalBillingProvider()), isNull);
    const DVBilling().useProvider(paystack);
    expect(const DVBilling().providerName, DVBillingProviderName.paystack);
  });

  group('DARTVEL_BILLING_PROVIDER', () {
    test('switches to another provider, with that provider\'s own keys and '
        'the same return addresses', () {
      paystackKeys();
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave(),
          environment: const <String, String>{'DARTVEL_BILLING_PROVIDER': 'paystack'});
      expect(billing.providerName, DVBillingProviderName.paystack);
      expect(billing.provider, isA<DVPaystackBillingProvider>());
      expect(billing.config!.apiKeySecret, 'PAYSTACK_SECRET_KEY');
      expect(billing.successUrl, Uri.parse('https://shop.example/payments/return'));
    });

    test('naming a provider Dartvel does not have is refused, not ignored', () {
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave(),
          environment: const <String, String>{'DARTVEL_BILLING_PROVIDER': 'paypal'});
      expect(() => billing.providerName,
          throwsA(isA<DVBillingConfigException>().having(
              (DVBillingConfigException e) => '$e', 'text',
              allOf(contains('DARTVEL_BILLING_PROVIDER'), contains('paypal')))));
    });

    test('empty means the configured provider', () {
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave(),
          environment: const <String, String>{'DARTVEL_BILLING_PROVIDER': ' '});
      expect(billing.providerName, DVBillingProviderName.flutterwave);
    });
  });

  group('DARTVEL_BILLING_SITE_URL', () {
    test('moves the return addresses to this deployment\'s origin, keeping '
        'their paths', () {
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave(),
          environment: const <String, String>{
            'DARTVEL_BILLING_SITE_URL': 'https://localhost:18443/',
          });
      expect(billing.successUrl, Uri.parse('https://localhost:18443/payments/return'));
      expect(billing.cancelUrl, Uri.parse('https://localhost:18443/cart'));
      flutterwaveKeys();
      expect((billing.provider! as DVFlutterwaveBillingProvider).redirectUrl,
          Uri.parse('https://localhost:18443/payments/return'));
    });

    test('a value that is not an origin is refused', () {
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave(),
          environment: const <String, String>{'DARTVEL_BILLING_SITE_URL': 'localhost'});
      expect(() => billing.successUrl,
          throwsA(isA<DVBillingConfigException>().having(
              (DVBillingConfigException e) => '$e', 'text',
              contains('DARTVEL_BILLING_SITE_URL'))));
    });
  });

  group('a provider by name, for its own webhook route', () {
    test('is built from the same block with its own default keys', () {
      flutterwaveKeys();
      paystackKeys();
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave());
      final DVBillingProvider? paystack =
          billing.providerNamed(DVBillingProviderName.paystack);
      expect(paystack, isA<DVPaystackBillingProvider>());
      expect(identical(billing.providerNamed(DVBillingProviderName.paystack), paystack),
          isTrue);
      expect(identical(billing.providerNamed(DVBillingProviderName.flutterwave),
              billing.provider), isTrue,
          reason: 'the configured provider by name is the configured provider');
    });

    test('is null when its keys are not set', () {
      flutterwaveKeys();
      const DVBilling().configure(flutterwave());
      expect(const DVBilling().providerNamed(DVBillingProviderName.bachs), isNull);
    });

    test('verifies a webhook signed for that provider', () async {
      flutterwaveKeys();
      paystackKeys();
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave());
      final String payload = jsonEncode(<String, Object?>{
        'event': 'charge.success',
        'data': <String, Object?>{'id': 1, 'reference': 'ord-7', 'status': 'success'},
      });
      final String signature = Hmac(sha512,
              utf8.encode('sk_test_paystack_0000000000000000'))
          .convert(utf8.encode(payload))
          .toString();
      final DVBillingWebhookResult result = await billing.handleWebhook(
        payload,
        <String, String>{'X-Paystack-Signature': signature},
        provider: DVBillingProviderName.paystack,
      );
      expect(result.reference, 'ord-7');
      await expectLater(
        billing.handleWebhook(payload, <String, String>{'x-paystack-signature': 'forged'},
            provider: DVBillingProviderName.paystack),
        throwsA(isA<DVBillingError>()),
      );
    });

    test('a webhook for a provider that is not set up says so', () async {
      flutterwaveKeys();
      const DVBilling().configure(flutterwave());
      await expectLater(
        const DVBilling().handleWebhook('{}', const <String, String>{},
            provider: DVBillingProviderName.bachs),
        throwsA(isA<DVBillingError>().having(
            (DVBillingError e) => e.message, 'message', contains('not set up'))),
      );
    });
  });

  group('one-time orders through DV.Billing', () {
    test('go to the configured provider over DV.Http when no transport is '
        'given', () async {
      flutterwaveKeys();
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave());
      final DVHttpFake fake = const DVHttp().fake(<String, DVHttpStub>{
        'api.flutterwave.com': DVHttpStub.json(<String, Object?>{
          'status': 'success',
          'data': <String, Object?>{'link': 'https://checkout.flutterwave.com/v3/hosted/pay/abc'},
        }),
      });
      final DVBillingOrderCheckout checkout =
          await billing.checkoutOrder(order('ord-2'));
      expect(checkout.url, Uri.parse('https://checkout.flutterwave.com/v3/hosted/pay/abc'));
      expect(fake.calls.single.url.path, '/v3/payments');
      expect(jsonDecode(utf8.decode(fake.calls.single.body))['redirect_url'],
          'https://shop.example/payments/return');
    });

    test('ask the configured provider for an order\'s status', () async {
      flutterwaveKeys();
      final List<Uri> asked = <Uri>[];
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave(), fetch: (String method, Uri url,
          Map<String, String> headers, String? body) async {
        asked.add(url);
        return (200, jsonEncode(<String, Object?>{
          'status': 'success',
          'data': <String, Object?>{
            'id': 99,
            'tx_ref': 'ord-3',
            'status': 'successful',
            'amount': 5000,
            'currency': 'NGN',
          },
        }));
      });
      final DVBillingOrderStatus status =
          await billing.orderStatus(reference: 'ord-3');
      expect(status.paidInFull(order('ord-3')), isTrue);
      expect(asked.single.queryParameters['tx_ref'], 'ord-3');
    });

    test('the default transport sends only to the provider\'s own API', () async {
      flutterwaveKeys();
      const DVBilling billing = DVBilling();
      billing.configure(flutterwave());
      const DVHttp().fake(<String, DVHttpStub>{
        'evil.example': DVHttpStub.json(<String, Object?>{'status': 'success'}),
      });
      final DVBillingFetch transport = DVBilling.transportFor(DVBillingProviderName.flutterwave);
      await expectLater(
        transport('GET', Uri.parse('https://evil.example/v3/payments'),
            const <String, String>{}, null),
        throwsA(isA<DVBillingError>()),
      );
      await expectLater(
        transport('GET', Uri.parse('http://api.flutterwave.com/v3/payments'),
            const <String, String>{}, null),
        throwsA(isA<DVBillingError>()),
        reason: 'a key is never sent in the clear',
      );
    });
  });
}
