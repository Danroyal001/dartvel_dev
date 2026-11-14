import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

import 'config.dart';
import 'models.dart';

/// The store said no, could not be reached, or is not set up.
///
/// [message] is the store's own, or says what is missing. It never holds
/// the consumer key or secret.
class WooCommerceException implements Exception {
  const WooCommerceException(this.code, this.message, {this.status});

  /// The store's error code (`woocommerce_rest_cannot_view`), or one of
  /// this module's: `not_configured`, `not_https`, `unreachable`,
  /// `unreadable`, `invalid`, `no_payment_url`, `not_found`.
  final String code;
  final String message;

  /// The HTTP status, when the store answered.
  final int? status;

  @override
  String toString() =>
      'WooCommerce ${status == null ? '' : '$status '}$code: $message';
}

/// A typed client for WooCommerce's REST API v3.
///
/// **For the application's backend only.** It signs each request with the
/// store's consumer key and secret, which grant whatever the key was made
/// to grant -- reading every order, writing every product -- and so are
/// read from the server's environment and never compiled into a client.
/// `DV.Modules.woocommerce.api` throws on a device and in a browser.
///
/// Requests go to `<store>/wp-json/wc/v3` with HTTP Basic auth, which
/// WooCommerce accepts over HTTPS only; a store address that is not HTTPS
/// is refused before anything is sent.
final class WooCommerceApi {
  const WooCommerceApi(this.config);

  final WooCommerceConfig config;

  /// The name the store is declared under with `DV.Http`.
  static const String hostName = 'woocommerce';

  static String? _declaredBase;

  DVHttpHost _host() {
    final String? store = config.resolvedStoreUrl;
    if (store == null) {
      throw const WooCommerceException(
        'not_configured',
        'No store address is configured: set '
            'dartvel.modules.woocommerce.config.storeUrl, or '
            '${WooCommerceConfig.storeUrlVariable} in the server\'s '
            'environment.',
      );
    }
    final Uri? url = Uri.tryParse(store);
    final bool local = url != null &&
        (url.host == 'localhost' || url.host == '127.0.0.1');
    if (url == null || url.host.isEmpty || (url.scheme != 'https' && !local)) {
      throw const WooCommerceException(
        'not_https',
        'The store address must be https://. WooCommerce takes its keys '
            'over HTTPS only, and over plain HTTP anybody on the way could '
            'read them.',
      );
    }
    final String base = '$store/wp-json/wc/v3';
    bool declared = _declaredBase == base;
    if (declared) {
      try {
        const DVHttp().host(hostName);
      } on DVHttpUndeclaredHostException {
        declared = false;
      }
    }
    if (!declared) {
      const DVHttp().declare(
        hostName,
        DVHttpHostConfig(baseUrl: base, timeout: const Duration(seconds: 20)),
      );
      _declaredBase = base;
    }
    return const DVHttp().host(hostName);
  }

  Map<String, String> _headers() {
    const DVSecrets secrets = DVSecrets();
    final String? key = secrets.maybeGet(config.consumerKeyName);
    final String? secret = secrets.maybeGet(config.consumerSecretName);
    if (key == null || secret == null) {
      throw WooCommerceException(
        'not_configured',
        '${config.consumerKeyName} and ${config.consumerSecretName} must be '
            'set in the server\'s environment.',
      );
    }
    return <String, String>{
      'authorization': 'Basic ${base64Encode(utf8.encode('$key:$secret'))}',
      'accept': 'application/json',
    };
  }

