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

import '../../dartvel.dart'
    show
        BillingPlan,
        Entitlement,
        DVBillingCheckoutSession,
        DVBillingProvider,
        DVUsageMeter,
        dvBillingCustomerKey;
import 'money.dart';
import 'webhooks.dart';

/// Paddle Billing (the v2 API) for subscriptions, with entitlements kept
/// from webhooks.
class DVPaddleBillingProvider
    implements DVBillingProvider, DVBillingWebhookReceiver {
  DVPaddleBillingProvider({
    required String apiKey,
    required String webhookSecret,
    required this.prices,
    required this.entitlements,
    DVBillingFetch? fetch,
    DateTime Function()? clock,
    this.tolerance = const Duration(minutes: 5),
  })  : _apiKey = apiKey,
        _webhookSecret = webhookSecret,
        _fetch = fetch ?? _noNetwork,
        _clock = clock ?? DateTime.now;

  final String _apiKey;
  final String _webhookSecret;
  final DVBillingFetch _fetch;
  final DateTime Function() _clock;

  /// Plan id to Paddle price id.
  final Map<String, String> prices;

  /// Paddle price id to the entitlements a subscription to it grants.
  final Map<String, Set<Entitlement>> entitlements;
  final Duration tolerance;

  final Map<String, Set<String>> _grants = <String, Set<String>>{};

  /// When the newest applied event happened, by subscription id.
  final Map<String, DateTime> _appliedAt = <String, DateTime>{};

  static Future<(int, String)> _noNetwork(
          String m, Uri u, Map<String, String> h, String? b) =>
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
    await _assertPriceAgrees(plan, price);
    final Map<String, Object?> json = await _post('/transactions', <String, Object?>{
      'items': <Object?>[
        <String, Object?>{'price_id': price, 'quantity': 1},
      ],
      'custom_data': <String, Object?>{'customer': dvBillingCustomerKey(customer)},
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

  /// Refuses a checkout when Paddle would charge something other than what
  /// the plan says it costs.
  ///
  /// Same reason as Stripe's, with one Paddle detail worth naming: the
  /// amount comes back as a string of minor units, not a number, so parsing
  /// it is the check. A quantity like "40.00" would parse as null here
  /// rather than as forty, and the refusal that follows is right -- an
  /// amount that is not what Paddle documents means the response is not the
  /// one this code was written against.
  Future<void> _assertPriceAgrees(BillingPlan plan, String priceId) async {
    // Nothing declared, nothing to compare, no request.
    if (plan.priceMinorUnits == 0 && plan.trialDays == 0) return;

    final Map<String, Object?> json = await _get('/prices/$priceId');
    final Object? data = json['data'];

    if (plan.priceMinorUnits > 0) {
      final DVMoney declared =
          DVMoney(amount: plan.priceMinorUnits, currency: plan.currency);
      final Object? unit = data is Map ? data['unit_price'] : null;
      final int? amount =
          unit is Map ? int.tryParse('${unit['amount'] ?? ''}') : null;
      final Object? currency = unit is Map ? unit['currency_code'] : null;
      if (amount == null ||
          amount < 0 ||
          currency is! String ||
          !RegExp(r'^[A-Za-z]{3}$').hasMatch(currency)) {
        throw DVBillingError(
          'Plan "${plan.id}" declares $declared, and Paddle price $priceId '
          'reports no unit amount to compare it against.',
        );
      }

      final DVMoney charged = DVMoney(amount: amount, currency: currency);
      if (charged != declared) {
        throw DVBillingError(
          'Plan "${plan.id}" declares $declared and Paddle price $priceId '
          'charges $charged. No transaction was created, because the '
          'customer would have been shown one number and billed another.',
        );
      }
    }

    _assertTrialAgrees(plan, priceId, data is Map ? data['trial_period'] : null);
  }

  /// Paddle keeps a trial on the price, so there is nothing to send with a
  /// transaction and checking is the only reading of `trialDays` there is.
  ///
  /// Both directions are wrong and only one of them complains. A plan that
  /// promises a fortnight against a price with no trial charges on day one,
  /// and the customer says so. A price with a trial nobody declared gives
  /// away a week per signup, quietly, forever.
  void _assertTrialAgrees(BillingPlan plan, String priceId, Object? trial) {
    final int? configured = _trialDays(trial);
    if (configured == plan.trialDays) return;
    if (configured == null) {
      throw DVBillingError(
        'Plan "${plan.id}" declares a ${plan.trialDays}-day trial and Paddle '
        'price $priceId has a trial this cannot count in days -- a month is '
        'not a fixed number of them. Express the trial in days or weeks, or '
        'set the trial on the plan to 0 and let Paddle own it.',
      );
    }
    throw DVBillingError(
      'Plan "${plan.id}" declares a ${plan.trialDays}-day trial and Paddle '
      'price $priceId gives $configured. No transaction was created: one of '
      'these is what a customer was promised and the other is what they get.',
    );
  }

  /// A Paddle trial period in days, 0 for none, null when it is measured in
  /// something that is not a fixed number of days.
  static int? _trialDays(Object? trial) {
    if (trial == null) return 0;
    if (trial is! Map) return null;
    final int? frequency = int.tryParse('${trial['frequency'] ?? ''}');
    if (frequency == null) return null;
    switch ('${trial['interval'] ?? ''}') {
      case 'day':
        return frequency;
      case 'week':
        return frequency * 7;
      default:
        return null;
    }
  }

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) async =>
      _grants[dvBillingCustomerKey(customer)]?.contains(entitlement.id) ?? false;

  /// Not implemented for Paddle, and loudly so.
  ///
  /// Paddle has no endpoint shaped like Stripe's meter events: metered items
  /// are billed by adjusting a subscription's item quantities, which needs
  /// the subscription identifier and a proration decision that this provider
  /// does not carry. Rather than write that against documentation and never
  /// run it, the call refuses. Accepting it and returning would be the worst
  /// version -- an application counting usage that reaches nobody, and an
  /// invoice quietly short every month.
  @override
  Future<void> recordUsage({
    required Object customer,
    required DVUsageMeter meter,
    required int quantity,
    required String idempotencyKey,
    DateTime? at,
  }) async {
    throw UnsupportedError(
      'Dartvel does not report usage to Paddle. Paddle bills metered items '
      'by adjusting subscription item quantities rather than by recording '
      'meter events, and that path is unimplemented here. Use Stripe for '
      'usage-based billing, or update the quantities through Paddle '
      'directly.',
    );
  }

  Map<String, Set<String>> get grants => Map<String, Set<String>>.unmodifiable(
        <String, Set<String>>{
          for (final MapEntry<String, Set<String>> e in _grants.entries)
            e.key: Set<String>.unmodifiable(e.value),
        },
      );

  /// Verifies and applies a webhook. [signatureHeader] is `Paddle-Signature`.
  @override
  String get signatureHeaderName => 'Paddle-Signature';

  @override
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
    final DateTime? occurredAt =
        DateTime.tryParse('${decoded['occurred_at'] ?? ''}')?.toUtc();

    switch (type) {
      case 'subscription.activated':
      case 'subscription.updated':
      case 'subscription.resumed':
      case 'subscription.canceled':
      case 'subscription.paused':
      case 'subscription.past_due':
        if (data is! Map) throw DVBillingError('A $type event carried no subscription.');
        return _apply(type, data, occurredAt);
      default:
        return DVBillingWebhookResult(type: type, handled: false);
    }
  }

  DVBillingWebhookResult _apply(
      String type, Map<Object?, Object?> sub, DateTime? occurredAt) {
    final String customer = '${sub['customer_id'] ?? ''}';
    final String status = '${sub['status'] ?? ''}';

    // Paddle retries a delivery it did not get a 200 for, so a notification
    // that failed lands behind whatever was sent while it was failing. In
    // arrival order that hands a cancelled customer their entitlement back,
    // and nothing about it looks wrong: the signature is valid, the payload
    // is real, the endpoint answers 200.
    final String subscriptionKey = '${sub['id'] ?? customer}';
    if (occurredAt != null) {
      final DateTime? applied = _appliedAt[subscriptionKey];
      if (applied != null && occurredAt.isBefore(applied)) {
        return DVBillingWebhookResult(
          type: type,
          handled: false,
          stale: true,
          customer: customer,
        );
      }
      _appliedAt[subscriptionKey] = occurredAt;
    }
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

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> body) =>
      _request('POST', path, jsonEncode(body));

  Future<Map<String, Object?>> _get(String path) => _request('GET', path, null);

  Future<Map<String, Object?>> _request(
      String method, String path, String? body) async {
    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $_apiKey',
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    final (int status, String responseBody) = await _fetch(
      method,
      Uri.https(_host, path),
      headers,
      body,
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
