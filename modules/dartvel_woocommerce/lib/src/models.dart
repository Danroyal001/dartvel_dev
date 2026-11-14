/// The store's resources, as its REST API v3 answers with them.
///
/// Money is a string in WooCommerce's answers (`"45000.00"`), because a
/// price is a decimal and JSON numbers are not. Each is kept as the store
/// sent it, with an `...Amount` beside it for arithmetic and display.
library;

String _text(Object? value) => value == null ? '' : '$value';

String? _optional(Object? value) {
  final String text = _text(value).trim();
  return text.isEmpty ? null : text;
}

int _int(Object? value) =>
    value is int ? value : int.tryParse(_text(value)) ?? 0;

/// [value] as a number: an int when it is whole, so 45000.00 reads 45000.
num dvWooAmount(Object? value) {
  final double parsed =
      value is num ? value.toDouble() : double.tryParse(_text(value)) ?? 0;
  return parsed == parsed.roundToDouble() ? parsed.round() : parsed;
}

List<Map<String, Object?>> _maps(Object? value) => <Map<String, Object?>>[
      if (value is List)
        for (final Object? item in value)
          if (item is Map)
            <String, Object?>{
              for (final MapEntry<Object?, Object?> e in item.entries)
                '${e.key}': e.value,
            },
    ];

/// A product's picture.
final class WooImage {
  const WooImage({required this.src, this.alt});

  factory WooImage.fromJson(Map<String, Object?> json) =>
      WooImage(src: _text(json['src']), alt: _optional(json['alt']));

  final String src;
  final String? alt;

  Map<String, Object?> toJson() => <String, Object?>{'src': src, 'alt': ?alt};
}

/// A product category, as a product lists it.
final class WooCategory {
  const WooCategory({required this.id, required this.name, required this.slug});

  factory WooCategory.fromJson(Map<String, Object?> json) => WooCategory(
        id: _int(json['id']),
        name: _text(json['name']),
        slug: _text(json['slug']),
      );

  final int id;
  final String name;
  final String slug;

  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'name': name, 'slug': slug};
}

/// A product in the store's catalogue.
final class WooProduct {
  const WooProduct({
    required this.id,
    required this.name,
    this.slug = '',
    this.permalink = '',
    this.type = 'simple',
    this.status = 'publish',
    this.sku = '',
    this.price = '',
    this.regularPrice = '',
    this.salePrice = '',
    this.onSale = false,
    this.purchasable = false,
    this.stockStatus = '',
    this.shortDescription = '',
    this.description = '',
    this.images = const <WooImage>[],
    this.categories = const <WooCategory>[],
  });

  factory WooProduct.fromJson(Map<String, Object?> json) => WooProduct(
        id: _int(json['id']),
        name: _text(json['name']),
        slug: _text(json['slug']),
        permalink: _text(json['permalink']),
        type: _text(json['type']),
        status: _text(json['status']),
        sku: _text(json['sku']),
        price: _text(json['price']),
        regularPrice: _text(json['regular_price']),
        salePrice: _text(json['sale_price']),
        onSale: json['on_sale'] == true,
        purchasable: json['purchasable'] == true,
        stockStatus: _text(json['stock_status']),
        shortDescription: _text(json['short_description']),
        description: _text(json['description']),
        images: <WooImage>[
          for (final Map<String, Object?> i in _maps(json['images']))
            WooImage.fromJson(i),
        ],
        categories: <WooCategory>[
          for (final Map<String, Object?> c in _maps(json['categories']))
            WooCategory.fromJson(c),
        ],
      );

  final int id;
  final String name;
  final String slug;
  final String permalink;

  /// `simple`, `grouped`, `external` or `variable`.
  final String type;
  final String status;
  final String sku;

  /// The current price, as the store gives it.
  final String price;
  final String regularPrice;
  final String salePrice;
  final bool onSale;
  final bool purchasable;

  /// `instock`, `outofstock` or `onbackorder`.
  final String stockStatus;

  /// HTML, as the store's editor wrote it.
  final String shortDescription;
  final String description;
  final List<WooImage> images;
  final List<WooCategory> categories;

  num get priceAmount => dvWooAmount(price);
  num get regularPriceAmount => dvWooAmount(regularPrice);

  /// The same names the store uses, so a product crosses from the backend
  /// to a client and is read back with [WooProduct.fromJson].
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'slug': slug,
        'permalink': permalink,
        'type': type,
        'status': status,
        'sku': sku,
        'price': price,
        'regular_price': regularPrice,
        'sale_price': salePrice,
        'on_sale': onSale,
        'purchasable': purchasable,
        'stock_status': stockStatus,
        'short_description': shortDescription,
        'description': description,
        'images': <Object?>[for (final WooImage i in images) i.toJson()],
        'categories': <Object?>[
          for (final WooCategory c in categories) c.toJson(),
        ],
      };
}

