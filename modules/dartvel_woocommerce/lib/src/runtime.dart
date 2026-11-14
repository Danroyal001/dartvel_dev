import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dartvel_core/dartvel.dart';

import 'api.dart';
import 'checkout.dart';
import 'config.dart';
import 'models.dart';
import 'webhook.dart';

/// How a client's call reaches the application's backend.
typedef WooCommerceCarrier = Future<Object?> Function(
    String operation, Map<String, Object?> arguments);

/// The module's behaviour, in whichever environment it was compiled for.
///
/// On the backend each operation asks the store. On a device or in a
/// browser each is carried to the application's backend, which asks the
/// store: the store's keys are there and nowhere else.
final class WooCommerceRuntime {
  WooCommerceRuntime({
    this.config = const WooCommerceConfig(),
    DVModuleEnvironment? environment,
    WooCommerceCarrier? carrier,
    DateTime Function()? clock,
    this.moduleId = 'woocommerce',
  })  : environment = environment ?? DVModuleEnvironment.current,
        // ignore: prefer_initializing_formals
        _carrier = carrier,
        _clock = clock ?? DateTime.now;

  /// The runtime behind `DV.Modules.woocommerce`.
  static WooCommerceRuntime instance = WooCommerceRuntime();

  /// The topic a checkout publishes to collect what each analytics module
  /// knows about the buyer.
  static const String contextTopic = 'analytics.context';

  WooCommerceConfig config;
  final DVModuleEnvironment environment;
  String moduleId;
  final WooCommerceCarrier? _carrier;
  final DateTime Function() _clock;

  /// Orders this client has already told its own analytics modules about.
  final Set<int> _announced = <int>{};

  bool get isBackend => environment == DVModuleEnvironment.backend;

  WooCommerceCheckout get checkout => WooCommerceCheckout(config, clock: _clock);

  WooCommerceWebhook get webhook => WooCommerceWebhook(config);

  /// The typed client. The backend's alone.
  WooCommerceApi get api {
    if (!isBackend) {
      throw DVModuleUnavailable(moduleId, 'api', environment);
    }
    return WooCommerceApi(config);
  }

  Future<Object?> _carry(String operation, Map<String, Object?> arguments) =>
      (_carrier ??
          (String op, Map<String, Object?> a) =>
              DVModuleRpc.call(moduleId, op, a))(operation, arguments);

  static Map<String, Object?> _plain(Object? value) => <String, Object?>{
        if (value is Map)
          for (final MapEntry<Object?, Object?> e in value.entries)
            '${e.key}': e.value,
      };

  /// The published catalogue.
  Future<List<WooProduct>> products({
    String? search,
    int? category,
    List<int>? include,
    int? perPage,
    int? page,
  }) async {
    if (isBackend) {
      return api.products(
        search: search,
        category: category,
        include: include,
        perPage: perPage,
        page: page,
        status: 'publish',
      );
    }
    final Object? answer = await _carry('products', <String, Object?>{
      'search': ?search,
      'category': ?category,
      'include': ?include,
      'perPage': ?perPage,
      'page': ?page,
    });
    return <WooProduct>[
      if (answer is List)
        for (final Object? json in answer) WooProduct.fromJson(_plain(json)),
    ];
  }

  /// One published product, or null when there is none a shopper may see.
  Future<WooProduct?> product(int id) async {
    if (isBackend) {
      try {
        final WooProduct found = await api.product(id);
        return found.status == 'publish' ? found : null;
      } on WooCommerceException catch (error) {
        if (error.status == 404) return null;
        rethrow;
      }
    }
    final Object? answer = await _carry('product', <String, Object?>{'id': id});
    return answer is Map ? WooProduct.fromJson(_plain(answer)) : null;
  }

  /// Makes the order for a cart and answers with where to pay it.
  ///
  /// From a client the buyer's analytics context is collected first: each
  /// analytics module the application mounted adds what it knows, if the
  /// buyer's consent allows it to.
  Future<WooCheckoutSession> startCheckout({
    required List<WooCartLine> cart,
    WooAddress? billing,
    List<String> coupons = const <String>[],
    String? note,
    String? idempotencyKey,
    int? customerId,
    Map<String, Object?>? context,
  }) async {
    final String key = idempotencyKey ?? _newKey();
    if (isBackend) {
      return checkout.start(WooCheckoutRequest(
        cart: cart,
        billing: billing,
        couponCodes: coupons,
        customerNote: note,
        idempotencyKey: key,
        customerId: customerId,
        context: context ?? const <String, Object?>{},
      ));
    }
    final Object? answer = await _carry('startCheckout', <String, Object?>{
      'cart': <Object?>[for (final WooCartLine line in cart) line.toJson()],
      'billing': ?billing?.toJson(),
      if (coupons.isNotEmpty) 'coupons': coupons,
      'note': ?note,
      'idempotencyKey': key,
      'context': context ?? _collectContext(),
    });
    return WooCheckoutSession.fromJson(_plain(answer));
  }

  /// What the mounted analytics modules know about this visitor.
  Map<String, Object?> _collectContext() {
    final Map<String, Object?> context = <String, Object?>{};
    // Subscribers fill it in before publish returns.
    unawaited(dvModuleRegistry.publish(contextTopic, context));
    return context;
  }

