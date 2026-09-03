/// Paddle as a billing provider: transactions and signed webhooks.
///
/// The same two boundaries as Stripe. The request that creates a checkout
/// carries the API key and nothing echoes it, and a webhook is believed only
/// when its Paddle-Signature is right. Paddle's scheme differs in the
/// details -- `ts=<unix>;h1=<hex>`, HMAC-SHA256 over "<ts>:<payload>" -- and
/// the details are what a copy of the Stripe verifier would get wrong while
/// still looking like it verified.
library dartvel.billing.paddle;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../dartvel.dart' show BillingPlan, Entitlement, DVBillingCheckoutSession, DVBillingProvider;
import 'stripe.dart' show DVBillingError, DVBillingWebhookResult, DVStripeFetch;

/// Paddle Billing (the v2 API) for subscriptions, with entitlements kept
/// from webhooks.
class DVPaddleBillingProvider implements DVBillingProvider {
  DVPaddleBillingProvider({
    required String apiKey,
    required String webhookSecret,
    required this.prices,
    required this.entitlements,
    DVStripeFetch? fetch,
    DateTime Function()? clock,
    this.tolerance = const Duration(minutes: 5),
  })  : _apiKey = apiKey,
        _webhookSecret = webhookSecret,
        _fetch = fetch ?? _noNetwork,
        _clock = clock ?? DateTime.now;

  final String _apiKey;
  final String _webhookSecret;
  final DVStripeFetch _fetch;
  final DateTime Function() _clock;

  /// Plan id to Paddle price id.
  final Map<String, String> prices;

  /// Paddle price id to the entitlements a subscription to it grants.
  final Map<String, Set<Entitlement>> entitlements;
  final Duration tolerance;

  final Map<String, Set<String>> _grants = <String, Set<String>>{};

  static Future<(int, String)> _noNetwork(Uri u, Map<String, String> h, String b) =>
      throw const DVBillingError('No HTTP transport was configured for Paddle.');

  /// Sandbox keys talk to the sandbox. Decided from the key rather than a
  /// flag, so a sandbox key cannot be pointed at production by mistake.
  String get _host =>
      _apiKey.startsWith('pdl_sdbx_') ? 'sandbox-api.paddle.com' : 'api.paddle.com';

