// The store's webhook.
//
// WooCommerce signs each delivery: X-WC-Webhook-Signature is the base64 of
// the HMAC-SHA256 of the request body with the webhook's secret (its
// documentation, and WC_Webhook::generate_signature in its source, both
// read 14 Nov 2026). A delivery that is not signed with the secret is not
// from the store, and is not acted on.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_woocommerce/dartvel_woocommerce.dart';
import 'package:dartvel_woocommerce/src/checkout.dart';
import 'package:test/test.dart';

import 'support.dart';

String sign(String body, [String secret = webhookSecret]) => base64Encode(
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(body)).bytes);

Request delivery(
  String body, {
  String? signature,
  String topic = 'order.updated',
}) =>
    Request(
      method: 'POST',
      url: Uri.parse('https://example.com/_dartvel/woocommerce/webhook'),
      headers: Headers(<String, Object?>{
        'content-type': 'application/json',
        'x-wc-webhook-topic': topic,
        'x-wc-webhook-resource': topic.split('.').first,
        'x-wc-webhook-signature': ?signature,
      }),
      bodyStream: Stream<List<int>>.value(utf8.encode(body)),
    );

void main() {
  late List<Object?> published;
  late WooCommerceWebhook webhook;

  setUp(() {
    DVHttp.reset();
    DVSecrets.reset();
    configureSecrets();
    WooCommerceCheckout.resetForTesting();
    published = <Object?>[];
    const DVHttp().fake(<String, DVHttpStub>{
      'shop.example.com': DVHttpStub.json(orderJson(status: 'processing')),
    });
    webhook = WooCommerceWebhook(
      config,
      checkout: WooCommerceCheckout(
        config,
        clock: () => DateTime.utc(2026, 11, 14, 12),
        publish: (String topic, Object? payload) async => published.add(payload),
      ),
    );
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  final String paidOrder = jsonEncode(
      orderJson(status: 'processing', datePaid: '2026-11-14T11:58:00'));

  test('a signed delivery of a paid order confirms the purchase', () async {
    final Response response =
        await webhook.handle(delivery(paidOrder, signature: sign(paidOrder)));
    expect(response.status, 200);
    expect((published.single! as Map<String, Object?>)['transaction_id'], '981');
  });

  test('an unsigned delivery is refused and nothing is confirmed', () async {
    final Response response = await webhook.handle(delivery(paidOrder));
    expect(response.status, 401);
    expect(published, isEmpty);
  });

  test('a delivery signed with another secret is refused', () async {
    final Response response = await webhook.handle(
        delivery(paidOrder, signature: sign(paidOrder, 'somebody-elses')));
    expect(response.status, 401);
    expect(published, isEmpty);
  });

  test('a body changed after signing is refused', () async {
    final String tampered = paidOrder.replaceFirst('47500.00', '1.00');
    final Response response =
        await webhook.handle(delivery(tampered, signature: sign(paidOrder)));
    expect(response.status, 401);
    expect(published, isEmpty);
  });

  test('with no webhook secret configured every delivery is refused: an '
      'endpoint that confirmed unsigned payments would confirm anybody\'s',
      () async {
    DVSecrets.reset();
    final Response response =
        await webhook.handle(delivery(paidOrder, signature: sign(paidOrder)));
    expect(response.status, 503);
    expect(published, isEmpty);
  });

  test('the ping the store sends when a webhook is saved is answered',
      () async {
    final Response response = await webhook.handle(delivery('webhook_id=12'));
    expect(response.status, 200);
    expect(published, isEmpty);
  });

  test('an order that is not paid yet is acknowledged and not confirmed',
      () async {
    final String pending = jsonEncode(orderJson());
    final Response response =
        await webhook.handle(delivery(pending, signature: sign(pending)));
    expect(response.status, 200);
    expect(published, isEmpty);
  });

  test('a delivery about something other than an order is acknowledged',
      () async {
    const String product = '{"id":12,"name":"Website audit"}';
    final Response response = await webhook.handle(delivery(product,
        signature: sign(product), topic: 'product.updated'));
    expect(response.status, 200);
    expect(published, isEmpty);
  });

  test('the same delivery twice confirms once', () async {
    await webhook.handle(delivery(paidOrder, signature: sign(paidOrder)));
    await webhook.handle(delivery(paidOrder, signature: sign(paidOrder)));
    expect(published, hasLength(1));
  });

  test('a signed body that is not an order is acknowledged, not an error',
      () async {
    const String nonsense = 'not json';
    final Response response =
        await webhook.handle(delivery(nonsense, signature: sign(nonsense)));
    expect(response.status, 200);
    expect(published, isEmpty);
  });
}