  static String _newKey() {
    final Random random = Random.secure();
    return List<String>.generate(
        16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Where an order has got to.
  Future<WooOrderState> orderStatus(int orderId, String orderKey) async {
    if (isBackend) return checkout.status(orderId, orderKey);
    final WooOrderState state = WooOrderState.fromJson(_plain(await _carry(
        'orderStatus',
        <String, Object?>{'orderId': orderId, 'orderKey': orderKey})));
    final Map<String, Object?>? purchase = state.purchase;
    if (state.paid && purchase != null && _announced.add(orderId)) {
      // The buyer's own browser hears it too, once: a module that reports
      // in the browser as well as from the server does so now, with the
      // id the server's report carries.
      unawaited(dvModuleRegistry.publish(
        WooCommerceCheckout.purchaseTopic,
        <String, Object?>{...purchase, 'context': _collectContext()},
      ));
    }
    return state;
  }

  /// Asks about an order until it is paid or will not be, or until the
  /// configured time runs out, and yields each answer that differs from
  /// the last. A failed request is tried again at the next interval.
  Stream<WooOrderState> watchOrder(int orderId, String orderKey) async* {
    final DateTime deadline = _clock().add(config.pollTimeout);
    String? last;
    while (true) {
      try {
        final WooOrderState state = await orderStatus(orderId, orderKey);
        if (state.status != last) {
          last = state.status;
          yield state;
        }
        if (state.finished) return;
      } on WooCommerceException catch (error) {
        if (error.status == 404) rethrow;
      } on DVModuleRpcRefused {
        rethrow;
      } on Object {
        // The network. Asked again below.
      }
      if (!_clock().isBefore(deadline)) return;
      await Future<void>.delayed(config.pollInterval);
    }
  }

  /// The backend's half of a client's call.
  ///
  /// The route is public, like a shop is, so what it accepts is what a
  /// shopper may do: read the published catalogue, start a checkout with
  /// products and quantities, and ask about an order they hold the key to.
  /// Not prices, not a customer id, not anybody else's order.
  Future<Object?> dispatch(
      String operation, Map<String, Object?> arguments) async {
    Never bad(String what) =>
        throw DVModuleRpcRefused(moduleId, operation, what);
    int? integer(Object? value) => value is int ? value : null;

    switch (operation) {
      case 'products':
        final Object? include = arguments['include'];
        final int perPage = integer(arguments['perPage']) ?? 20;
        return <Object?>[
          for (final WooProduct p in await products(
            search: arguments['search'] is String
                ? arguments['search'] as String
                : null,
            category: integer(arguments['category']),
            include: include is List
                ? <int>[for (final Object? id in include.take(100)) if (id is int) id]
                : null,
            perPage: perPage < 1 || perPage > 100 ? 20 : perPage,
            page: integer(arguments['page']),
          ))
            p.toJson(),
        ];
      case 'product':
        final int? id = integer(arguments['id']);
        if (id == null) bad('a product has an id');
        return (await product(id))?.toJson();
      case 'orderStatus':
        final int? id = integer(arguments['orderId']);
        final Object? key = arguments['orderKey'];
        if (id == null || key is! String || key.length > 200) {
          bad('an order is asked about by its id and key');
        }
        return (await orderStatus(id, key)).toJson();
      case 'startCheckout':
        final Object? cart = arguments['cart'];
        if (cart is! List || cart.length > 100) bad('not a cart');
        final List<WooCartLine> lines = <WooCartLine>[];
        for (final Object? line in cart) {
          if (line is! Map ||
              line['product_id'] is! int ||
              line['quantity'] is! int) {
            bad('not a cart line');
          }
          lines.add(WooCartLine(
            productId: line['product_id'] as int,
            variationId: integer(line['variation_id']),
            quantity: line['quantity'] as int,
          ));
        }
        final Object? billing = arguments['billing'];
        if (billing != null) {
          if (billing is! Map ||
              billing.values.any((Object? v) => v is! String || v.length > 200)) {
            bad('not a billing address');
          }
        }
        final Object? coupons = arguments['coupons'];
        if (coupons != null &&
            (coupons is! List ||
                coupons.length > 10 ||
                coupons.any((Object? c) => c is! String || c.length > 100))) {
          bad('not coupon codes');
        }
        final Object? note = arguments['note'];
        if (note != null && (note is! String || note.length > 1000)) {
          bad('not a note');
        }
        final Object? key = arguments['idempotencyKey'];
        if (key is! String) bad('a checkout has an idempotency key');
        Map<String, Object?> context = const <String, Object?>{};
        final Object? given = arguments['context'];
        if (given is Map && given.isNotEmpty) {
          final String encoded;
          try {
            encoded = jsonEncode(given);
          } on Object {
            bad('not an analytics context');
          }
          if (encoded.length > 4096) bad('too much analytics context');
          final Request? request = DVModuleRpc.request;
          context = <String, Object?>{
            ...jsonDecode(encoded) as Map<String, Object?>,
            // The buyer consented to at least one analytics module, or the
            // context would be empty; where they were is part of what that
            // module reports a purchase with.
            if (request != null)
              'request': <String, Object?>{
                'ip': ?DVClientAddress.current.resolve(request)?.toString(),
                'agent': ?request.headers.get('user-agent'),
              },
          };
        }
        try {
          return (await startCheckout(
            cart: lines,
            billing: billing is Map ? WooAddress.fromJson(_plain(billing)) : null,
            coupons: coupons is List ? coupons.cast<String>() : const <String>[],
            note: note as String?,
            idempotencyKey: key,
            context: context,
          ))
              .toJson();
        } on WooCommerceException catch (error) {
          // A shopper is told their cart was refused, and why when the
          // reason is theirs. The store's own words stay on the server.
          const DVLog().warn('WooCommerce: checkout refused: $error',
              tag: 'woocommerce');
          bad(error.code == 'invalid' ? error.message : 'the store refused it');
        }
    }
    throw DVModuleRpcRefused(
        moduleId, operation, 'the module does not carry it to the backend');
  }
}
