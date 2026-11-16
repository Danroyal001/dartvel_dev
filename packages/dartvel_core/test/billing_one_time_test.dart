// One-time orders through DV.Billing: a cart priced by the application,
// paid on the provider's hosted page, and believed only when the provider's
// own API confirms it. Bachs, Paystack and Flutterwave, each against recorded
// shapes from their API references; nothing here reaches the network.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// One request a provider sent.
class SentRequest {
  SentRequest(this.method, this.url, this.headers, this.body);
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;

  Map<String, Object?> get json => jsonDecode(body!) as Map<String, Object?>;

  String? header(String name) {
    for (final MapEntry<String, String> entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }
}

/// Stands in for the network: answers by method and path, keeps every
/// request.
class FakeNetwork {
  final List<SentRequest> sent = <SentRequest>[];
  final Map<String, (int, String)> answers = <String, (int, String)>{};

  void answer(String method, String path, int status, Object body) =>
      answers['$method $path'] = (status, jsonEncode(body));

  Future<(int, String)> call(
      String method, Uri url, Map<String, String> headers, String? body) async {
    sent.add(SentRequest(method, url, headers, body));
    return answers['$method ${url.path}'] ??
        (404, jsonEncode(<String, Object?>{'message': 'not found'}));
  }
}

final DVBillingOrder order = DVBillingOrder(
  reference: 'SD-20261115-093005',
  currency: 'NGN',
  lines: const <DVBillingOrderLine>[
    DVBillingOrderLine(name: 'Cohort retention curve', unitMinorUnits: 2500000),
    DVBillingOrderLine(name: 'Care plan', unitMinorUnits: 5000000, quantity: 2),
  ],
  customerEmail: 'ada@example.com',
  customerName: 'Ada Obi',
  successUrl: Uri.parse('https://shop.example.com/payments/return'),
  cancelUrl: Uri.parse('https://shop.example.com/cart'),
);

final DateTime now = DateTime.utc(2026, 11, 15, 9, 30, 5);
int get nowSeconds => now.millisecondsSinceEpoch ~/ 1000;

void main() {
  test('an order adds up its lines in minor units', () {
    expect(order.totalMinorUnits, 2500000 + 2 * 5000000);
    expect(order.total, DVMoney(amount: 12500000, currency: 'NGN'));
  });

  test('an order status is paid in full only for the exact amount and currency', () {
    // A payment under another reference is another order, whatever it paid.
    expect(
      DVBillingOrderStatus(reference: 'SD-other', checkoutId: 'chk', paid: true, amount: DVMoney(amount: 12500000, currency: 'NGN'))
          .paidInFull(order),
      isFalse,
    );
    final DVBillingOrderStatus paid = DVBillingOrderStatus(
      reference: order.reference,
      checkoutId: 'chk',
      paid: true,
      amount: DVMoney(amount: 12500000, currency: 'NGN'),
    );
    expect(paid.paidInFull(order), isTrue);
    expect(
      DVBillingOrderStatus(reference: order.reference, checkoutId: 'chk', paid: true, amount: DVMoney(amount: 100, currency: 'NGN'))
          .paidInFull(order),
      isFalse,
    );
    expect(
      DVBillingOrderStatus(reference: order.reference, checkoutId: 'chk', paid: true, amount: DVMoney(amount: 12500000, currency: 'USD'))
          .paidInFull(order),
      isFalse,
    );
    expect(
      DVBillingOrderStatus(reference: order.reference, checkoutId: 'chk', paid: false, amount: DVMoney(amount: 12500000, currency: 'NGN'))
          .paidInFull(order),
      isFalse,
    );
  });

  group('Bachs', () {
    const String key = 'sk_sandbox_bachs_0123456789';
    const String secret = 'whsec_bachs_signing_secret';
    late FakeNetwork network;
    late DVBachsBillingProvider bachs;

    setUp(() {
      network = FakeNetwork();
      bachs = DVBachsBillingProvider(
        secretKey: key,
        webhookSecret: secret,
        products: const <String, String>{},
        entitlements: const <String, Set<Entitlement>>{},
        successUrl: Uri.parse('https://shop.example.com/thanks'),
        cancelUrl: Uri.parse('https://shop.example.com/cart'),
        fetch: network.call,
        clock: () => now,
      );
      network.answer('POST', '/v1/checkout-sessions', 201, <String, Object?>{
        'checkout_id': 'chk_6R7s8T9u0V1w2X3y',
        'status': 'open',
        'amount': '125000.00',
        'currency': 'NGN',
        'reference': order.reference,
        'checkout_url': 'https://sandbox-checkout.bachs.io/c/V8xQ2mZpLj9RfTa',
      });
    });

    String sign(String payload, int t, {String with_ = secret}) =>
        't=$t,v1=${Hmac(sha256, utf8.encode(with_)).convert(utf8.encode('$t.$payload'))}';

    String event(String type, {String? reference, String checkout = 'chk_6R7s8T9u0V1w2X3y'}) =>
        jsonEncode(<String, Object?>{
          'id': 'evt_3ab4e0d5d27445cf8a52ab3d8cb8f0b1',
          'type': type,
          'created_at': '2026-11-15T09:31:00.000Z',
          'organization_id': 'acct_1',
          'data': <String, Object?>{
            'checkout_id': checkout,
            'reference': reference ?? order.reference,
            'status': type == 'checkout.completed' ? 'completed' : 'SUCCEEDED',
            'mode': 'payment',
            'payment_status': 'paid',
            'amount': '125000.00',
            'currency': 'NGN',
          },
        });

    test('checkoutOrder charges the order total as a decimal string, with the order as its reference', () async {
      final DVBillingOrderCheckout checkout = await bachs.checkoutOrder(order);
      expect(checkout.id, 'chk_6R7s8T9u0V1w2X3y');
      expect(checkout.url.toString(), 'https://sandbox-checkout.bachs.io/c/V8xQ2mZpLj9RfTa');
      expect(checkout.reference, order.reference);
      final SentRequest request = network.sent.single;
      expect(request.url.toString(), 'https://sandbox-api.bachs.io/v1/checkout-sessions');
      expect(request.header('authorization'), 'Bearer $key');
      // One order, one checkout: the retry after a timeout is the same one.
      expect(request.header('idempotency-key'), 'order-${order.reference}');
      expect(request.json['pricing'], <String, Object?>{'currency': 'NGN', 'amount': '125000.00'});
      expect(request.json['reference'], order.reference);
      expect((request.json['customer'] as Map)['email'], 'ada@example.com');
      // The order's reference rides on the return address: Bachs appends its
      // own checkout_id, which the sandbox fills with its page token.
      expect(request.json['success_url'], 'https://shop.example.com/payments/return?reference=${order.reference}');
      expect(request.json['cancel_url'], 'https://shop.example.com/cart');
    });

    test('a loopback return address is left out, which Bachs refuses', () async {
      await bachs.checkoutOrder(DVBillingOrder(
        reference: 'R1',
        currency: 'NGN',
        lines: const <DVBillingOrderLine>[DVBillingOrderLine(name: 'x', unitMinorUnits: 100)],
        customerEmail: 'a@b.co',
        successUrl: Uri.parse('http://127.0.0.1:8080/return'),
        cancelUrl: Uri.parse('http://localhost:8080/cart'),
      ));
      expect(network.sent.single.json.containsKey('success_url'), isFalse);
      expect(network.sent.single.json.containsKey('cancel_url'), isFalse);
    });

    test('orderStatus retrieves the checkout: completed, the amount by its digits, the reference', () async {
      network.answer('GET', '/v1/checkout-sessions/chk_6R7s8T9u0V1w2X3y', 200, <String, Object?>{
        'checkout_id': 'chk_6R7s8T9u0V1w2X3y',
        'status': 'completed',
        'payment_status': 'succeeded',
        'amount': '125000.00',
        'currency': 'NGN',
        'reference': order.reference,
        'charge': <String, Object?>{'payment_id': 'ch_e2ea4423', 'status': 'succeeded'},
      });
      final DVBillingOrderStatus status =
          await bachs.orderStatus(reference: order.reference, checkoutId: 'chk_6R7s8T9u0V1w2X3y');
      expect(status.paid, isTrue);
      expect(status.paidInFull(order), isTrue);
      expect(status.reference, order.reference);
      expect(status.transactionId, 'ch_e2ea4423');
    });

    test('an open checkout is not paid', () async {
      network.answer('GET', '/v1/checkout-sessions/chk_6R7s8T9u0V1w2X3y', 200, <String, Object?>{
        'checkout_id': 'chk_6R7s8T9u0V1w2X3y',
        'status': 'open',
        'amount': '125000.00',
        'currency': 'NGN',
        'reference': order.reference,
      });
      expect((await bachs.orderStatus(reference: order.reference, checkoutId: 'chk_6R7s8T9u0V1w2X3y')).paid, isFalse);
    });

    test('collection.succeeded and checkout.completed for an order name it, the checkout and the event', () async {
      for (final String type in <String>['collection.succeeded', 'checkout.completed']) {
        final String payload = event(type);
        final DVBillingWebhookResult result = await bachs.handleWebhook(payload, sign(payload, nowSeconds));
        expect(result.handled, isTrue, reason: type);
        expect(result.reference, order.reference, reason: type);
        expect(result.checkoutId, 'chk_6R7s8T9u0V1w2X3y', reason: type);
        expect(result.eventId, 'evt_3ab4e0d5d27445cf8a52ab3d8cb8f0b1', reason: type);
      }
    });

    test('a forged or stale order event is refused', () async {
      final String payload = event('collection.succeeded');
      await expectLater(bachs.handleWebhook(payload, sign(payload, nowSeconds, with_: 'whsec_other')), throwsA(isA<DVBillingError>()));
      await expectLater(bachs.handleWebhook(payload, sign(payload, nowSeconds - 301)), throwsA(isA<DVBillingError>()));
    });
  });

  group('Paystack', () {
    const String key = 'sk_test_paystack_0123456789';
    late FakeNetwork network;
    late DVPaystackBillingProvider paystack;

    setUp(() {
      network = FakeNetwork();
      paystack = DVPaystackBillingProvider(
        secretKey: key,
        plans: const <String, String>{'pro': 'PLN_gx2wn530m0i3w3m'},
        entitlements: const <String, Set<Entitlement>>{
          'PLN_gx2wn530m0i3w3m': <Entitlement>{Entitlement('pro')},
        },
        callbackUrl: Uri.parse('https://shop.example.com/thanks'),
        fetch: network.call,
      );
      network.answer('POST', '/transaction/initialize', 200, <String, Object?>{
        'status': true,
        'message': 'Authorization URL created',
        'data': <String, Object?>{
          'authorization_url': 'https://checkout.paystack.com/3ni8kdavz62431k',
          'access_code': '3ni8kdavz62431k',
          'reference': order.reference,
        },
      });
    });

    String sign(String payload, {String with_ = key}) =>
        Hmac(sha512, utf8.encode(with_)).convert(utf8.encode(payload)).toString();

    test('checkoutOrder initialises the total in kobo with our reference and the secret key', () async {
      final DVBillingOrderCheckout checkout = await paystack.checkoutOrder(order);
      expect(checkout.url.toString(), 'https://checkout.paystack.com/3ni8kdavz62431k');
      expect(checkout.reference, order.reference);
      final SentRequest request = network.sent.single;
      expect(request.url.toString(), 'https://api.paystack.co/transaction/initialize');
      expect(request.header('authorization'), 'Bearer $key');
      expect(request.json['amount'], 12500000);
      expect(request.json['currency'], 'NGN');
      expect(request.json['reference'], order.reference);
      expect(request.json['email'], 'ada@example.com');
      expect(request.json['callback_url'], 'https://shop.example.com/payments/return');
    });

    test('a refused initialise never repeats the secret key', () async {
      network.answer('POST', '/transaction/initialize', 401, <String, Object?>{'status': false, 'message': 'Invalid key $key'});
      await expectLater(
        paystack.checkoutOrder(order),
        throwsA(isA<DVBillingError>().having((DVBillingError error) => error.message, 'message', isNot(contains(key)))),
      );
    });

    test('orderStatus verifies by reference: success, kobo, currency', () async {
      network.answer('GET', '/transaction/verify/${order.reference}', 200, <String, Object?>{
        'status': true,
        'data': <String, Object?>{'id': 4099260516, 'status': 'success', 'reference': order.reference, 'amount': 12500000, 'currency': 'NGN'},
      });
      final DVBillingOrderStatus status = await paystack.orderStatus(reference: order.reference);
      expect(status.paidInFull(order), isTrue);
      expect(status.transactionId, '4099260516');
    });

    test('an abandoned transaction is not paid', () async {
      network.answer('GET', '/transaction/verify/${order.reference}', 200, <String, Object?>{
        'status': true,
        'data': <String, Object?>{'status': 'abandoned', 'reference': order.reference, 'amount': 12500000, 'currency': 'NGN'},
      });
      expect((await paystack.orderStatus(reference: order.reference)).paid, isFalse);
    });

    test('charge.success signed with HMAC-SHA512 of the body names the order', () async {
      final String payload = jsonEncode(<String, Object?>{
        'event': 'charge.success',
        'data': <String, Object?>{'id': 302961, 'reference': order.reference, 'amount': 12500000, 'currency': 'NGN', 'status': 'success'},
      });
      expect(paystack.signatureHeaderName.toLowerCase(), 'x-paystack-signature');
      final DVBillingWebhookResult result = await paystack.handleWebhook(payload, sign(payload));
      expect(result.handled, isTrue);
      expect(result.reference, order.reference);
    });

    test('a wrong signature is refused', () async {
      final String payload = jsonEncode(<String, Object?>{'event': 'charge.success', 'data': <String, Object?>{'reference': 'R'}});
      await expectLater(paystack.handleWebhook(payload, sign(payload, with_: 'sk_test_other')), throwsA(isA<DVBillingError>()));
      await expectLater(paystack.handleWebhook(payload, ''), throwsA(isA<DVBillingError>()));
    });

    test('a subscription charge for a plan grants its entitlements to the customer', () async {
      final String payload = jsonEncode(<String, Object?>{
        'event': 'charge.success',
        'data': <String, Object?>{
          'reference': 'sub-1',
          'status': 'success',
          'plan': <String, Object?>{'plan_code': 'PLN_gx2wn530m0i3w3m'},
          'customer': <String, Object?>{'email': 'ada@example.com'},
        },
      });
      final DVBillingWebhookResult result = await paystack.handleWebhook(payload, sign(payload));
      expect(result.customer, 'ada@example.com');
      expect(<String>{for (final Entitlement e in result.granted) e.id}, <String>{'pro'});
      expect(await paystack.hasEntitlement('ada@example.com', const Entitlement('pro')), isTrue);
    });

    test('checkout for a plan initialises the plan code for the customer email', () async {
      final DVBillingCheckoutSession session = await paystack.checkout(
        plan: const BillingPlan(id: 'pro', displayName: 'Pro', priceMinorUnits: 500000, currency: 'NGN'),
        customer: 'ada@example.com',
      );
      expect(session.checkoutUrl.toString(), 'https://checkout.paystack.com/3ni8kdavz62431k');
      expect(network.sent.single.json['plan'], 'PLN_gx2wn530m0i3w3m');
      expect(network.sent.single.json['email'], 'ada@example.com');
    });

    test('usage is not something Paystack meters', () async {
      await expectLater(
        paystack.recordUsage(customer: 'ada@example.com', meter: const DVUsageMeter('calls'), quantity: 1, idempotencyKey: 'k'),
        throwsA(isA<DVBillingError>()),
      );
    });
  });

  group('Flutterwave', () {
    const String key = 'FLWSECK_TEST-0123456789-X';
    const String hash = 'our-webhook-hash';
    late FakeNetwork network;
    late DVFlutterwaveBillingProvider flutterwave;

    setUp(() {
      network = FakeNetwork();
      flutterwave = DVFlutterwaveBillingProvider(
        secretKey: key,
        webhookHash: hash,
        plans: const <String, String>{'pro': '3807'},
        entitlements: const <String, Set<Entitlement>>{
          '3807': <Entitlement>{Entitlement('pro')},
        },
        redirectUrl: Uri.parse('https://shop.example.com/thanks'),
        fetch: network.call,
      );
      network.answer('POST', '/v3/payments', 200, <String, Object?>{
        'status': 'success',
        'message': 'Hosted Link',
        'data': <String, Object?>{'link': 'https://checkout.flutterwave.com/v3/hosted/pay/f524c1196ffda5556341'},
      });
    });

    test('checkoutOrder sends the total in naira with tx_ref and redirect_url', () async {
      final DVBillingOrderCheckout checkout = await flutterwave.checkoutOrder(order);
      expect(checkout.url.host, 'checkout.flutterwave.com');
      final SentRequest request = network.sent.single;
      expect(request.url.toString(), 'https://api.flutterwave.com/v3/payments');
      expect(request.header('authorization'), 'Bearer $key');
      expect(request.json['amount'], 125000);
      expect(request.json['tx_ref'], order.reference);
      expect(request.json['currency'], 'NGN');
      expect(request.json['redirect_url'], 'https://shop.example.com/payments/return');
      expect((request.json['customer'] as Map)['email'], 'ada@example.com');
    });

    test('orderStatus verifies by reference and reads naira as minor units', () async {
      network.answer('GET', '/v3/transactions/verify_by_reference', 200, <String, Object?>{
        'status': 'success',
        'data': <String, Object?>{'id': 288200108, 'tx_ref': order.reference, 'status': 'successful', 'amount': 125000, 'currency': 'NGN'},
      });
      final DVBillingOrderStatus status = await flutterwave.orderStatus(reference: order.reference);
      expect(network.sent.single.url.queryParameters['tx_ref'], order.reference);
      expect(status.paidInFull(order), isTrue);
    });

    test('a webhook carrying our hash in verif-hash names the order', () async {
      final String payload = jsonEncode(<String, Object?>{
        'event': 'charge.completed',
        'data': <String, Object?>{'id': 1, 'tx_ref': order.reference, 'status': 'successful', 'amount': 125000, 'currency': 'NGN'},
      });
      expect(flutterwave.signatureHeaderName.toLowerCase(), 'verif-hash');
      final DVBillingWebhookResult result = await flutterwave.handleWebhook(payload, hash);
      expect(result.handled, isTrue);
      expect(result.reference, order.reference);
    });

    test('a wrong or missing hash is refused, and every one when none is set', () async {
      final String payload = jsonEncode(<String, Object?>{'event': 'charge.completed', 'data': <String, Object?>{'tx_ref': 'R'}});
      await expectLater(flutterwave.handleWebhook(payload, 'guess'), throwsA(isA<DVBillingError>()));
      final DVFlutterwaveBillingProvider unset = DVFlutterwaveBillingProvider(
        secretKey: key,
        webhookHash: '',
        plans: const <String, String>{},
        entitlements: const <String, Set<Entitlement>>{},
        redirectUrl: Uri.parse('https://shop.example.com/thanks'),
        fetch: network.call,
      );
      await expectLater(unset.handleWebhook(payload, ''), throwsA(isA<DVBillingError>()));
    });
  });

  group('configuration', () {
    test('paystack and flutterwave are billing providers with their own secrets', () {
      final DVBillingConfig paystack = DVBillingConfig.read(<String, Object?>{
        'provider': 'paystack',
        'successUrl': 'https://shop.example.com/thanks',
        'cancelUrl': 'https://shop.example.com/cart',
      });
      expect(paystack.provider, DVBillingProviderName.paystack);
      expect(paystack.apiKeySecret, 'PAYSTACK_SECRET_KEY');
      final DVBillingConfig flutterwave = DVBillingConfig.read(<String, Object?>{
        'provider': 'flutterwave',
        'successUrl': 'https://shop.example.com/thanks',
        'cancelUrl': 'https://shop.example.com/cart',
      });
      expect(flutterwave.apiKeySecret, 'FLUTTERWAVE_SECRET_KEY');
      expect(flutterwave.webhookSecretName, 'FLUTTERWAVE_WEBHOOK_HASH');
    });
  });
}
