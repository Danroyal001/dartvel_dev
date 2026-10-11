/// Bachs as a billing provider: checkout sessions, signed webhooks,
/// subscriptions and the customer portal.
///
/// Bachs (bachs.io) is a payments and billing service for internet
/// businesses that collects by card, bank transfer and mobile money across
/// African markets and settles in local currencies including NGN. It is the
/// provider Lagos Life took payments through before 6 October 2026.
///
/// It shares Stripe's outline and none of its details, and the details are
/// where a copied integration goes wrong while still appearing to work:
///
/// * money is a decimal string at the currency's precision ("49.00"), never
///   minor units, so the price check parses rather than reads;
/// * objects come back unwrapped and lists as `items`, not under `data`;
/// * a subscription exists only once a checkout for a recurring product
///   completes, and a recurring checkout needs a customer record, so the
///   billing customer here is a Bachs `cust_` id;
/// * a webhook is signed as HMAC-SHA256 over `"<t>.<raw body>"` and carried
///   as `X-Bachs-Signature-V2: t=<unix>,v1=<hex>[,v1=<hex>]`, with one `v1`
///   per secret that is live during a rotation.
library dartvel.billing.bachs;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../dartvel.dart'
    show
        BillingPlan,
        Entitlement,
        DVBillingCheckoutSession,
        DVBillingProvider,
        DVUsageMeter,
        dvBillingCustomerKey;
import 'invoice.dart';
import 'money.dart';
import 'subscription_lifecycle.dart';
import 'webhooks.dart';

/// A checkout session as Bachs reports it, read back to confirm a payment.
class DVBachsCheckout {
  const DVBachsCheckout({
    required this.id,
    required this.status,
    required this.paymentStatus,
    this.amount,
    this.customer,
    this.plan,
  });

  final String id;

  /// `open`, `completed`, `expired` or `cancelled`.
  final String status;

  /// `succeeded`, `processing`, `failed` and the rest of Bachs' payment
  /// lifecycle; null when nothing has been attempted.
  final String? paymentStatus;

  /// What the checkout charges, null when Bachs reports an amount this
  /// cannot read exactly.
  final DVMoney? amount;

  /// The Bachs customer id, null for a guest checkout.
  final String? customer;

  /// The Dartvel plan id the checkout was opened for, null for one this
  /// provider did not open.
  final String? plan;

  /// Whether money was collected: the session completed and its payment
  /// succeeded. A redirect to the success URL proves neither, which is why
  /// this reads the session rather than trusting the return.
  bool get paid => status == 'completed' && paymentStatus == 'succeeded';

  @override
  String toString() => 'DVBachsCheckout($id, $status, $paymentStatus)';
}

