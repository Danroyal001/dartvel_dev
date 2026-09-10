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
/// The third is the price. A plan declares what it costs and the price
/// identifier says where to charge it, and until those two were compared the
/// declared amount was decoration: a dashboard edit at Stripe moved the real
/// price and the application went on showing the old one.
///
/// HTTP is an injected function and so is the clock, so the provider is
/// tested without Stripe and the tolerance is tested at its edge.
library dartvel.billing.stripe;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../dartvel.dart'
    show
        BillingPlan,
        Entitlement,
        DVBillingCheckoutSession,
        DVBillingProvider,
        DVUsageMeter,
        dvBillingCustomerKey;
import 'money.dart';

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
    this.stale = false,
  });

  final String type;

  /// Whether this provider acted on the event. False is still an
  /// acknowledgement: Stripe retries an unacknowledged webhook for days.
  final bool handled;

  /// Whether the event described a moment older than one already applied to
  /// the same subscription, and was therefore ignored.
  ///
  /// Being late is not being wrong, so a stale event is acknowledged like
  /// any other. This says why nothing changed, which is otherwise
  /// indistinguishable from an event that changed nothing.
  final bool stale;
  final String? customer;
  final Set<Entitlement> granted;
  final Set<Entitlement> revoked;
}

/// `(status, body)` for an HTTP [method] request to [url] with [headers].
///
/// [body] is null for a read. It used to be a required String and the method
/// was implied, which meant a provider could only write -- and a provider
/// that cannot read cannot check what a price actually costs before sending
/// somebody to pay it.
typedef DVBillingFetch = Future<(int, String)> Function(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
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
    this.meters = const <String, String>{},
    DVBillingFetch? fetch,
    DateTime Function()? clock,
    this.tolerance = const Duration(minutes: 5),
  })  : _secretKey = secretKey,
        _webhookSecret = webhookSecret,
        _fetch = fetch ?? _noNetwork,
        _clock = clock ?? DateTime.now;

  final String _secretKey;
  final String _webhookSecret;
  final DVBillingFetch _fetch;
  final DateTime Function() _clock;

  /// Plan id to Stripe price id.
  final Map<String, String> prices;

  /// Stripe price id to the entitlements a subscription to it grants.
  final Map<String, Set<Entitlement>> entitlements;

  /// Meter id to the Stripe billing meter's `event_name`.
  ///
  /// Empty by default, which is why recording against a meter that is not in
  /// here is an error rather than a no-op: an application counting usage
  /// nobody configured would otherwise bill for none of it, quietly, until
  /// somebody read an invoice closely.
  final Map<String, String> meters;

  final Uri successUrl;
  final Uri cancelUrl;

  /// How old a webhook signature may be. Stripe's own libraries use five
  /// minutes; older is a replay.
  final Duration tolerance;

  /// Entitlement ids held, by Stripe customer id.
  final Map<String, Set<String>> _grants = <String, Set<String>>{};

  /// The `created` of the newest event applied, by subscription id.
  final Map<String, int> _appliedAt = <String, int>{};

  static const String _host = 'api.stripe.com';

  static Future<(int, String)> _noNetwork(
          String m, Uri u, Map<String, String> h, String? b) =>
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
    await _assertPriceAgrees(plan, price);

    final Map<String, String> form = <String, String>{
      'mode': 'subscription',
      'line_items[0][price]': price,
      'line_items[0][quantity]': '1',
      'success_url': successUrl.toString(),
      'cancel_url': cancelUrl.toString(),
      'client_reference_id': dvBillingCustomerKey(customer),
    };
    // Only when there is one. A Stripe price can carry its own default
    // trial, and sending a zero would cancel it silently -- saying nothing
    // leaves that decision where somebody made it.
    if (plan.trialDays > 0) {
      form['subscription_data[trial_period_days]'] = '${plan.trialDays}';
    }
    final String body = form.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final Map<String, Object?> json =
        await _request('POST', '/v1/checkout/sessions', body);
    final Object? url = json['url'];
    return DVBillingCheckoutSession(
      id: '${json['id'] ?? ''}',
      plan: plan,
      customer: customer,
      createdAt: _clock().toUtc(),
      checkoutUrl: url is String ? Uri.tryParse(url) : null,
    );
  }

  /// Refuses a checkout when Stripe would charge something other than what
  /// the plan says it costs.
  ///
  /// The failure this stops is quiet on both sides. The application renders
  /// the plan's own price, so the number a customer reads comes from the
  /// declaration; the charge comes from the identifier in [prices], which
  /// somebody can repoint or reprice in the Stripe dashboard without
  /// touching a line of code. Nothing then disagrees out loud -- the
  /// checkout opens, the card is charged, and the receipt is the first place
  /// the two numbers appear together.
  ///
  /// A plan whose `priceMinorUnits` is zero is declaring that it has no unit
  /// price: free, or billed by the meter. There is nothing to compare and no
  /// request is made.
  Future<void> _assertPriceAgrees(BillingPlan plan, String priceId) async {
    if (plan.priceMinorUnits == 0) return;
    final DVMoney declared =
        DVMoney(amount: plan.priceMinorUnits, currency: plan.currency);

    final Map<String, Object?> price =
        await _request('GET', '/v1/prices/$priceId', null);
    final Object? amount = price['unit_amount'];
    final Object? currency = price['currency'];
    if (amount is! int ||
        amount < 0 ||
        currency is! String ||
        !_isCurrencyCode(currency)) {
      // unit_amount is null on tiered and metered prices. Passing that as
      // "nothing to compare" would wave through the exact mismatch this
      // exists to catch, so the contradiction is the error.
      throw DVBillingError(
        'Plan "${plan.id}" declares $declared, but Stripe price $priceId has '
        'no single unit amount -- a tiered or metered price is charged per '
        'use rather than per subscription. Set priceMinorUnits to 0 for a '
        'metered plan, or point the plan at a fixed price.',
      );
    }

    final DVMoney charged = DVMoney(amount: amount, currency: currency);
    if (charged != declared) {
      throw DVBillingError(
        'Plan "${plan.id}" declares $declared and Stripe price $priceId '
        'charges $charged. No checkout was created, because the customer '
        'would have been shown one number and billed another.',
      );
    }
  }

  static bool _isCurrencyCode(String value) =>
      RegExp(r'^[A-Za-z]{3}$').hasMatch(value);

  @override
  Future<void> recordUsage({
    required Object customer,
    required DVUsageMeter meter,
    required int quantity,
    required String idempotencyKey,
    DateTime? at,
  }) async {
    final String? eventName = meters[meter.id];
    if (eventName == null) {
      throw DVBillingError(
        'Meter "${meter.id}" has no Stripe event name configured, so this '
        'usage would be counted by the application and billed by nobody. '
        'Add it to the provider meters map.',
      );
    }
    if (quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'usage is something that happened, so it is a positive number',
      );
    }

    final DateTime when = (at ?? _clock()).toUtc();
    // Stripe counts one event per identifier, so the caller's key is what
    // makes a redelivered job harmless rather than expensive.
    final Map<String, String> form = <String, String>{
      'event_name': eventName,
      'identifier': idempotencyKey,
      'timestamp': '${when.millisecondsSinceEpoch ~/ 1000}',
      'payload[stripe_customer_id]': dvBillingCustomerKey(customer),
      'payload[value]': '$quantity',
    };
    await _request(
      'POST',
      '/v1/billing/meter_events',
      form.entries
          .map((MapEntry<String, String> e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'),
    );
  }

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) async =>
      _grants[dvBillingCustomerKey(customer)]?.contains(entitlement.id) ?? false;

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
    // Seconds since the epoch, and the only ordering Stripe gives us.
    final Object? createdRaw = decoded['created'];
    final int? created =
        createdRaw is int ? createdRaw : int.tryParse('${createdRaw ?? ''}');

    switch (type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted':
        if (object is! Map) {
          throw DVBillingError('A $type event carried no subscription.');
        }
        return _applySubscription(type, object, created);
      default:
        return DVBillingWebhookResult(type: type, handled: false);
    }
  }

  DVBillingWebhookResult _applySubscription(
      String type, Map<Object?, Object?> sub, int? created) {
    final String customer = '${sub['customer'] ?? ''}';
    final String status = '${sub['status'] ?? ''}';

    // Stripe does not guarantee delivery order, and a retry of a failed
    // delivery lands after whatever was sent while it was failing. Applied
    // in arrival order, a stale "active" behind a cancellation hands the
    // entitlement back to someone who stopped paying -- signed, genuine,
    // answered with a 200, and visible nowhere.
    //
    // Per subscription, because two subscriptions move independently and one
    // high-water mark for the provider would drop every event for a
    // subscription that happened to be quiet. Strictly older is stale:
    // created is whole seconds, so an update and the deletion that follows
    // it share one, and refusing the second would leave the subscription
    // looking alive.
    final String subscriptionKey = '${sub['id'] ?? customer}';
    if (created != null) {
      final int? applied = _appliedAt[subscriptionKey];
      if (applied != null && created < applied) {
        return DVBillingWebhookResult(
          type: type,
          handled: false,
          stale: true,
          customer: customer,
        );
      }
      _appliedAt[subscriptionKey] = created;
    }
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

  Future<Map<String, Object?>> _request(
      String method, String path, String? body) async {
    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $_secretKey',
    };
    // Only a request with a body declares one. Stripe reads a form-encoded
    // content type on a GET as a malformed request rather than ignoring it.
    if (body != null) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    final (int status, String responseBody) = await _fetch(
      method,
      Uri.https(_host, path),
      headers,
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
