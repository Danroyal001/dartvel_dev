// The typed client, against a faked store.
//
// What is asserted is what WooCommerce's REST API documentation states
// (fetched 14 Nov 2026): resources under /wp-json/wc/v3, HTTP Basic auth
// over HTTPS with the consumer key as the username and the consumer secret
// as the password, the `code` and `message` of an error, and the names of
// the list parameters and resource properties.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_woocommerce/dartvel_woocommerce.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late DVHttpFake fake;

  void answer(DVHttpStub stub) {
    fake = const DVHttp()
        .fake(<String, DVHttpStub>{'shop.example.com': stub});
  }

  setUp(() {
    DVHttp.reset();
    DVSecrets.reset();
    configureSecrets();
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  WooCommerceApi api() => const WooCommerceApi(config);

  test('a request goes to the store\'s v3 API with Basic auth, and the keys '
      'are in no address', () async {
    answer(DVHttpStub.json(<Object?>[]));
    await api().products(search: 'audit', perPage: 20, page: 2);

    final DVHttpCall call = fake.calls.single;
    expect(call.method, 'GET');
    expect(call.url.path, '/wp-json/wc/v3/products');
    expect(call.url.queryParameters, <String, String>{
      'search': 'audit',
      'per_page': '20',
      'page': '2',
    });
    expect(call.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}');
    expect('${call.url}', isNot(contains(consumerKey)));
    expect('${call.url}', isNot(contains(consumerSecret)));
  });

  test('a store that is not HTTPS is refused: Basic auth would send the keys '
      'in the clear', () {
    expect(
      () => const WooCommerceApi(
              WooCommerceConfig(storeUrl: 'http://shop.example.com'))
          .products(),
      throwsA(isA<WooCommerceException>()
          .having((WooCommerceException e) => e.code, 'code', 'not_https')),
    );
  });

  test('with no store or no keys it says which, and sends nothing', () async {
    answer(DVHttpStub.json(<Object?>[]));
    await expectLater(
      const WooCommerceApi(WooCommerceConfig()).products(),
      throwsA(isA<WooCommerceException>().having(
          (WooCommerceException e) => e.code, 'code', 'not_configured')),
    );
    DVSecrets.reset();
    await expectLater(
      api().products(),
      throwsA(isA<WooCommerceException>().having(
          (WooCommerceException e) => e.message,
          'message',
          contains(WooCommerceConfig.defaultConsumerKeyName))),
    );
    expect(fake.calls, isEmpty);
  });

  test('a product is read with its prices as the store gives them', () async {
    answer(DVHttpStub.json(<String, Object?>{
      'id': 12,
      'name': 'Website audit',
      'slug': 'website-audit',
      'permalink': 'https://shop.example.com/product/website-audit/',
      'type': 'simple',
      'status': 'publish',
      'sku': 'SKU-1',
      'price': '45000',
      'regular_price': '60000',
      'sale_price': '45000',
      'on_sale': true,
      'purchasable': true,
      'stock_status': 'instock',
      'short_description': '<p>A passive audit.</p>',
      'images': <Object?>[
        <String, Object?>{'id': 3, 'src': 'https://shop.example.com/a.png', 'alt': 'Audit'},
      ],
      'categories': <Object?>[
        <String, Object?>{'id': 9, 'name': 'Services', 'slug': 'services'},
      ],
    }));
    final WooProduct product = await api().product(12);
    expect(fake.calls.single.url.path, '/wp-json/wc/v3/products/12');
    expect(product.id, 12);
    expect(product.name, 'Website audit');
    expect(product.price, '45000');
    expect(product.priceAmount, 45000);
    expect(product.regularPrice, '60000');
    expect(product.onSale, isTrue);
    expect(product.purchasable, isTrue);
    expect(product.images.single.src, 'https://shop.example.com/a.png');
    expect(product.categories.single.name, 'Services');
  });

  test('an order is created with the fields the API names', () async {
    answer(DVHttpStub.json(orderJson(), status: 201));
    final WooOrder order = await api().createOrder(const WooOrderRequest(
      lineItems: <WooCartLine>[
        WooCartLine(productId: 12, quantity: 1),
        WooCartLine(productId: 30, variationId: 31, quantity: 2),
      ],
      billing: WooAddress(firstName: 'Ada', email: 'ada@example.com'),
      couponCodes: <String>['launch'],
      customerNote: 'Call first',
      meta: <String, String>{'source': 'app'},
    ));

    final DVHttpCall call = fake.calls.single;
    expect(call.method, 'POST');
    expect(call.url.path, '/wp-json/wc/v3/orders');
    expect(jsonBody(call), <String, Object?>{
      'status': 'pending',
      'set_paid': false,
      'line_items': <Object?>[
        <String, Object?>{'product_id': 12, 'quantity': 1},
        <String, Object?>{'product_id': 30, 'variation_id': 31, 'quantity': 2},
      ],
      'billing': <String, Object?>{'first_name': 'Ada', 'email': 'ada@example.com'},
      'coupon_lines': <Object?>[
        <String, Object?>{'code': 'launch'},
      ],
      'customer_note': 'Call first',
      'meta_data': <Object?>[
        <String, Object?>{'key': 'source', 'value': 'app'},
      ],
    });
    expect(order.id, 981);
    expect(order.orderKey, 'wc_order_abc123');
    expect(order.status, 'pending');
    expect(order.total, '47500.00');
    expect(order.currency, 'NGN');
    expect(order.needsPayment, isTrue);
    expect(
      order.paymentUrl,
      'https://shop.example.com/checkout/order-pay/981/?pay_for_order=true&key=wc_order_abc123',
    );
    expect(order.lineItems.single.sku, 'SKU-1');
    expect(order.billing.email, 'ada@example.com');
  });

  test('an order, a customer by email and a coupon by code are looked up '
      'with the API\'s own parameters', () async {
    answer(DVHttpStub.json(orderJson(status: 'processing')));
    expect((await api().order(981)).status, 'processing');
    expect(fake.calls.single.url.path, '/wp-json/wc/v3/orders/981');

    answer(DVHttpStub.json(<Object?>[
      <String, Object?>{
        'id': 7,
        'email': 'ada@example.com',
        'first_name': 'Ada',
        'last_name': 'Obi',
        'username': 'ada',
      },
    ]));
    final List<WooCustomer> customers =
        await api().customers(email: 'ada@example.com');
    expect(fake.calls.single.url.path, '/wp-json/wc/v3/customers');
    expect(fake.calls.single.url.queryParameters['email'], 'ada@example.com');
    expect(customers.single.id, 7);

    answer(DVHttpStub.json(<Object?>[
      <String, Object?>{
        'id': 5,
        'code': 'launch',
        'amount': '10.00',
        'discount_type': 'percent',
        'date_expires_gmt': null,
        'usage_count': 3,
        'usage_limit': null,
      },
    ]));
    final WooCoupon? coupon = await api().couponByCode('LAUNCH');
    expect(fake.calls.single.url.path, '/wp-json/wc/v3/coupons');
    expect(fake.calls.single.url.queryParameters['code'], 'launch');
    expect(coupon?.discountType, 'percent');
    expect(coupon?.amount, '10.00');
  });

  test('the store\'s refusal is its code and message, without the keys',
      () async {
    answer(DVHttpStub.json(<String, Object?>{
      'code': 'woocommerce_rest_cannot_view',
      'message': 'Sorry, you cannot list resources.',
      'data': <String, Object?>{'status': 401},
    }, status: 401));
    await expectLater(
      api().orders(),
      throwsA(isA<WooCommerceException>()
          .having((WooCommerceException e) => e.status, 'status', 401)
          .having((WooCommerceException e) => e.code, 'code',
              'woocommerce_rest_cannot_view')
          .having((WooCommerceException e) => '$e', 'text',
              isNot(anyOf(contains(consumerKey), contains(consumerSecret))))),
    );
  });

  test('the store being unreachable is a WooCommerceException too', () async {
    answer(DVHttpStub.error(StateError('connection reset')));
    await expectLater(
      api().product(12),
      throwsA(isA<WooCommerceException>().having(
          (WooCommerceException e) => e.code, 'code', 'unreachable')),
    );
  });
}
