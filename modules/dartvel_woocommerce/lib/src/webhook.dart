import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';

import 'checkout.dart';
import 'config.dart';
import 'models.dart';

/// The store's webhook, on the application's backend.
///
/// WooCommerce signs each delivery: `X-WC-Webhook-Signature` is the base64
/// of the HMAC-SHA256 of the request body with the webhook's secret. A
/// delivery whose signature does not match is not from the store and is
/// refused, and so is every delivery when no secret is configured: an
/// endpoint that confirmed unsigned payments would confirm anybody's.
final class WooCommerceWebhook {
  WooCommerceWebhook(this.config, {WooCommerceCheckout? checkout})
      : checkout = checkout ?? WooCommerceCheckout(config);

  final WooCommerceConfig config;
  final WooCommerceCheckout checkout;

  static const String signatureHeader = 'x-wc-webhook-signature';
  static const String topicHeader = 'x-wc-webhook-topic';

  /// The largest delivery read. An order is a few kilobytes.
  static const int maxBodyBytes = 1024 * 1024;

  /// The signature the store would send for [body] with [secret].
  static String sign(List<int> body, String secret) =>
      base64Encode(Hmac(sha256, utf8.encode(secret)).convert(body).bytes);

  /// Whether [signature] is the store's for [body]. Compared without
  /// stopping at the first difference.
  static bool verify(List<int> body, String? signature, String secret) {
    if (signature == null || signature.isEmpty) return false;
    final List<int> expected = utf8.encode(sign(body, secret));
    final List<int> given = utf8.encode(signature.trim());
    int difference = expected.length ^ given.length;
    for (int i = 0; i < expected.length && i < given.length; i++) {
      difference |= expected[i] ^ given[i];
    }
    return difference == 0;
  }

  static Response _answer(int status, Map<String, Object?> body) =>
      Response.json(body,
          status: status,
          headers: Headers(<String, Object?>{'cache-control': 'no-store'}));

  /// Answers one delivery.
  ///
  /// 200 for anything the store signed, whether or not it was acted on --
  /// WooCommerce disables a webhook that keeps failing, and a delivery this
  /// has no use for is not a failure. 401 for a bad signature, 503 with no
  /// secret configured.
  Future<Response> handle(Request request) async {
    final List<int> body = await request.body.bytes();
    if (body.length > maxBodyBytes) {
      return _answer(413, <String, Object?>{'error': 'too large'});
    }
    // What the store sends, unsigned, when a webhook is saved.
    if (RegExp(r'^webhook_id=\d+$')
        .hasMatch(utf8.decode(body, allowMalformed: true).trim())) {
      return _answer(200, <String, Object?>{'received': true});
    }
    final String? secret = const DVSecrets().maybeGet(config.webhookSecretName);
    if (secret == null) {
      const DVLog().error(
        'WooCommerce: a webhook arrived and ${config.webhookSecretName} is '
        'not set, so it was refused. Set it to the secret the webhook was '
        'saved with.',
        tag: 'woocommerce',
      );
      return _answer(
          503, <String, Object?>{'error': 'the webhook is not set up'});
    }
    if (!verify(body, request.headers.get(signatureHeader), secret)) {
      return _answer(401, <String, Object?>{'error': 'bad signature'});
    }

    final String topic = request.headers.get(topicHeader) ?? '';
    if (topic.startsWith('order.') && topic != 'order.deleted') {
      try {
        final Object? decoded = jsonDecode(utf8.decode(body));
        if (decoded is Map<String, Object?> && decoded['id'] != null) {
          await checkout.confirm(WooOrder.fromJson(decoded));
        }
      } on Object catch (error) {
        const DVLog().warn(
          'WooCommerce: a signed $topic delivery could not be read '
          '(${error.runtimeType}).',
          tag: 'woocommerce',
        );
      }
    }
    return _answer(200, <String, Object?>{'received': true});
  }
}
