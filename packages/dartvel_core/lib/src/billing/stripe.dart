/// Stripe as a billing provider: checkout sessions and signed webhooks.
///
/// What a real provider has to get right is not the happy path but the two
/// places money and trust cross a boundary. The request that creates a
/// checkout session carries the secret key, and nothing else must ever echo
/// it -- errors get shown and pasted. And a webhook is believed only when its
/// signature is Stripe's, checked in constant time against a timestamp
/// inside the tolerance, because an unsigned "subscription activated" is how
/// someone grants themselves a plan.
///
/// HTTP is an injected function and so is the clock, so the provider is
/// tested without Stripe and the tolerance is tested at its edge.
library dartvel.billing.stripe;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../dartvel.dart' show BillingPlan, Entitlement, DVBillingCheckoutSession, DVBillingProvider;

/// A billing operation that could not proceed, with a message safe to show.
class DVBillingError implements Exception {
  const DVBillingError(this.message);
  final String message;
  @override
  String toString() => 'DVBillingError: $message';
}

/// What a webhook did.
class DVBillingWebhookResult {
  const DVBillingWebhookResult({
    required this.type,
    required this.handled,
    this.customer,
    this.granted = const <Entitlement>{},
    this.revoked = const <Entitlement>{},
  });

  final String type;

  /// Whether this provider acted on the event. False is still an
  /// acknowledgement: Stripe retries an unacknowledged webhook for days.
  final bool handled;
  final String? customer;
  final Set<Entitlement> granted;
  final Set<Entitlement> revoked;
}

/// `(status, body)` for a POST of [body] to [url] with [headers].
typedef DVStripeFetch = Future<(int, String)> Function(
  Uri url,
  Map<String, String> headers,
  String body,
);

/// Stripe Checkout for subscriptions, with entitlements kept from webhooks.
class DVStripeBillingProvider implements DVBillingProvider {
  DVStripeBillingProvider({
    required String secretKey,
    required String webhookSecret,
    required this.prices,
    required this.entitlements,
    required this.successUrl,
    required this.cancelUrl,
    DVStripeFetch? fetch,
    DateTime Function()? clock,
    this.tolerance = const Duration(minutes: 5),
  })  : _secretKey = secretKey,
        _webhookSecret = webhookSecret,
        _fetch = fetch ?? _noNetwork,
        _clock = clock ?? DateTime.now;

  final String _secretKey;
  final String _webhookSecret;
  final DVStripeFetch _fetch;
  final DateTime Function() _clock;

  /// Plan id to Stripe price id.
  final Map<String, String> prices;

  /// Stripe price id to the entitlements a subscription to it grants.
  final Map<String, Set<Entitlement>> entitlements;

  final Uri successUrl;
  final Uri cancelUrl;

  /// How old a webhook signature may be. Stripe's own libraries use five
  /// minutes; older is a replay.
  final Duration tolerance;

  /// Entitlement ids held, by Stripe customer id.
  final Map<String, Set<String>> _grants = <String, Set<String>>{};

  static const String _host = 'api.stripe.com';

  static Future<(int, String)> _noNetwork(Uri u, Map<String, String> h, String b) =>
      throw const DVBillingError('No HTTP transport was configured for Stripe.');