/// A billing or shipping address.
final class WooAddress {
  const WooAddress({
    this.firstName,
    this.lastName,
    this.company,
    this.address1,
    this.address2,
    this.city,
    this.state,
    this.postcode,
    this.country,
    this.email,
    this.phone,
  });

  factory WooAddress.fromJson(Map<String, Object?> json) => WooAddress(
        firstName: _optional(json['first_name']),
        lastName: _optional(json['last_name']),
        company: _optional(json['company']),
        address1: _optional(json['address_1']),
        address2: _optional(json['address_2']),
        city: _optional(json['city']),
        state: _optional(json['state']),
        postcode: _optional(json['postcode']),
        country: _optional(json['country']),
        email: _optional(json['email']),
        phone: _optional(json['phone']),
      );

  final String? firstName;
  final String? lastName;
  final String? company;
  final String? address1;
  final String? address2;
  final String? city;
  final String? state;
  final String? postcode;

  /// The two-letter ISO 3166-1 code.
  final String? country;
  final String? email;
  final String? phone;

  Map<String, Object?> toJson() => <String, Object?>{
        'first_name': ?firstName,
        'last_name': ?lastName,
        'company': ?company,
        'address_1': ?address1,
        'address_2': ?address2,
        'city': ?city,
        'state': ?state,
        'postcode': ?postcode,
        'country': ?country,
        'email': ?email,
        'phone': ?phone,
      };
}

/// One line of an order.
final class WooLineItem {
  const WooLineItem({
    required this.productId,
    required this.quantity,
    this.variationId = 0,
    this.name = '',
    this.sku = '',
    this.subtotal = '',
    this.total = '',
  });

  factory WooLineItem.fromJson(Map<String, Object?> json) => WooLineItem(
        productId: _int(json['product_id']),
        variationId: _int(json['variation_id']),
        quantity: _int(json['quantity']),
        name: _text(json['name']),
        sku: _text(json['sku']),
        subtotal: _text(json['subtotal']),
        total: _text(json['total']),
      );

  final int productId;
  final int variationId;
  final int quantity;
  final String name;
  final String sku;

  /// The line before discounts.
  final String subtotal;

  /// The line after discounts, without tax.
  final String total;

  num get totalAmount => dvWooAmount(total);
}

/// One product and how many of it, for a cart or a new order.
final class WooCartLine {
  const WooCartLine({
    required this.productId,
    required this.quantity,
    this.variationId,
  });

  final int productId;
  final int? variationId;
  final int quantity;

  Map<String, Object?> toJson() => <String, Object?>{
        'product_id': productId,
        'variation_id': ?variationId,
        'quantity': quantity,
      };
}

/// An order.
final class WooOrder {
  const WooOrder({
    required this.id,
    required this.orderKey,
    required this.status,
    this.number = '',
    this.currency = '',
    this.total = '',
    this.totalTax = '',
    this.shippingTotal = '',
    this.discountTotal = '',
    this.customerId = 0,
    this.paymentMethod = '',
    this.paymentMethodTitle = '',
    this.transactionId = '',
    this.datePaid,
    this.paymentUrl,
    this.needsPayment = false,
    this.billing = const WooAddress(),
    this.lineItems = const <WooLineItem>[],
    this.couponCodes = const <String>[],
    this.meta = const <String, String>{},
  });

  factory WooOrder.fromJson(Map<String, Object?> json) {
    final String? paid = _optional(json['date_paid_gmt']);
    final Object? billing = json['billing'];
    return WooOrder(
      id: _int(json['id']),
      number: _text(json['number']),
      orderKey: _text(json['order_key']),
      status: _text(json['status']),
      currency: _text(json['currency']),
      total: _text(json['total']),
      totalTax: _text(json['total_tax']),
      shippingTotal: _text(json['shipping_total']),
      discountTotal: _text(json['discount_total']),
      customerId: _int(json['customer_id']),
      paymentMethod: _text(json['payment_method']),
      paymentMethodTitle: _text(json['payment_method_title']),
      transactionId: _text(json['transaction_id']),
      // The store's GMT times carry no zone; they are UTC.
      datePaid: paid == null
          ? null
          : DateTime.tryParse(
              RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(paid) ? paid : '${paid}Z'),
      paymentUrl: _optional(json['payment_url']),
      needsPayment: json['needs_payment'] == true,
      billing: billing is Map
          ? WooAddress.fromJson(<String, Object?>{
              for (final MapEntry<Object?, Object?> e in billing.entries)
                '${e.key}': e.value,
            })
          : const WooAddress(),
      lineItems: <WooLineItem>[
        for (final Map<String, Object?> l in _maps(json['line_items']))
          WooLineItem.fromJson(l),
      ],
      couponCodes: <String>[
        for (final Map<String, Object?> c in _maps(json['coupon_lines']))
          if (_optional(c['code']) != null) _text(c['code']),
      ],
      meta: <String, String>{
        for (final Map<String, Object?> m in _maps(json['meta_data']))
          if (m['value'] is String || m['value'] is num || m['value'] is bool)
            _text(m['key']): _text(m['value']),
      },
    );
  }

