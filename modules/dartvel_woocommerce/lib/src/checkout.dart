import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';

/// A cart on its way to being an order.
final class WooCheckoutRequest {
  const WooCheckoutRequest({
    required this.cart,
    required this.idempotencyKey,
    this.billing,
    this.customerId,
    this.couponCodes = const <String>[],
    this.customerNote,
    this.context = const <String, Object?>{},
  });

  /// Products and quantities. Never prices: the store prices an order from
  /// its own catalogue, so a buyer cannot name their own.
  final List<WooCartLine> cart;

  /// One value per cart, kept by the caller: a checkout started twice with
  /// the same key is one order.
  final String idempotencyKey;

  final WooAddress? billing;

  /// The store customer the order belongs to. The backend's to set, from
  /// whoever is signed in; a client cannot.
  final int? customerId;
  final List<String> couponCodes;
  final String? customerNote;

  /// What the analytics modules know about the buyer, kept with the order
  /// so the purchase can be reported as theirs once it is paid.
  final Map<String, Object?> context;
}

/// An order waiting to be paid, and where to pay it.
final class WooCheckoutSession {
  const WooCheckoutSession({
    required this.orderId,
    required this.orderKey,
    required this.paymentUrl,
    required this.total,
    required this.currency,
    required this.needsPayment,
  });

  factory WooCheckoutSession.fromJson(Map<String, Object?> json) =>
      WooCheckoutSession(
        orderId: json['orderId']! as int,
        orderKey: json['orderKey']! as String,
        paymentUrl: Uri.parse(json['paymentUrl']! as String),
        total: json['total']! as String,
        currency: json['currency']! as String,
        needsPayment: json['needsPayment'] == true,
      );

  final int orderId;

  /// Needed, with [orderId], to ask whether the order is paid.
  final String orderKey;

  /// The store's own payment page for this order. Send the buyer there:
  /// the store's configured gateways take the money.
  final Uri paymentUrl;
  final String total;
  final String currency;

  /// False for an order that came to nothing to pay, which has no payment
  /// page to visit.
  final bool needsPayment;

  num get totalAmount => dvWooAmount(total);

  Map<String, Object?> toJson() => <String, Object?>{
        'orderId': orderId,
        'orderKey': orderKey,
        'paymentUrl': '$paymentUrl',
        'total': total,
        'currency': currency,
        'needsPayment': needsPayment,
      };
}

/// Where an order has got to.
final class WooOrderState {
  const WooOrderState({
    required this.orderId,
    required this.status,
    required this.paid,
    required this.finished,
    required this.total,
    required this.currency,
    this.purchase,
  });

  factory WooOrderState.fromJson(Map<String, Object?> json) => WooOrderState(
        orderId: json['orderId']! as int,
        status: json['status']! as String,
        paid: json['paid'] == true,
        finished: json['finished'] == true,
        total: json['total']! as String,
        currency: json['currency']! as String,
        purchase: json['purchase'] is Map
            ? <String, Object?>{
                for (final MapEntry<Object?, Object?> e
                    in (json['purchase']! as Map<Object?, Object?>).entries)
                  '${e.key}': e.value,
              }
            : null,
      );

  final int orderId;

  /// The store's status: `pending`, `processing`, `on-hold`, `completed`,
  /// `cancelled`, `refunded`, `failed`.
  final String status;

  /// The store has the money.
  final bool paid;

  /// Nothing more will happen by itself: paid, or failed, cancelled or
  /// refunded.
  final bool finished;
  final String total;
  final String currency;

  /// For a paid order, what was bought: the transaction id, totals and
  /// items, without the buyer's details.
  final Map<String, Object?>? purchase;

  Map<String, Object?> toJson() => <String, Object?>{
        'orderId': orderId,
        'status': status,
        'paid': paid,
        'finished': finished,
        'total': total,
        'currency': currency,
        'purchase': ?purchase,
      };
}

/// Checkout through the store, on the application's backend.
///
/// An order is made in the store, pending and unpaid. The buyer is sent to
/// the store's own payment page for it, where whichever gateways the store
/// has configured take the money. The payment is confirmed by the store --
/// its webhook, or its answer when asked -- and never by the buyer arriving
/// back, which proves only that they followed a link.
final class WooCommerceCheckout {
  WooCommerceCheckout(
    this.config, {
    DateTime Function()? clock,
    Future<void> Function(String topic, Object? payload)? publish,
  })  : _clock = clock ?? DateTime.now,
        _publish = publish ??
            ((String topic, Object? payload) =>
                dvModuleRegistry.publish(topic, payload));

  final WooCommerceConfig config;
  final DateTime Function() _clock;
  final Future<void> Function(String topic, Object? payload) _publish;

