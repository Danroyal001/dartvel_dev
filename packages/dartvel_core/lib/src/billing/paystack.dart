/// Paystack as a billing provider: one-time orders on its hosted checkout,
/// subscriptions to its plans, and webhooks signed with the secret key.
///
/// Paystack counts money in the currency's minor units (kobo for NGN), takes
/// the application's reference as the transaction reference, and verifies a
/// transaction by that reference (`GET /transaction/verify/:reference`). A
/// webhook is believed only when `x-paystack-signature` is the hex
/// HMAC-SHA512 of the raw body keyed with the secret key, compared in
/// constant time. https://paystack.com/docs/api/transaction and
/// /docs/payments/webhooks.
///
/// What Paystack does not do is stated rather than faked: it has no usage
/// metering, so [recordUsage] refuses, and invoices are not read here, so
/// [invoices] is empty.
library dartvel.billing.paystack;

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
import 'invoice.dart';
import 'money.dart';
import 'one_time.dart';
import 'webhooks.dart';

class DVPaystackBillingProvider
    implements DVBillingProvider, DVBillingWebhookReceiver, DVOneTimeCheckout {
  DVPaystackBillingProvider({
    required String secretKey,
    required this.plans,
    required this.entitlements,
    required this.callbackUrl,
    DVBillingFetch? fetch,
    Uri? apiBase,
  })  : _secretKey = secretKey,
        _fetch = fetch ?? _noNetwork,
        apiBase = apiBase ?? Uri.parse('https://api.paystack.co');

  final String _secretKey;
  final DVBillingFetch _fetch;

  /// Plan id to Paystack plan code (`PLN_...`).
  final Map<String, String> plans;

  /// Paystack plan code to the entitlements a subscription to it grants.
  final Map<String, Set<Entitlement>> entitlements;

  /// Where Paystack sends a subscriber after paying for a plan. Paystack
  /// appends `reference` and `trxref`.
  final Uri callbackUrl;

  /// Paystack's API; another address only for a local stand-in.
  final Uri apiBase;

  /// Entitlement ids held, by customer email, from webhooks.
  final Map<String, Set<String>> _grants = <String, Set<String>>{};

  static Future<(int, String)> _noNetwork(
          String m, Uri u, Map<String, String> h, String? b) =>
      throw const DVBillingError('No HTTP transport was configured for Paystack.');

  @override
  String get signatureHeaderName => 'x-paystack-signature';

  Uri _at(String path) => apiBase.replace(
      path: '${apiBase.path.replaceAll(RegExp(r'/$'), '')}$path');

  Future<Map<String, Object?>> _request(String method, String path,
      {Map<String, Object?>? body}) async {
    final (int status, String text) = await _fetch(
      method,
      _at(path),
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
    if (status < 200 || status >= 300 || json['status'] != true) {
      final String reason = '${json['message'] ?? 'Paystack answered $status.'}';
      throw DVBillingError(
          'Paystack refused the request (HTTP $status): ${reason.replaceAll(_secretKey, '[key]')}');
    }
    return json;
  }

  Future<Uri> _initialise(Map<String, Object?> body) async {
    final Map<String, Object?> json =
        await _request('POST', '/transaction/initialize', body: body);
    final Object? data = json['data'];
    final Uri? page = data is Map
        ? Uri.tryParse('${data['authorization_url'] ?? ''}')
        : null;
    if (page == null || !page.hasScheme) {
      throw const DVBillingError('Paystack gave no checkout page.');
    }
    return page;
  }

  @override
  Future<DVBillingOrderCheckout> checkoutOrder(DVBillingOrder order) async {
    final Uri page = await _initialise(<String, Object?>{
      'email': order.customerEmail,
      'amount': order.totalMinorUnits,
      'currency': order.currency,
      'reference': order.reference,
      'callback_url': order.successUrl.toString(),
      'metadata': <String, Object?>{
        ...order.metadata,
        'dartvel_order': order.reference,
        'description': order.description,
        if (order.customerName != null) 'customer_name': order.customerName,
        'cancel_action': order.cancelUrl.toString(),
      },
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
      json = await _request(
          'GET', '/transaction/verify/${Uri.encodeComponent(reference)}');
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
      reference: '${data['reference'] ?? ''}',
      checkoutId: checkoutId.isEmpty ? reference : checkoutId,
      paid: data['status'] == 'success',
      amount: amount is int && currency is String
          ? DVMoney(amount: amount, currency: currency)
          : null,
      transactionId: data['id'] == null ? null : '${data['id']}',
    );
  }

  @override
  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) async {
    final String? code = plans[plan.id];
    if (code == null) {
      throw DVBillingError('Plan "${plan.id}" has no Paystack plan code configured.');
    }
    final String email = dvBillingCustomerKey(customer);
    if (!email.contains('@')) {
      throw DVBillingError(
          'Paystack bills a customer by email address, and "$email" is not one.');
    }
    final Uri page = await _initialise(<String, Object?>{
      'email': email,
      'amount': plan.priceMinorUnits,
      'currency': plan.currency,
      'plan': code,
      'callback_url': callbackUrl.toString(),
      'metadata': <String, Object?>{'dartvel_plan': plan.id},
    });
    return DVBillingCheckoutSession(
      id: page.pathSegments.isEmpty ? page.toString() : page.pathSegments.last,
      plan: plan,
      customer: customer,
      createdAt: DateTime.now().toUtc(),
      checkoutUrl: page,
    );
  }

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) async =>
      _grants[dvBillingCustomerKey(customer)]?.contains(entitlement.id) ?? false;

  /// Paystack has no usage metering: refused, rather than recorded nowhere.
  @override
  Future<void> recordUsage({
    required Object customer,
    required DVUsageMeter meter,
    required int quantity,
    required String idempotencyKey,
    DateTime? at,
  }) async {
    throw const DVBillingError(
        'Paystack does not meter usage, so there is nowhere to record it.');
  }

  /// Not read from Paystack: an empty history rather than an error.
  @override
  Future<List<DVInvoice>> invoices(Object customer, {int limit = 20}) async =>
      const <DVInvoice>[];

  /// The hex HMAC-SHA512 Paystack sends for [payload].
  static String sign(String payload, String secretKey) =>
      Hmac(sha512, utf8.encode(secretKey)).convert(utf8.encode(payload)).toString();

  @override
  Future<DVBillingWebhookResult> handleWebhook(
      String payload, String signatureHeader) async {
    if (!_sameText(sign(payload, _secretKey), signatureHeader.trim())) {
      throw const DVBillingError('The webhook signature does not match.');
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
    final String type = '${decoded['event'] ?? ''}';
    final Object? data = decoded['data'];
    if (data is! Map) return DVBillingWebhookResult(type: type, handled: false);
    final Object? customerObject = data['customer'];
    final String? email = customerObject is Map && customerObject['email'] is String
        ? customerObject['email'] as String
        : null;
    final Object? plan = data['plan'];
    final String? code = plan is Map && plan['plan_code'] is String
        ? plan['plan_code'] as String
        : null;
    switch (type) {
      case 'charge.success':
      case 'subscription.create':
        final Set<Entitlement> granted = <Entitlement>{};
        if (code != null && email != null) {
          final Set<String> held = _grants.putIfAbsent(email, () => <String>{});
          for (final Entitlement entitlement
              in entitlements[code] ?? const <Entitlement>{}) {
            if (held.add(entitlement.id)) granted.add(entitlement);
          }
        }
        final String reference = '${data['reference'] ?? ''}';
        return DVBillingWebhookResult(
          type: type,
          handled: true,
          customer: email,
          granted: granted,
          reference: reference.isEmpty ? null : reference,
          checkoutId: reference.isEmpty ? null : reference,
          eventId: data['id'] == null ? null : '${data['id']}',
        );
      case 'subscription.disable':
        final Set<Entitlement> revoked = <Entitlement>{};
        if (code != null && email != null) {
          final Set<String>? held = _grants[email];
          for (final Entitlement entitlement
              in entitlements[code] ?? const <Entitlement>{}) {
            if (held?.remove(entitlement.id) ?? false) revoked.add(entitlement);
          }
        }
        return DVBillingWebhookResult(
            type: type, handled: true, customer: email, revoked: revoked);
      default:
        return DVBillingWebhookResult(type: type, handled: false);
    }
  }
}

/// Whether [a] and [b] are the same text, compared without stopping early.
bool _sameText(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  var difference = a.length ^ b.length;
  for (var index = 0; index < a.length && index < b.length; index++) {
    difference |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
  }
  return difference == 0;
}