/// Bachs Billing for checkouts and subscriptions, with entitlements kept
/// from webhooks.
class DVBachsBillingProvider
    implements
        DVBillingProvider,
        DVBillingWebhookReceiver,
        DVSubscriptionLifecycle {
  DVBachsBillingProvider({
    required String secretKey,
    required String webhookSecret,
    required this.products,
    required this.entitlements,
    required this.successUrl,
    required this.cancelUrl,
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

  /// Plan id to Bachs product id (`prod_...`).
  final Map<String, String> products;

  /// Bachs product id to the entitlements buying or subscribing to it grants.
  final Map<String, Set<Entitlement>> entitlements;

  /// Where Bachs sends the customer after paying. Bachs appends
  /// `?checkout_id=<id>`, which [verifyCheckout] takes.
  final Uri successUrl;

  /// Where Bachs sends a customer who abandons the checkout.
  final Uri cancelUrl;

  final Duration tolerance;

  /// What each subscription grants, by subscription id, so a plan change
  /// takes away what only the old plan gave.
  final Map<String, ({String customer, Set<String> granted})> _subscriptions =
      <String, ({String customer, Set<String> granted})>{};

  /// What each customer bought outright, by customer.
  final Map<String, Set<String>> _purchased = <String, Set<String>>{};

  /// When the newest applied event happened, by subscription id.
  final Map<String, DateTime> _appliedAt = <String, DateTime>{};

  static final Random _random = Random.secure();

  static Future<(int, String)> _noNetwork(
          String m, Uri u, Map<String, String> h, String? b) =>
      throw const DVBillingError('No HTTP transport was configured for Bachs.');

  /// Sandbox keys talk to the sandbox. Decided from the key rather than a
  /// flag, so a sandbox key cannot be pointed at production by mistake.
  String get _host => _secretKey.startsWith('sk_sandbox_')
      ? 'sandbox-api.bachs.io'
      : 'api.bachs.io';

  @override
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) async {
    final String? product = products[plan.id];
    if (product == null) {
      throw DVBillingError('Plan "${plan.id}" has no Bachs product configured.');
    }
    final String customerId = dvBillingCustomerKey(customer);
    await _assertPriceAgrees(plan, product);
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/checkout-sessions',
      body: <String, Object?>{
        'product_cart': <Object?>[
          <String, Object?>{'product_id': product, 'quantity': 1},
        ],
        'customer': <String, Object?>{'customer_id': customerId},
        'success_url': '$successUrl',
        'cancel_url': '$cancelUrl',
        'metadata': <String, Object?>{
          'dartvel_plan': plan.id,
          'dartvel_customer': customerId,
        },
      },
      // Without one, a retry after a timeout opens a second checkout and a
      // customer who pays both is charged twice.
      idempotencyKey: _idempotencyKey(),
    );
    final Object? url = json['checkout_url'];
    return DVBillingCheckoutSession(
      id: '${json['checkout_id'] ?? ''}',
      plan: plan,
      customer: customer,
      createdAt: _clock().toUtc(),
      checkoutUrl: url is String ? Uri.tryParse(url) : null,
    );
  }

  /// Reads a checkout session back from Bachs.
  ///
  /// The success redirect carries `checkout_id`, and anyone can type a URL
  /// with one in it, so a page that confirms a purchase asks Bachs rather
  /// than believing the query string. Entitlements still come from the
  /// webhook; this is for telling the customer what happened.
  Future<DVBachsCheckout> verifyCheckout(String checkoutId) async {
    final Map<String, Object?> json = await _request(
        'GET', '/v1/checkout-sessions/${Uri.encodeComponent(checkoutId)}');
    final Object? customer = json['customer'];
    final Object? metadata = json['metadata'];
    final Object? currency = json['currency'];
    final int? minor = currency is String
        ? _minorUnits('${json['amount'] ?? ''}', currency)
        : null;
    return DVBachsCheckout(
      id: '${json['checkout_id'] ?? checkoutId}',
      status: '${json['status'] ?? ''}',
      paymentStatus:
          json['payment_status'] is String ? json['payment_status'] as String : null,
      amount: minor == null ? null : DVMoney(amount: minor, currency: currency! as String),
      customer: customer is Map && customer['customer_id'] is String
          ? customer['customer_id'] as String
          : null,
      plan: metadata is Map && metadata['dartvel_plan'] is String
          ? metadata['dartvel_plan'] as String
          : null,
    );
  }

  /// Refuses a checkout when Bachs would charge something other than what
  /// the plan says it costs.
  ///
  /// Bachs gives the amount as a decimal string at the currency's precision.
  /// It is converted to minor units by the digits, never through a double,
  /// and an amount with more places than the currency has is refused: it is
  /// not a price Bachs documents, so the response is not the one this was
  /// written against.
  Future<void> _assertPriceAgrees(BillingPlan plan, String productId) async {
    if (plan.priceMinorUnits == 0 && plan.trialDays == 0) return;

    final Map<String, Object?> json = await _request(
        'GET', '/v1/products/${Uri.encodeComponent(productId)}');

    if (plan.priceMinorUnits > 0) {
      final DVMoney declared =
          DVMoney(amount: plan.priceMinorUnits, currency: plan.currency);
      final Object? price = json['price'];
      final Object? currency = price is Map ? price['currency'] : null;
      final Object? type = price is Map ? price['price_type'] : null;
      final int? amount = currency is String && type == 'fixed'
          ? _minorUnits('${price is Map ? price['amount'] ?? '' : ''}', currency)
          : null;
      if (amount == null ||
          currency is! String ||
          !RegExp(r'^[A-Za-z]{3}$').hasMatch(currency)) {
        throw DVBillingError(
          'Plan "${plan.id}" declares $declared, and Bachs product $productId '
          'reports no fixed price to compare it against.',
        );
      }
      final DVMoney charged = DVMoney(amount: amount, currency: currency);
      if (charged != declared) {
        throw DVBillingError(
          'Plan "${plan.id}" declares $declared and Bachs product $productId '
          'charges $charged. No checkout was created, because the customer '
          'would have been shown one number and billed another.',
        );
      }
    }

    _assertTrialAgrees(plan, productId, json['trial_period']);
  }

  /// Bachs keeps a trial on the product, so checking is the only reading of
  /// `trialDays` there is. Both directions are wrong: a promised fortnight
  /// that is not given is charged on day one, and a trial nobody declared
  /// gives a week away per signup, quietly.
  void _assertTrialAgrees(BillingPlan plan, String productId, Object? trial) {
    final int? configured = _trialDays(trial);
    if (configured == plan.trialDays) return;
    if (configured == null) {
      throw DVBillingError(
        'Plan "${plan.id}" declares a ${plan.trialDays}-day trial and Bachs '
        'product $productId has a trial this cannot count in days -- a month '
        'is not a fixed number of them. Express the trial in days or weeks.',
      );
    }
    throw DVBillingError(
      'Plan "${plan.id}" declares a ${plan.trialDays}-day trial and Bachs '
      'product $productId gives $configured. No checkout was created: one of '
      'these is what a customer was promised and the other is what they get.',
    );
  }

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

  /// "49.00" in USD as 4900, "4900" in JPY as 4900; null for anything that
  /// is not a non-negative decimal with at most the currency's places.
  static int? _minorUnits(String decimal, String currency) {
    final RegExpMatch? match =
        RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(decimal.trim());
    if (match == null) return null;
    final int places = dvCurrencyExponent(currency);
    final String fraction = match.group(2) ?? '';
    if (fraction.length > places) return null;
    return int.parse('${match.group(1)}${fraction.padRight(places, '0')}');
  }

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) async =>
      _held(dvBillingCustomerKey(customer)).contains(entitlement.id);

  Set<String> _held(String customer) => <String>{
        ...?_purchased[customer],
        for (final ({String customer, Set<String> granted}) subscription
            in _subscriptions.values)
          if (subscription.customer == customer) ...subscription.granted,
      };

  /// Who holds what, for an entitlements view.
  Map<String, Set<String>> get grants {
    final Set<String> customers = <String>{
      ..._purchased.keys,
      for (final ({String customer, Set<String> granted}) s
          in _subscriptions.values)
        s.customer,
    };
    return Map<String, Set<String>>.unmodifiable(<String, Set<String>>{
      for (final String customer in customers)
        if (_held(customer).isNotEmpty)
          customer: Set<String>.unmodifiable(_held(customer)),
    });
  }

  /// Not supported by Bachs, and refused rather than dropped.
  ///
  /// Bachs lists usage billing among its models but the API has no endpoint
  /// that records a meter event. Accepting the call and returning would be
  /// the worst version: usage counted by the application and billed by
  /// nobody.
  @override
  Future<void> recordUsage({
    required Object customer,
    required DVUsageMeter meter,
    required int quantity,
    required String idempotencyKey,
    DateTime? at,
  }) async {
    throw UnsupportedError(
      'Dartvel does not report usage to Bachs: the Bachs API has no endpoint '
      'that records a meter event. Use Stripe for usage-based billing.',
    );
  }

  /// Not supported by Bachs, and refused rather than guessed.
  ///
  /// Bachs sends invoice webhooks but has no endpoint that lists a
  /// customer's invoices, and its payment list cannot be filtered by
  /// customer. Listing every payment on the account and filtering here would
  /// hand one customer's page the whole account's history the moment a
  /// field was missing; the customer portal shows invoices instead.
  @override
  Future<List<DVInvoice>> invoices(Object customer, {int limit = 20}) async {
    throw UnsupportedError(
      'Bachs has no endpoint that lists one customer\'s invoices. Send the '
      'customer to customerPortalUrl, where Bachs shows them.',
    );
  }

  @override
  String get signatureHeaderName => 'X-Bachs-Signature-V2';

  @override
  Future<DVBillingWebhookResult> handleWebhook(
      String payload, String signatureHeader) async {
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
    final DateTime? occurredAt =
        DateTime.tryParse('${decoded['created_at'] ?? ''}')?.toUtc();

    switch (type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted':
        if (data is! Map) {
          throw DVBillingError('A $type event carried no subscription.');
        }
        return _applySubscription(type, data, occurredAt);
      case 'checkout.completed':
        if (data is! Map) {
          throw DVBillingError('A $type event carried no checkout.');
        }
        return _applyPurchase(type, data);
      default:
        return DVBillingWebhookResult(type: type, handled: false);
    }
  }

  DVBillingWebhookResult _applySubscription(
      String type, Map<Object?, Object?> sub, DateTime? occurredAt) {
    final Object? customerObject = sub['customer'];
    final String customer = customerObject is Map
        ? '${customerObject['customer_id'] ?? ''}'
        : '${sub['customer_id'] ?? ''}';
    if (customer.isEmpty) {
      throw DVBillingError('A $type event named no customer.');
    }
    final String status = '${sub['status'] ?? ''}';
    final String subscription =
        '${sub['subscription_id'] ?? sub['id'] ?? customer}';

    // Bachs delivers at least once and retries what failed, so a failed
    // notification lands behind whatever was sent while it was failing. In
    // arrival order that hands a cancelled customer their access back.
    if (occurredAt != null) {
      final DateTime? applied = _appliedAt[subscription];
      if (applied != null && occurredAt.isBefore(applied)) {
        return DVBillingWebhookResult(
            type: type, handled: false, stale: true, customer: customer);
      }
      _appliedAt[subscription] = occurredAt;
    }

    final Set<String> before =
        _subscriptions[subscription]?.granted ?? const <String>{};
    final Set<Entitlement> forProduct =
        entitlements['${sub['product_id'] ?? ''}'] ?? const <Entitlement>{};

    // Bachs' statuses: active and trialing pay; past_due keeps what it has
    // while Bachs retries the card; unpaid, paused and canceled end it.
    if (status == 'past_due') {
      return DVBillingWebhookResult(type: type, handled: true, customer: customer);
    }
    final Set<String> after = status == 'active' || status == 'trialing'
        ? <String>{for (final Entitlement e in forProduct) e.id}
        : <String>{};
    if (after.isEmpty) {
      _subscriptions.remove(subscription);
    } else {
      _subscriptions[subscription] = (customer: customer, granted: after);
    }
    final Set<String> stillHeld = _held(customer);
    return DVBillingWebhookResult(
      type: type,
      handled: true,
      customer: customer,
      granted: <Entitlement>{
        for (final String id in after.difference(before)) Entitlement(id),
      },
      revoked: <Entitlement>{
        for (final String id in before.difference(after))
          if (!stillHeld.contains(id)) Entitlement(id),
      },
    );
  }

  /// A one-time purchase: granted when the checkout completed with money
  /// collected. A subscription checkout is left to its subscription events,
  /// which carry the status that later revokes it.
  DVBillingWebhookResult _applyPurchase(
      String type, Map<Object?, Object?> checkout) {
    final Object? customerObject = checkout['customer'];
    final String? customer =
        customerObject is Map && customerObject['customer_id'] is String
            ? customerObject['customer_id'] as String
            : null;
    final Object? metadata = checkout['metadata'];
    final String? plan =
        metadata is Map && metadata['dartvel_plan'] is String
            ? metadata['dartvel_plan'] as String
            : null;
    final String? product = plan == null ? null : products[plan];
    if (checkout['mode'] != 'payment' ||
        checkout['payment_status'] != 'paid' ||
        customer == null ||
        product == null) {
      return DVBillingWebhookResult(type: type, handled: false, customer: customer);
    }
    final Set<Entitlement> forProduct =
        entitlements[product] ?? const <Entitlement>{};
    final Set<String> held = _purchased.putIfAbsent(customer, () => <String>{});
    final Set<Entitlement> granted = <Entitlement>{
      for (final Entitlement e in forProduct)
        if (held.add(e.id)) e,
    };
    return DVBillingWebhookResult(
        type: type, handled: true, customer: customer, granted: granted);
  }

  /// `t=<unix>,v1=<hex>[,v1=<hex>]`, each v1 = HMAC-SHA256(secret,
  /// "<t>.<payload>"). Any v1 may match: during a rotation Bachs signs with
  /// the old secret and the new, and checking only the first fails then.
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
      throw const DVBillingError('The webhook carries no usable Bachs signature.');
    }
    final int age = _clock().toUtc().millisecondsSinceEpoch ~/ 1000 - timestamp;
    if (age.abs() > tolerance.inSeconds) {
      throw const DVBillingError('The webhook signature is outside the accepted '
          'time window; a replay, or a clock that is wrong.');
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

  /// Statuses of a subscription the customer still has, in preference order.
  static const List<String> _currentStatuses = <String>[
    'active', 'trialing', 'past_due', 'unpaid', 'paused',
  ];

  Future<Map<Object?, Object?>?> _subscriptionFor(Object customer) async {
    final Map<String, Object?> json = await _request(
      'GET',
      '/v1/subscriptions',
      query: <String, String>{
        'customer_id': dvBillingCustomerKey(customer),
        'limit': '50',
      },
    );
    final Object? items = json['items'];
    final String id = dvBillingCustomerKey(customer);
    final List<Map<Object?, Object?>> subscriptions = <Map<Object?, Object?>>[
      for (final Object? row in items is List ? items : const <Object?>[])
        // Filtered at Bachs, so another customer's row here means the filter
        // did not apply, and acting on it would cancel somebody else's plan.
        if (row is Map && _customerOf(row) == id) row,
    ];
    for (final String status in _currentStatuses) {
      for (final Map<Object?, Object?> subscription in subscriptions) {
        if (subscription['status'] == status) return subscription;
      }
    }
    return subscriptions.isEmpty ? null : subscriptions.first;
  }

  static String _customerOf(Map<Object?, Object?> subscription) {
    final Object? customer = subscription['customer'];
    return customer is Map ? '${customer['customer_id'] ?? ''}' : '';
  }

  Future<String> _subscriptionIdFor(Object customer) async {
    final Object? id = (await _subscriptionFor(customer))?['id'];
    if (id is String && id.isNotEmpty) return id;
    throw DVBillingError(
      'No Bachs subscription found for customer ${dvBillingCustomerKey(customer)}.',
    );
  }

  /// Moves the subscription to [plan]'s product. Bachs invoices the
  /// difference now when [prorate], and bills the new price from the next
  /// cycle otherwise.
  @override
  Future<void> changeSubscriptionPlan({
    required Object customer,
    required BillingPlan plan,
    bool prorate = true,
  }) async {
    final String? product = products[plan.id];
    if (product == null) {
      throw DVBillingError('Plan "${plan.id}" has no Bachs product configured.');
    }
    final String id = await _subscriptionIdFor(customer);
    await _request(
      'PATCH',
      '/v1/subscriptions/${Uri.encodeComponent(id)}',
      body: <String, Object?>{
        'product_id': product,
        'proration_behavior': prorate ? 'invoice_now' : 'next_cycle',
      },
      idempotencyKey: _idempotencyKey(),
    );
  }

  /// Cancels now, or at the end of the paid period when [atPeriodEnd].
  @override
  Future<void> cancelSubscription({
    required Object customer,
    bool atPeriodEnd = false,
  }) async {
    final String id = await _subscriptionIdFor(customer);
    await _request(
      'DELETE',
      '/v1/subscriptions/${Uri.encodeComponent(id)}',
      body: <String, Object?>{'cancel_at_period_end': atPeriodEnd},
    );
  }

  /// Not offered by the Bachs API, which can cancel a subscription but not
  /// resume one or undo a scheduled cancellation.
  @override
  Future<void> resumeSubscription({required Object customer}) async {
    throw UnsupportedError(
      'The Bachs API cannot resume a subscription or undo a scheduled '
      'cancellation. Send the customer to customerPortalUrl.',
    );
  }

  /// Not offered by the Bachs API: a subscription can be paused only from
  /// the Bachs dashboard.
  @override
  Future<void> pauseSubscription({required Object customer}) async {
    throw UnsupportedError(
      'The Bachs API cannot pause a subscription. Cancel at the period end, '
      'or pause it from the Bachs dashboard.',
    );
  }

  @override
  Future<DVSubscriptionStatus> subscriptionStatus(
      {required Object customer}) async {
    final Map<Object?, Object?>? subscription = await _subscriptionFor(customer);
    if (subscription == null) return const DVSubscriptionStatus(status: 'none');
    final Object? endsAt = subscription['current_period_end'];
    return DVSubscriptionStatus(
      status: '${subscription['status'] ?? ''}',
      cancelAtPeriodEnd: subscription['cancel_at_period_end'] == true,
      currentPeriodEnd:
          endsAt is String ? DateTime.tryParse(endsAt)?.toUtc() : null,
    );
  }

  /// A fresh Bachs customer-portal session. The URL carries the session
  /// credential, so it is handed to the customer and not logged.
  @override
  Future<String> customerPortalUrl({required Object customer}) async {
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/customers/${Uri.encodeComponent(dvBillingCustomerKey(customer))}'
          '/portal-sessions',
    );
    final Object? url = json['url'];
    if (url is String && url.isNotEmpty) return url;
    throw const DVBillingError('Bachs did not return a customer portal URL.');
  }

  static String _idempotencyKey() {
    final StringBuffer key = StringBuffer('dv_');
    for (var i = 0; i < 16; i++) {
      key.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return '$key';
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    String? idempotencyKey,
  }) async {
    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $_secretKey',
      'Accept': 'application/json',
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    final (int status, String responseBody) = await _fetch(
      method,
      Uri.https(_host, path, query),
      headers,
      body == null ? null : jsonEncode(body),
    );
    if (status == 401 || status == 403) {
      throw const DVBillingError('Bachs refused the secret key. Check it is a '
          'live or sandbox key for this account with the scopes this call '
          'needs, and that sandbox keys are used with sandbox products.');
    }
    Object? decoded;
    try {
      decoded = responseBody.isEmpty ? null : jsonDecode(responseBody);
    } on FormatException {
      decoded = null;
    }
    if (status < 200 || status >= 300) {
      final String detail = decoded is Map
          ? '${decoded['detail'] ?? decoded['error_code'] ?? 'Bachs answered $status.'}'
          : 'Bachs answered $status.';
      throw DVBillingError(detail.replaceAll(_secretKey, '[key]'));
    }
    if (status == 204 || decoded == null) return const <String, Object?>{};
    if (decoded is! Map) {
      throw const DVBillingError('Bachs answered with something that is not '
          'a JSON object.');
    }
    return decoded.cast<String, Object?>();
  }
}
