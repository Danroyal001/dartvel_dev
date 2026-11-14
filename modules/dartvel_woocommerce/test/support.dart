import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_woocommerce/dartvel_woocommerce.dart';

const String consumerKey = 'ck_0123456789abcdef0123456789abcdef01234567';
const String consumerSecret = 'cs_0123456789abcdef0123456789abcdef01234567';
const String webhookSecret = 'whsec-0123456789abcdef';

const WooCommerceConfig config =
    WooCommerceConfig(storeUrl: 'https://shop.example.com');

void configureSecrets() {
  DVSecrets.configure(<String, String>{
    WooCommerceConfig.defaultConsumerKeyName: consumerKey,
    WooCommerceConfig.defaultConsumerSecretName: consumerSecret,
    WooCommerceConfig.defaultWebhookSecretName: webhookSecret,
  });
}

/// An order as WooCommerce's REST API answers with one.
Map<String, Object?> orderJson({
  int id = 981,
  String status = 'pending',
  String key = 'wc_order_abc123',
  List<Map<String, Object?>> meta = const <Map<String, Object?>>[],
  String? datePaid,
}) =>
    <String, Object?>{
      'id': id,
      'number': '$id',
      'order_key': key,
      'status': status,
      'currency': 'NGN',
      'total': '47500.00',
      'total_tax': '1500.00',
      'shipping_total': '1000.00',
      'discount_total': '0.00',
      'customer_id': 0,
      'payment_method': 'paystack',
      'payment_method_title': 'Debit/Credit Cards',
      'transaction_id': '',
      'date_created_gmt': '2026-11-14T11:50:00',
      'date_paid_gmt': datePaid,
      'payment_url':
          'https://shop.example.com/checkout/order-pay/$id/?pay_for_order=true&key=$key',
      'needs_payment': status == 'pending' || status == 'failed',
      'billing': <String, Object?>{
        'first_name': 'Ada',
        'last_name': 'Obi',
        'email': 'ada@example.com',
        'phone': '+2348030000000',
        'city': 'Uyo',
        'country': 'NG',
        'postcode': '520001',
      },
      'line_items': <Object?>[
        <String, Object?>{
          'id': 1,
          'name': 'Website audit',
          'product_id': 12,
          'variation_id': 0,
          'quantity': 1,
          'sku': 'SKU-1',
          'price': 45000,
          'subtotal': '45000.00',
          'total': '45000.00',
        },
      ],
      'coupon_lines': <Object?>[
        <String, Object?>{'id': 5, 'code': 'launch'},
      ],
      'meta_data': <Object?>[
        for (final Map<String, Object?> m in meta) <String, Object?>{'id': 1, ...m},
      ],
    };

Map<String, Object?> jsonBody(DVHttpCall call) =>
    jsonDecode(utf8.decode(call.body)) as Map<String, Object?>;