  static String _query(Map<String, Object?> parameters) {
    final Map<String, String> present = <String, String>{
      for (final MapEntry<String, Object?> e in parameters.entries)
        if (e.value != null)
          e.key: e.value is List
              ? (e.value! as List<Object?>).join(',')
              : '${e.value}',
    };
    return present.isEmpty ? '' : '?${Uri(queryParameters: present).query}';
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?> query = const <String, Object?>{},
    Object? json,
  }) async {
    final DVHttpHost host = _host();
    final Map<String, String> headers = _headers();
    final String target = '$path${_query(query)}';
    final Response response;
    try {
      response = switch (method) {
        'GET' => await host.get(target, headers: headers),
        // Sent once. A repeated POST is a second order; the checkout has
        // its own way of not making one twice.
        'POST' =>
          await host.post(target, json: json, headers: headers, attempts: 1),
        'PUT' => await host.put(target, json: json, headers: headers),
        _ => throw ArgumentError.value(method, 'method'),
      };
    } on WooCommerceException {
      rethrow;
    } on ArgumentError {
      rethrow;
    } on Object catch (error) {
      throw WooCommerceException(
          'unreachable', 'The store could not be reached (${error.runtimeType}).');
    }
    final String text = await response.body?.text() ?? '';
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (response.status < 200 || response.status >= 300) {
      throw WooCommerceException(
        decoded is Map && decoded['code'] is String
            ? decoded['code'] as String
            : 'http_${response.status}',
        decoded is Map && decoded['message'] is String
            ? decoded['message'] as String
            : 'The store answered ${response.status}.',
        status: response.status,
      );
    }
    if (decoded == null) {
      throw WooCommerceException(
          'unreadable', 'The store\'s answer was not JSON.',
          status: response.status);
    }
    return decoded;
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in value.entries)
          '${e.key}': e.value,
      };
    }
    throw const WooCommerceException(
        'unreadable', 'The store\'s answer was not the resource asked for.');
  }

  static List<Map<String, Object?>> _list(Object? value) {
    if (value is List) {
      return <Map<String, Object?>>[
        for (final Object? item in value)
          if (item is Map) _map(item),
      ];
    }
    throw const WooCommerceException(
        'unreadable', 'The store\'s answer was not a list.');
  }

  /// The catalogue. [status] is `publish` for what a shopper may see.
  Future<List<WooProduct>> products({
    String? search,
    String? sku,
    int? category,
    List<int>? include,
    String? status,
    int? perPage,
    int? page,
  }) async =>
      <WooProduct>[
        for (final Map<String, Object?> json in _list(await _send(
          'GET',
          '/products',
          query: <String, Object?>{
            'search': search,
            'sku': sku,
            'category': category,
            'include': include,
            'status': status,
            'per_page': perPage,
            'page': page,
          },
        )))
          WooProduct.fromJson(json),
      ];

  Future<WooProduct> product(int id) async =>
      WooProduct.fromJson(_map(await _send('GET', '/products/$id')));

  /// A variable product's variations, each priced like a product.
  Future<List<WooProduct>> variations(int productId,
          {int? perPage, int? page}) async =>
      <WooProduct>[
        for (final Map<String, Object?> json in _list(await _send(
          'GET',
          '/products/$productId/variations',
          query: <String, Object?>{'per_page': perPage, 'page': page},
        )))
          WooProduct.fromJson(json),
      ];

  /// Makes an order. Not idempotent: asked twice, the store makes two. Use
  /// `DV.Modules.woocommerce.startCheckout` for a buyer's order.
  Future<WooOrder> createOrder(WooOrderRequest request) async => WooOrder
      .fromJson(_map(await _send('POST', '/orders', json: request.toJson())));

  Future<WooOrder> order(int id) async =>
      WooOrder.fromJson(_map(await _send('GET', '/orders/$id')));

  Future<List<WooOrder>> orders({
    String? status,
    int? customer,
    DateTime? after,
    DateTime? before,
    String? search,
    int? perPage,
    int? page,
  }) async =>
      <WooOrder>[
        for (final Map<String, Object?> json in _list(await _send(
          'GET',
          '/orders',
          query: <String, Object?>{
            'status': status,
            'customer': customer,
            'after': after?.toUtc().toIso8601String(),
            'before': before?.toUtc().toIso8601String(),
            'search': search,
            'per_page': perPage,
            'page': page,
          },
        )))
          WooOrder.fromJson(json),
      ];

  /// Changes an order: its [status], or meta data to add or replace.
  Future<WooOrder> updateOrder(
    int id, {
    String? status,
    Map<String, String> meta = const <String, String>{},
  }) async =>
      WooOrder.fromJson(_map(await _send(
        'PUT',
        '/orders/$id',
        json: <String, Object?>{
          'status': ?status,
          if (meta.isNotEmpty)
            'meta_data': <Object?>[
              for (final MapEntry<String, String> m in meta.entries)
                <String, Object?>{'key': m.key, 'value': m.value},
            ],
        },
      )));

  Future<List<WooCustomer>> customers({
    String? email,
    String? search,
    int? perPage,
    int? page,
  }) async =>
      <WooCustomer>[
        for (final Map<String, Object?> json in _list(await _send(
          'GET',
          '/customers',
          query: <String, Object?>{
            'email': email,
            'search': search,
            'per_page': perPage,
            'page': page,
          },
        )))
          WooCustomer.fromJson(json),
      ];

  Future<WooCustomer> customer(int id) async =>
      WooCustomer.fromJson(_map(await _send('GET', '/customers/$id')));

  Future<WooCustomer> createCustomer({
    required String email,
    String? firstName,
    String? lastName,
    WooAddress? billing,
  }) async =>
      WooCustomer.fromJson(_map(await _send(
        'POST',
        '/customers',
        json: <String, Object?>{
          'email': email,
          'first_name': ?firstName,
          'last_name': ?lastName,
          'billing': ?billing?.toJson(),
        },
      )));

  Future<List<WooCoupon>> coupons({String? code, int? perPage, int? page}) async =>
      <WooCoupon>[
        for (final Map<String, Object?> json in _list(await _send(
          'GET',
          '/coupons',
          query: <String, Object?>{
            'code': code,
            'per_page': perPage,
            'page': page,
          },
        )))
          WooCoupon.fromJson(json),
      ];

  /// The coupon with [code], or null. The store keeps codes in lower case.
  Future<WooCoupon?> couponByCode(String code) async {
    final List<WooCoupon> found =
        await coupons(code: code.trim().toLowerCase());
    return found.isEmpty ? null : found.first;
  }

  /// The store's currency code: `NGN`.
  Future<String> currency() async {
    final Map<String, Object?> current =
        _map(await _send('GET', '/data/currencies/current'));
    return '${current['code'] ?? ''}';
  }
}