  WooCommerceApi get api => WooCommerceApi(config);

  /// The topic a confirmed purchase is published to.
  static const String purchaseTopic = 'commerce.purchase';

  /// The order meta a checkout's key is kept under.
  static const String idempotencyMeta = '_dv_idempotency_key';

  /// The order meta the buyer's analytics context is kept under, as JSON.
  static const String analyticsMeta = '_dv_analytics';

  /// The order meta that says the purchase has been published.
  static const String reportedMeta = '_dv_purchase_reported';

  /// How far back an order with the same key is looked for.
  static const Duration idempotencyWindow = Duration(hours: 24);

  static final Map<String, Future<WooCheckoutSession>> _started =
      <String, Future<WooCheckoutSession>>{};
  static final Set<int> _reported = <int>{};

  /// Forgets what this process has started and reported, for tests.
  static void resetForTesting() {
    _started.clear();
    _reported.clear();
  }

  /// Makes the order for [request], or finds the one already made for its
  /// key, and answers with where to pay it.
  ///
  /// The store's API has no idempotency key of its own, so the key is kept
  /// on the order as meta data. A second request with the same key gets the
  /// first one's order: from this process's memory while it is running, and
  /// otherwise by looking through the store's orders of the last day.
  Future<WooCheckoutSession> start(WooCheckoutRequest request) {
    try {
      _validate(request);
    } on WooCommerceException catch (error, stack) {
      return Future<WooCheckoutSession>.error(error, stack);
    }
    final Future<WooCheckoutSession>? running =
        _started[request.idempotencyKey];
    if (running != null) return running;
    final Future<WooCheckoutSession> started = _start(request);
    _started[request.idempotencyKey] = started;
    // A checkout that failed may be tried again with the same key.
    unawaited(started.then<void>((_) {}, onError: (Object _) {
      _started.remove(request.idempotencyKey);
    }));
    return started;
  }

  static void _validate(WooCheckoutRequest request) {
    Never invalid(String message) =>
        throw WooCommerceException('invalid', message);
    final String key = request.idempotencyKey;
    if (key.isEmpty || key.length > 100) {
      invalid('A checkout needs an idempotency key of 1 to 100 characters.');
    }
    if (request.cart.isEmpty) invalid('The cart is empty.');
    if (request.cart.length > 100) invalid('The cart has too many lines.');
    for (final WooCartLine line in request.cart) {
      if (line.productId <= 0) invalid('A cart line names no product.');
      if (line.quantity < 1 || line.quantity > 10000) {
        invalid('A cart line\'s quantity is not between 1 and 10000.');
      }
    }
    if (request.couponCodes.length > 10) invalid('Too many coupons.');
  }

  Future<WooCheckoutSession> _start(WooCheckoutRequest request) async {
    final List<WooOrder> recent = await api.orders(
      after: _clock().toUtc().subtract(idempotencyWindow),
      perPage: 100,
    );
    for (final WooOrder order in recent) {
      if (order.meta[idempotencyMeta] == request.idempotencyKey) {
        return _session(order);
      }
    }
    final WooOrder order = await api.createOrder(WooOrderRequest(
      lineItems: request.cart,
      billing: request.billing,
      customerId: request.customerId,
      couponCodes: request.couponCodes,
      customerNote: request.customerNote,
      meta: <String, String>{
        idempotencyMeta: request.idempotencyKey,
        if (request.context.isNotEmpty)
          analyticsMeta: jsonEncode(request.context),
      },
    ));
    return _session(order);
  }

  WooCheckoutSession _session(WooOrder order) {
    final String? url = order.paymentUrl;
    final Uri? paymentUrl = url == null ? null : Uri.tryParse(url);
    if (paymentUrl == null || !paymentUrl.hasScheme) {
      throw const WooCommerceException(
        'no_payment_url',
        'The store made the order and did not say where to pay it. Its '
            'REST API answers with payment_url from WooCommerce 6.3; update '
            'the store.',
      );
    }
    return WooCheckoutSession(
      orderId: order.id,
      orderKey: order.orderKey,
      paymentUrl: paymentUrl,
      total: order.total,
      currency: order.currency,
      needsPayment: order.needsPayment,
    );
  }

