/// WooCommerce for Dartvel applications.
///
/// Mounted in `pubspec.yaml` and reached as `DV.Modules.woocommerce`:
///
/// ```yaml
/// dartvel:
///   modules:
///     woocommerce:
///       package: dartvel_woocommerce
///       backendPolicy: public
///       config:
///         storeUrl: https://shop.example.com
/// ```
///
/// A checkout is two calls: make the order and send the buyer to pay it,
/// then wait for the store to say it is paid.
///
/// ```dart
/// final checkout = await DV.Modules.woocommerce.startCheckout(
///   cart: [WooCartLine(productId: 12, quantity: 1)],
///   idempotencyKey: cart.id,
/// );
/// openLink(checkout.paymentUrl);   // however the application opens a link
/// await for (final order in DV.Modules.woocommerce
///     .watchOrder(checkout.orderId, checkout.orderKey)) {
///   if (order.paid) { /* thank them */ }
/// }
/// ```
///
/// See the package's README for every setting and the store-side setup.
library;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';

import 'src/api.dart';
import 'src/checkout.dart';
import 'src/config.dart';
import 'src/models.dart';
import 'src/runtime.dart';

export 'src/api.dart';
export 'src/checkout.dart'
    show WooCheckoutRequest, WooCheckoutSession, WooOrderState;
export 'src/config.dart';
export 'src/models.dart';
export 'src/webhook.dart';

/// Starts the module: `dartvel.module.start`, called by the generated
/// client and the generated server once the module is registered.
///
/// Settings that cannot be read are reported and leave the module without
/// a store, so its calls fail saying so: a mistake in a pubspec must not
/// stop an application starting.
void startWooCommerce(DVModule module) {
  final WooCommerceRuntime runtime = WooCommerceRuntime.instance;
  runtime.moduleId = module.id;
  final Object? settings = module.config['config'];
  if (settings is Map) {
    try {
      runtime.config = WooCommerceConfig.fromModuleConfig(<String, Object?>{
        for (final MapEntry<Object?, Object?> e in settings.entries)
          '${e.key}': e.value,
      });
    } on ArgumentError catch (error) {
      const DVLog().error('${error.message}', tag: 'woocommerce');
    }
  }
}

/// A purchase the store confirmed: the payload of `commerce.purchase`, read.
final class WooPaidOrder {
  const WooPaidOrder(this.payload);

  /// The payload as published: plain maps, lists, strings and numbers.
  final Map<String, Object?> payload;

  int get orderId => payload['order_id'] is int ? payload['order_id']! as int : 0;
  String get transactionId => '${payload['transaction_id']}';
  String get currency => '${payload['currency']}';

  /// What the buyer paid.
  num get total => payload['total'] is num ? payload['total']! as num : 0;

  /// The billing email, on the backend. A client's copy has no buyer
  /// details.
  String? get email {
    final Object? customer = payload['customer'];
    return customer is Map && customer['email'] is String
        ? customer['email'] as String
        : null;
  }
}

/// `DV.Modules.woocommerce`.
///
/// The store's keys exist only on the application's backend. From a device
/// or a browser, [products], [product], [startCheckout], [orderStatus] and
/// [watchOrder] are carried there; [api] is the backend's alone.
final class WooCommerce {
  const WooCommerce();

  WooCommerceRuntime get _runtime => WooCommerceRuntime.instance;

  /// Sets the module up in code instead of, or on top of, the mount's
  /// `config:`. The same settings either way.
  void configure(WooCommerceConfig config) => _runtime.config = config;

  /// The typed REST API v3 client: products, orders, customers, coupons.
  ///
  /// The backend's alone. On a device or in a browser it throws
  /// `DVModuleUnavailable`, because the keys it signs with are not there.
  WooCommerceApi get api => _runtime.api;

  /// The published catalogue, with the store's prices.
  Future<List<WooProduct>> products({
    String? search,
    int? category,
    List<int>? include,
    int? perPage,
    int? page,
  }) =>
      _runtime.products(
        search: search,
        category: category,
        include: include,
        perPage: perPage,
        page: page,
      );

  /// One published product, or null.
  Future<WooProduct?> product(int id) => _runtime.product(id);

  /// Makes the order for [cart] in the store, pending and unpaid, and
  /// answers with the store's own payment page for it.
  ///
  /// Give [idempotencyKey] a value kept with the cart: a checkout started
  /// twice with the same key -- a double tap, a retry after a timeout -- is
  /// one order. Left out, each call is a new order.
  ///
  /// The cart is products and quantities. The store prices it.
  /// [customerId] is honoured on the backend only.
  Future<WooCheckoutSession> startCheckout({
    required List<WooCartLine> cart,
    WooAddress? billing,
    List<String> coupons = const <String>[],
    String? note,
    String? idempotencyKey,
    int? customerId,
  }) =>
      _runtime.startCheckout(
        cart: cart,
        billing: billing,
        coupons: coupons,
        note: note,
        idempotencyKey: idempotencyKey,
        customerId: customerId,
      );

  /// Where an order has got to, for whoever holds its key.
  Future<WooOrderState> orderStatus(int orderId, String orderKey) =>
      _runtime.orderStatus(orderId, orderKey);

  /// Each change in an order's status until it is paid or will not be.
  ///
  /// Asking is also what confirms a payment when the store's webhook did
  /// not arrive, so a checkout that watches its order does not depend on
  /// the webhook.
  Stream<WooOrderState> watchOrder(int orderId, String orderKey) =>
      _runtime.watchOrder(orderId, orderKey);

  /// Calls [listener] for each purchase the store confirms, once per order,
  /// and returns the function that stops it.
  ///
  /// On the backend this is where an order is fulfilled: grant the access,
  /// send the receipt. It is called when the store says the order is paid
  /// -- by webhook, or when asked -- and not when the buyer comes back.
  void Function() onOrderPaid(
    FutureOr<void> Function(WooPaidOrder order) listener,
  ) =>
      dvModuleRegistry.subscribe(WooCommerceCheckout.purchaseTopic,
          (Object? payload) {
        if (payload is Map<String, Object?>) {
          return listener(WooPaidOrder(payload));
        }
      });
}