  @override
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) async {
    final String? price = prices[plan.id];
    if (price == null) {
      throw DVBillingError('Plan "${plan.id}" has no Stripe price configured.');
    }

    final Map<String, String> form = <String, String>{
      'mode': 'subscription',
      'line_items[0][price]': price,
      'line_items[0][quantity]': '1',
      'success_url': successUrl.toString(),
      'cancel_url': cancelUrl.toString(),
      'client_reference_id': customer.toString(),
    };
    final String body = form.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final Map<String, Object?> json = await _post('/v1/checkout/sessions', body);
    final Object? url = json['url'];
    return DVBillingCheckoutSession(
      id: '${json['id'] ?? ''}',
      plan: plan,
      customer: customer,
      createdAt: _clock().toUtc(),
      checkoutUrl: url is String ? Uri.tryParse(url) : null,
    );
  }

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) async =>
      _grants[customer.toString()]?.contains(entitlement.id) ?? false;

  /// Who holds what, for an entitlements view.
  Map<String, Set<String>> get grants => Map<String, Set<String>>.unmodifiable(
        <String, Set<String>>{
          for (final MapEntry<String, Set<String>> e in _grants.entries)
            e.key: Set<String>.unmodifiable(e.value),
        },
      );

  /// Verifies and applies a webhook.
  ///
  /// [signatureHeader] is the `Stripe-Signature` header. A signature that
  /// does not match, or is older than [tolerance], is refused and nothing is
  /// changed. An event this provider does not act on is acknowledged with
  /// `handled: false` rather than refused, because Stripe retries an
  /// unacknowledged webhook for days.
  Future<DVBillingWebhookResult> handleWebhook(
    String payload,
    String signatureHeader,
  ) async {
    _verify(payload, signatureHeader);

    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const DVBillingError('The webhook payload is not JSON.');
    }
    if (decoded is! Map) {
      throw const DVBillingError('The webhook payload is not an event.');
    }
    final String type = '${decoded['type'] ?? ''}';
    final Object? data = decoded['data'];
    final Object? object = data is Map ? data['object'] : null;

    switch (type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted':
        if (object is! Map) {
          throw DVBillingError('A $type event carried no subscription.');
        }
        return _applySubscription(type, object);
      default:
        return DVBillingWebhookResult(type: type, handled: false);
    }
  }

  DVBillingWebhookResult _applySubscription(String type, Map<Object?, Object?> sub) {
    final String customer = '${sub['customer'] ?? ''}';
    final String status = '${sub['status'] ?? ''}';
    final Set<Entitlement> forPrices = <Entitlement>{};
    final Object? items = sub['items'];
    final Object? rows = items is Map ? items['data'] : null;
    if (rows is List) {
      for (final Object? row in rows) {
        final Object? price = row is Map ? row['price'] : null;
        final String id = price is Map ? '${price['id'] ?? ''}' : '';
        forPrices.addAll(entitlements[id] ?? const <Entitlement>{});
      }
    }

    // Only a subscription Stripe considers paying is a grant. past_due keeps
    // what it has until Stripe decides; unpaid, canceled and deleted revoke.
    final bool active = type != 'customer.subscription.deleted' &&
        (status == 'active' || status == 'trialing');
    final Set<String> held = _grants.putIfAbsent(customer, () => <String>{});
    if (active) {
      for (final Entitlement e in forPrices) {
        held.add(e.id);
      }
      return DVBillingWebhookResult(
          type: type, handled: true, customer: customer, granted: forPrices);
    }
    if (status == 'past_due') {
      return DVBillingWebhookResult(type: type, handled: true, customer: customer);
    }
    for (final Entitlement e in forPrices) {
      held.remove(e.id);
    }
    if (held.isEmpty) _grants.remove(customer);
    return DVBillingWebhookResult(
        type: type, handled: true, customer: customer, revoked: forPrices);
  }

  /// Stripe-Signature: `t=<unix>,v1=<hex>[,v1=<hex>...]`, where each v1 is
  /// HMAC-SHA256(secret, "<t>.<payload>").
  void _verify(String payload, String header) {
    int? timestamp;
    final List<String> signatures = <String>[];
    for (final String part in header.split(',')) {
      final int eq = part.indexOf('=');
      if (eq <= 0) continue;
      final String key = part.substring(0, eq).trim();
      final String value = part.substring(eq + 1).trim();
      if (key == 't') timestamp = int.tryParse(value);
      if (key == 'v1' && value.isNotEmpty) signatures.add(value);
    }
    if (timestamp == null || signatures.isEmpty) {
      throw const DVBillingError('The webhook carries no usable Stripe signature.');
    }

    final int age = _clock().toUtc().millisecondsSinceEpoch ~/ 1000 - timestamp;
    if (age.abs() > tolerance.inSeconds) {
      throw const DVBillingError('The webhook signature is outside the '
          'accepted time window; a replay, or a clock that is wrong.');
    }

    final String expected = Hmac(sha256, utf8.encode(_webhookSecret))
        .convert(utf8.encode('$timestamp.$payload'))
        .toString();
    for (final String given in signatures) {
      if (_constantTimeEquals(expected, given)) return;
    }
    throw const DVBillingError('The webhook signature does not match.');
  }

  static bool _constantTimeEquals(String a, String b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<Map<String, Object?>> _post(String path, String body) async {
    final (int status, String responseBody) = await _fetch(
      Uri.https(_host, path),
      <String, String>{
        'Authorization': 'Bearer $_secretKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    );

    if (status == 401) {
      // Stripe's own message quotes a redacted key; ours quotes nothing.
      throw const DVBillingError('Stripe refused the API key. Check the secret '
          'key is a live or test key with the right mode for this account.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } on FormatException {
      decoded = null;
    }
    if (status < 200 || status >= 300) {
      final Object? error = decoded is Map ? decoded['error'] : null;
      final String message =
          error is Map ? '${error['message'] ?? 'Stripe answered $status.'}' : 'Stripe answered $status.';
      throw DVBillingError(_scrub(message));
    }
    if (decoded is! Map) {
      throw const DVBillingError('Stripe answered with something that is not JSON.');
    }
    return decoded.cast<String, Object?>();
  }

  /// Nothing from Stripe's own text is allowed to carry the key.
  String _scrub(String message) =>
      message.contains(_secretKey) ? message.replaceAll(_secretKey, '[key]') : message;
}
