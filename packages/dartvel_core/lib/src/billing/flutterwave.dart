/// Flutterwave as a billing provider: one-time orders on its hosted checkout
/// (Flutterwave Standard), subscriptions to its payment plans, and webhooks
/// carrying the secret hash set on its dashboard.
///
/// Flutterwave counts money in the currency's major unit (naira, not kobo),
/// takes the application's reference as `tx_ref`, and verifies a transaction
/// by it (`GET /v3/transactions/verify_by_reference?tx_ref=`). A webhook is
/// believed only when its `verif-hash` header equals the secret hash saved
/// with the webhook, compared in constant time, and no hash configured means
/// no webhook is believed. https://developer.flutterwave.com/docs.
///
/// Flutterwave has no usage metering, so [recordUsage] refuses, and invoices
/// are not read here, so [invoices] is empty.
library dartvel.billing.flutterwave;

import 'dart:convert';

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
import 'one_time.dart';
import 'webhooks.dart';

class DVFlutterwaveBillingProvider
    implements DVBillingProvider, DVBillingWebhookReceiver, DVOneTimeCheckout {
  DVFlutterwaveBillingProvider({
    required String secretKey,
    required String webhookHash,
    required this.plans,
    required this.entitlements,
    required this.redirectUrl,
    DVBillingFetch? fetch,
    Uri? apiBase,
  })  : _secretKey = secretKey,
        _webhookHash = webhookHash,
        _fetch = fetch ?? _noNetwork,
        apiBase = apiBase ?? Uri.parse('https://api.flutterwave.com');

  final String _secretKey;
  final String _webhookHash;
  final DVBillingFetch _fetch;

  /// Plan id to Flutterwave payment plan id.
  final Map<String, String> plans;

  /// Payment plan id to the entitlements a subscription to it grants.
  final Map<String, Set<Entitlement>> entitlements;

  /// Where Flutterwave sends a subscriber after paying for a plan.
  final Uri redirectUrl;

  /// Flutterwave's API; another address only for a local stand-in.
  final Uri apiBase;

  final Map<String, Set<String>> _grants = <String, Set<String>>{};

  static Future<(int, String)> _noNetwork(
          String m, Uri u, Map<String, String> h, String? b) =>
      throw const DVBillingError('No HTTP transport was configured for Flutterwave.');

  @override
  String get signatureHeaderName => 'verif-hash';

  Uri _at(String path, [Map<String, String>? query]) => apiBase.replace(
        path: '${apiBase.path.replaceAll(RegExp(r'/$'), '')}$path',
        queryParameters: query,
      );

  Future<Map<String, Object?>> _request(String method, String path,
      {Map<String, Object?>? body, Map<String, String>? query}) async {
    final (int status, String text) = await _fetch(
      method,
      _at(path, query),
      <String, String>{
        'Authorization': 'Bearer $_secretKey',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      },
      body == null ? null : jsonEncode(body),
    );
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    final Map<String, Object?> json =
        decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
    if (status < 200 || status >= 300 || json['status'] != 'success') {
      final String reason = '${json['message'] ?? 'Flutterwave answered $status.'}';
      throw DVBillingError(
          'Flutterwave refused the request (HTTP $status): ${reason.replaceAll(_secretKey, '[key]')}');
    }
    return json;
  }

  /// [minor] in [currency]'s major unit, as Flutterwave counts: a whole
  /// number when there are no minor units left over.
  static num _major(int minor, String currency) {
    final int unit = _pow10(dvCurrencyExponent(currency));
    return minor % unit == 0 ? minor ~/ unit : minor / unit;
  }

  static int _pow10(int places) {
    var value = 1;
    for (var index = 0; index < places; index++) {
      value *= 10;
    }
    return value;
  }

  Future<Uri> _pay(Map<String, Object?> body) async {
    final Map<String, Object?> json =
        await _request('POST', '/v3/payments', body: body);
    final Object? data = json['data'];
    final Uri? page = data is Map ? Uri.tryParse('${data['link'] ?? ''}') : null;
    if (page == null || !page.hasScheme) {
      throw const DVBillingError('Flutterwave gave no checkout page.');
    }
    return page;
  }

  @override
  Future<DVBillingOrderCheckout> checkoutOrder(DVBillingOrder order) async {
    final Uri page = await _pay(<String, Object?>{
      'tx_ref': order.reference,
      'amount': _major(order.totalMinorUnits, order.currency),
      'currency': order.currency,
      'redirect_url': order.successUrl.toString(),
      'customer': <String, Object?>{
        'email': order.customerEmail,
        if (order.customerName != null) 'name': order.customerName,
      },
      'customizations': <String, Object?>{'description': order.description},
      'meta': <String, Object?>{...order.metadata, 'dartvel_order': order.reference},
    });
    return DVBillingOrderCheckout(
        reference: order.reference, id: order.reference, url: page);
  }

  @override
  Future<DVBillingOrderStatus> orderStatus({
    required String reference,
    String checkoutId = '',
  }) async {
    final Map<String, Object?> json;
    try {
      json = await _request('GET', '/v3/transactions/verify_by_reference',
          query: <String, String>{'tx_ref': reference});
    } on DVBillingError {
      return DVBillingOrderStatus(
          reference: reference, checkoutId: checkoutId, paid: false);
    }
    final Object? data = json['data'];
    if (data is! Map) {
      return DVBillingOrderStatus(
          reference: reference, checkoutId: checkoutId, paid: false);
    }
    final Object? amount = data['amount'];
    final Object? currency = data['currency'];
    return DVBillingOrderStatus(
      reference: '${data['tx_ref'] ?? ''}',
      checkoutId: checkoutId.isEmpty ? reference : checkoutId,
      paid: data['status'] == 'successful',
      amount: amount is num && currency is String
          ? DVMoney(
              amount: (amount * _pow10(dvCurrencyExponent(currency))).round(),
              currency: currency)
          : null,
      transactionId: data['id'] == null ? null : '${data['id']}',
    );
  }

  @override
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) async {
    final String? planId = plans[plan.id];
    if (planId == null) {
      throw DVBillingError('Plan "${plan.id}" has no Flutterwave payment plan configured.');
    }
    final String email = dvBillingCustomerKey(customer);
    if (!email.contains('@')) {
      throw DVBillingError(
          'Flutterwave bills a customer by email address, and "$email" is not one.');
    }
    final String reference = 'plan-${plan.id}-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final Uri page = await _pay(<String, Object?>{
      'tx_ref': reference,
      'amount': _major(plan.priceMinorUnits, plan.currency),
      'currency': plan.currency,
      'redirect_url': redirectUrl.toString(),
      'payment_plan': planId,
      'customer': <String, Object?>{'email': email},
      'meta': <String, Object?>{'dartvel_plan': plan.id},
    });
    return DVBillingCheckoutSession(
      id: reference,
      plan: plan,
      customer: customer,
      createdAt: DateTime.now().toUtc(),
      checkoutUrl: page,
    );
  }

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) async =>
      _grants[dvBillingCustomerKey(customer)]?.contains(entitlement.id) ?? false;

  @override
  Future<void> recordUsage({
    required Object customer,
    required DVUsageMeter meter,
    required int quantity,
    required String idempotencyKey,
    DateTime? at,
  }) async {
    throw const DVBillingError(
        'Flutterwave does not meter usage, so there is nowhere to record it.');
  }

  @override
  Future<List<DVInvoice>> invoices(Object customer, {int limit = 20}) async =>
      const <DVInvoice>[];

  @override
  Future<DVBillingWebhookResult> handleWebhook(
      String payload, String signatureHeader) async {
    if (!_sameText(_webhookHash, signatureHeader.trim())) {
      throw const DVBillingError(
          'The webhook does not carry the secret hash, so it is not from Flutterwave.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const DVBillingError('The webhook payload is not JSON.');
    }
    if (decoded is! Map) {
      throw const DVBillingError('The webhook payload is not an event.');
    }
    final String type = '${decoded['event'] ?? decoded['event.type'] ?? ''}';
    final Object? data = decoded['data'];
    if (data is! Map) return DVBillingWebhookResult(type: type, handled: false);
    final String reference = '${data['tx_ref'] ?? data['txRef'] ?? ''}';
    final Object? customerObject = data['customer'];
    final String? email = customerObject is Map && customerObject['email'] is String
        ? customerObject['email'] as String
        : null;
    final Object? planObject = data['payment_plan'];
    final String? planId = planObject == null ? null : '$planObject';
    final Set<Entitlement> granted = <Entitlement>{};
    if (type == 'charge.completed' &&
        data['status'] == 'successful' &&
        planId != null &&
        email != null) {
      final Set<String> held = _grants.putIfAbsent(email, () => <String>{});
      for (final Entitlement entitlement
          in entitlements[planId] ?? const <Entitlement>{}) {
        if (held.add(entitlement.id)) granted.add(entitlement);
      }
    }
    return DVBillingWebhookResult(
      type: type,
      handled: reference.isNotEmpty,
      customer: email,
      granted: granted,
      reference: reference.isEmpty ? null : reference,
      checkoutId: reference.isEmpty ? null : reference,
      eventId: data['id'] == null ? null : '${data['id']}',
    );
  }
}

/// Whether [a] and [b] are the same text, compared without stopping early.
/// An empty side never matches: no secret configured believes nothing.
bool _sameText(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  var difference = a.length ^ b.length;
  for (var index = 0; index < a.length && index < b.length; index++) {
    difference |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
  }
  return difference == 0;
}