  /// Where order [orderId] has got to, for whoever holds its [orderKey].
  ///
  /// Asking is also how a payment is confirmed when the store's webhook did
  /// not arrive: an order found paid here is published like one the webhook
  /// reported, once.
  Future<WooOrderState> status(int orderId, String orderKey) async {
    final WooOrder order;
    try {
      order = await api.order(orderId);
    } on WooCommerceException catch (error) {
      if (error.status == 404) throw _notFound;
      rethrow;
    }
    if (!_sameKey(order.orderKey, orderKey)) throw _notFound;
    final bool paid = isPaid(order);
    if (paid) await confirm(order);
    return WooOrderState(
      orderId: order.id,
      status: order.status,
      paid: paid,
      finished:
          paid || WooCommerceConfig.endedStatuses.contains(order.status),
      total: order.total,
      currency: order.currency,
      purchase: paid ? (purchaseOf(order)..remove('customer')..remove('context')) : null,
    );
  }

  /// The same answer for an order that does not exist and one whose key is
  /// wrong, so an order number alone tells nobody anything.
  static const WooCommerceException _notFound = WooCommerceException(
      'not_found', 'There is no such order.',
      status: 404);

  /// Compares without stopping at the first difference.
  static bool _sameKey(String actual, String given) {
    final List<int> a = utf8.encode(actual);
    final List<int> b = utf8.encode(given);
    int difference = a.length ^ b.length;
    for (int i = 0; i < a.length && i < b.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0 && actual.isNotEmpty;
  }

  /// Whether the store has the money for [order].
  bool isPaid(WooOrder order) => config.paidStatuses.contains(order.status);

  /// Publishes [order]'s purchase if it is paid and has not been published,
  /// and answers whether it did.
  ///
  /// Once per order: this process remembers, and the order is marked in the
  /// store so another server, or this one after a restart, sees that it has
  /// been done. A subscriber failing, or the mark failing to be written,
  /// does not undo a purchase that happened.
  Future<bool> confirm(WooOrder order) async {
    if (!isPaid(order)) return false;
    if (order.meta.containsKey(reportedMeta)) return false;
    if (!_reported.add(order.id)) return false;
    try {
      await _publish(purchaseTopic, purchaseOf(order));
    } on Object catch (error) {
      const DVLog().warn(
        'WooCommerce: a subscriber to $purchaseTopic failed for order '
        '${order.id} (${error.runtimeType}).',
        tag: 'woocommerce',
      );
    }
    try {
      await api.updateOrder(order.id, meta: <String, String>{
        reportedMeta: _clock().toUtc().toIso8601String(),
      });
    } on Object catch (error) {
      const DVLog().warn(
        'WooCommerce: order ${order.id} could not be marked as reported '
        '(${error is WooCommerceException ? error.code : error.runtimeType}). '
        'Another server may report it again.',
        tag: 'woocommerce',
      );
    }
    return true;
  }

  /// [order] as the payload of [purchaseTopic]: plain maps, lists, strings
  /// and numbers, so a subscriber needs none of this package's types.
  ///
  /// `value` is the items' own total, after discounts and without tax or
  /// shipping, which are beside it; `total` is what the buyer paid.
  Map<String, Object?> purchaseOf(WooOrder order) {
    Map<String, Object?> context = const <String, Object?>{};
    final String? stored = order.meta[analyticsMeta];
    if (stored != null) {
      try {
        final Object? decoded = jsonDecode(stored);
        if (decoded is Map<String, Object?>) context = decoded;
      } on FormatException {
        // Not ours, or damaged: a purchase with no context.
      }
    }
    num value = 0;
    for (final WooLineItem line in order.lineItems) {
      value += line.totalAmount;
    }
    return <String, Object?>{
      'transaction_id': '${order.id}',
      'order_id': order.id,
      'order_number': order.number,
      'currency': order.currency,
      'total': order.totalAmount,
      'value': dvWooAmount(value),
      'tax': dvWooAmount(order.totalTax),
      'shipping': dvWooAmount(order.shippingTotal),
      if (order.couponCodes.isNotEmpty) 'coupon': order.couponCodes.first,
      'paid_at':
          (order.datePaid ?? _clock()).toUtc().toIso8601String().replaceFirst('.000Z', 'Z'),
      'payment_method': order.paymentMethod,
      'items': <Object?>[
        for (final WooLineItem line in order.lineItems)
          <String, Object?>{
            'item_id': line.sku.isNotEmpty ? line.sku : '${line.productId}',
            'item_name': line.name,
            'price': dvWooAmount(
                line.quantity > 0 ? line.totalAmount / line.quantity : 0),
            'quantity': line.quantity,
          },
      ],
      'customer': <String, Object?>{
        'email': ?order.billing.email,
        'phone': ?order.billing.phone,
        'first_name': ?order.billing.firstName,
        'last_name': ?order.billing.lastName,
        'city': ?order.billing.city,
        'country': ?order.billing.country,
        'postcode': ?order.billing.postcode,
      },
      'context': context,
    };
  }
}