  final int id;
  final String number;

  /// The secret half of an order's address: whoever holds it may pay the
  /// order or ask about it.
  final String orderKey;

  /// `pending`, `processing`, `on-hold`, `completed`, `cancelled`,
  /// `refunded`, `failed` or `trash`.
  final String status;
  final String currency;
  final String total;
  final String totalTax;
  final String shippingTotal;
  final String discountTotal;
  final int customerId;
  final String paymentMethod;
  final String paymentMethodTitle;
  final String transactionId;
  final DateTime? datePaid;

  /// The store's own page for paying this order, where its configured
  /// payment gateways take the money.
  final String? paymentUrl;

  /// Whether the store is still waiting for payment.
  final bool needsPayment;
  final WooAddress billing;
  final List<WooLineItem> lineItems;
  final List<String> couponCodes;

  /// The order's meta data whose values are plain text or numbers.
  final Map<String, String> meta;

  num get totalAmount => dvWooAmount(total);
}

/// A new order, for `WooCommerceApi.createOrder`.
final class WooOrderRequest {
  const WooOrderRequest({
    required this.lineItems,
    this.billing,
    this.shipping,
    this.customerId,
    this.couponCodes = const <String>[],
    this.customerNote,
    this.status = 'pending',
    this.setPaid = false,
    this.meta = const <String, String>{},
  });

  final List<WooCartLine> lineItems;
  final WooAddress? billing;
  final WooAddress? shipping;
  final int? customerId;
  final List<String> couponCodes;
  final String? customerNote;
  final String status;

  /// Marks the order paid as it is made. For an order whose money the
  /// application took some other way; a checkout leaves it false and lets
  /// the store's gateway say.
  final bool setPaid;
  final Map<String, String> meta;

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status,
        'set_paid': setPaid,
        'line_items': <Object?>[
          for (final WooCartLine line in lineItems) line.toJson(),
        ],
        'billing': ?billing?.toJson(),
        'shipping': ?shipping?.toJson(),
        'customer_id': ?customerId,
        if (couponCodes.isNotEmpty)
          'coupon_lines': <Object?>[
            for (final String code in couponCodes)
              <String, Object?>{'code': code},
          ],
        'customer_note': ?customerNote,
        if (meta.isNotEmpty)
          'meta_data': <Object?>[
            for (final MapEntry<String, String> m in meta.entries)
              <String, Object?>{'key': m.key, 'value': m.value},
          ],
      };
}

/// A customer account in the store.
final class WooCustomer {
  const WooCustomer({
    required this.id,
    required this.email,
    this.firstName = '',
    this.lastName = '',
    this.username = '',
    this.billing = const WooAddress(),
  });

  factory WooCustomer.fromJson(Map<String, Object?> json) {
    final Object? billing = json['billing'];
    return WooCustomer(
      id: _int(json['id']),
      email: _text(json['email']),
      firstName: _text(json['first_name']),
      lastName: _text(json['last_name']),
      username: _text(json['username']),
      billing: billing is Map
          ? WooAddress.fromJson(<String, Object?>{
              for (final MapEntry<Object?, Object?> e in billing.entries)
                '${e.key}': e.value,
            })
          : const WooAddress(),
    );
  }

  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String username;
  final WooAddress billing;
}

/// A coupon.
final class WooCoupon {
  const WooCoupon({
    required this.id,
    required this.code,
    this.amount = '',
    this.discountType = '',
    this.dateExpires,
    this.usageCount = 0,
    this.usageLimit,
  });

  factory WooCoupon.fromJson(Map<String, Object?> json) {
    final String? expires = _optional(json['date_expires_gmt']);
    return WooCoupon(
      id: _int(json['id']),
      code: _text(json['code']),
      amount: _text(json['amount']),
      discountType: _text(json['discount_type']),
      dateExpires: expires == null ? null : DateTime.tryParse('${expires}Z'),
      usageCount: _int(json['usage_count']),
      usageLimit:
          json['usage_limit'] == null ? null : _int(json['usage_limit']),
    );
  }

  final int id;
  final String code;
  final String amount;

  /// `percent`, `fixed_cart` or `fixed_product`.
  final String discountType;
  final DateTime? dateExpires;
  final int usageCount;
  final int? usageLimit;

  num get amountValue => dvWooAmount(amount);
}