  @override
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) async {
    final String? price = prices[plan.id];
    if (price == null) {
      throw DVBillingError('Plan "${plan.id}" has no Paddle price configured.');
    }
    final Map<String, Object?> json = await _post('/transactions', <String, Object?>{
      'items': <Object?>[
        <String, Object?>{'price_id': price, 'quantity': 1},
      ],
      'custom_data': <String, Object?>{'customer': customer.toString()},
    });
    final Object? data = json['data'];
    final Map<Object?, Object?> txn = data is Map ? data : const <Object?, Object?>{};
    final Object? checkout = txn['checkout'];
    final Object? url = checkout is Map ? checkout['url'] : null;
    return DVBillingCheckoutSession(
      id: '${txn['id'] ?? ''}',
      plan: plan,
      customer: customer,
      createdAt: _clock().toUtc(),
      checkoutUrl: url is String ? Uri.tryParse(url) : null,
    );
  }

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) async =>
      _grants[customer.toString()]?.contains(entitlement.id) ?? false;

  Map<String, Set<String>> get grants => Map<String, Set<String>>.unmodifiable(
        <String, Set<String>>{
          for (final MapEntry<String, Set<String>> e in _grants.entries)
            e.key: Set<String>.unmodifiable(e.value),
        },
      );

  /// Verifies and applies a webhook. [signatureHeader] is `Paddle-Signature`.
  Future<DVBillingWebhookResult> handleWebhook(String payload, String signatureHeader) async {
    _verify(payload, signatureHeader);

    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const DVBillingError('The webhook payload is not JSON.');
    }
    if (decoded is! Map) throw const DVBillingError('The webhook payload is not an event.');
    final String type = '${decoded['event_type'] ?? ''}';
    final Object? data = decoded['data'];

    switch (type) {
      case 'subscription.activated':
      case 'subscription.updated':
      case 'subscription.resumed':
      case 'subscription.canceled':
      case 'subscription.paused':
      case 'subscription.past_due':
        if (data is! Map) throw DVBillingError('A $type event carried no subscription.');
        return _apply(type, data);
      default:
        return DVBillingWebhookResult(type: type, handled: false);
    }
  }

  DVBillingWebhookResult _apply(String type, Map<Object?, Object?> sub) {
    final String customer = '${sub['customer_id'] ?? ''}';
    final String status = '${sub['status'] ?? ''}';
    final Set<Entitlement> forPrices = <Entitlement>{};
    final Object? items = sub['items'];
    if (items is List) {
      for (final Object? row in items) {
        final Object? price = row is Map ? row['price'] : null;
        final String id = price is Map ? '${price['id'] ?? ''}' : '';
        forPrices.addAll(entitlements[id] ?? const <Entitlement>{});
      }
    }
    final Set<String> held = _grants.putIfAbsent(customer, () => <String>{});
    // Paddle's statuses: active and trialing pay; past_due keeps what it has
    // until Paddle decides; paused and canceled revoke.
    if (status == 'active' || status == 'trialing') {
      for (final Entitlement e in forPrices) {
        held.add(e.id);
      }
      return DVBillingWebhookResult(type: type, handled: true, customer: customer, granted: forPrices);
    }
    if (status == 'past_due') {
      return DVBillingWebhookResult(type: type, handled: true, customer: customer);
    }
    for (final Entitlement e in forPrices) {
      held.remove(e.id);
    }
    if (held.isEmpty) _grants.remove(customer);
    return DVBillingWebhookResult(type: type, handled: true, customer: customer, revoked: forPrices);
  }

  /// `ts=<unix>;h1=<hex>[;h1=<hex>]`, each h1 = HMAC-SHA256(secret, "<ts>:<payload>").
  void _verify(String payload, String header) {
    int? ts;
    final List<String> hashes = <String>[];
    for (final String part in header.split(';')) {
      final int eq = part.indexOf('=');
      if (eq <= 0) continue;
      final String key = part.substring(0, eq).trim();
      final String value = part.substring(eq + 1).trim();
      if (key == 'ts') ts = int.tryParse(value);
      if (key == 'h1' && value.isNotEmpty) hashes.add(value);
    }
    if (ts == null || hashes.isEmpty) {
      throw const DVBillingError('The webhook carries no usable Paddle signature.');
    }
    final int age = _clock().toUtc().millisecondsSinceEpoch ~/ 1000 - ts;
    if (age.abs() > tolerance.inSeconds) {
      throw const DVBillingError('The webhook signature is outside the accepted '
          'time window; a replay, or a clock that is wrong.');
    }
    final String expected = Hmac(sha256, utf8.encode(_webhookSecret))
        .convert(utf8.encode('$ts:$payload'))
        .toString();
    for (final String given in hashes) {
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

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> body) async {
    final (int status, String responseBody) = await _fetch(
      Uri.https(_host, path),
      <String, String>{
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      jsonEncode(body),
    );
    if (status == 401 || status == 403) {
      throw const DVBillingError('Paddle refused the API key. Check it is a live or '
          'sandbox key for this account, and that sandbox keys are used with '
          'sandbox prices.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } on FormatException {
      decoded = null;
    }
    if (status < 200 || status >= 300) {
      final Object? error = decoded is Map ? decoded['error'] : null;
      final String detail =
          error is Map ? '${error['detail'] ?? error['code'] ?? 'Paddle answered $status.'}' : 'Paddle answered $status.';
      throw DVBillingError(detail.replaceAll(_apiKey, '[key]'));
    }
    if (decoded is! Map) throw const DVBillingError('Paddle answered with something that is not JSON.');
    return decoded.cast<String, Object?>();
  }
}
