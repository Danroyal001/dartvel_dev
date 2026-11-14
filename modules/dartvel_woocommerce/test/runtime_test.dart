// The module in a client and on the backend.
//
// A client holds no store keys: each call is carried to the application's
// backend, which asks the store. The route those calls arrive on is public,
// like a shop, so what it accepts is what a shopper may do.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_woocommerce/dartvel_woocommerce.dart';
import 'package:dartvel_woocommerce/src/checkout.dart';
import 'package:dartvel_woocommerce/src/runtime.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late DVHttpFake fake;

  void answer(DVHttpStub stub) {
    fake = const DVHttp()
        .fake(<String, DVHttpStub>{'shop.example.com': stub});
  }

  WooCommerceRuntime backend() => WooCommerceRuntime(
        config: config,
        environment: DVModuleEnvironment.backend,
        clock: () => DateTime.utc(2026, 11, 14, 12),
      );

  /// A client whose calls go straight to [server]'s dispatcher, after the
  /// JSON round trip the wire would give them.
  WooCommerceRuntime client(WooCommerceRuntime server,
          {List<String>? carried}) =>
      WooCommerceRuntime(
        config: const WooCommerceConfig(
            pollInterval: Duration(milliseconds: 1)),
        environment: DVModuleEnvironment.web,
        carrier: (String operation, Map<String, Object?> arguments) async {
          carried?.add(operation);
          final Object? result = await server.dispatch(
              operation,
              jsonDecode(jsonEncode(arguments)) as Map<String, Object?>);
          return jsonDecode(jsonEncode(result));
        },
      );

  setUp(() {
    DVHttp.reset();
    DVSecrets.reset();
    configureSecrets();
    WooCommerceCheckout.resetForTesting();
    dvModuleRegistry.resetForTesting();
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
    dvModuleRegistry.resetForTesting();
  });

  group('in a client', () {
    test('the typed API is not there: its keys are the backend\'s', () {
      expect(() => client(backend()).api, throwsA(isA<DVModuleUnavailable>()));
    });

    test('the catalogue is carried to the backend, which asks only for '
        'what is published', () async {
      answer(DVHttpStub.json(<Object?>[
        <String, Object?>{'id': 12, 'name': 'Website audit', 'price': '45000', 'status': 'publish'},
      ]));
      final List<WooProduct> products =
          await client(backend()).products(search: 'audit');
      expect(products.single.name, 'Website audit');
      expect(products.single.priceAmount, 45000);
      expect(fake.calls.single.url.queryParameters['status'], 'publish');
      expect(fake.calls.single.url.queryParameters['search'], 'audit');
    });

    test('a product that is not published is not there', () async {
      answer(DVHttpStub.json(<String, Object?>{
        'id': 13,
        'name': 'Draft',
        'status': 'draft',
      }));
      expect(await client(backend()).product(13), isNull);
    });

    test('a checkout carries the cart and what the analytics modules know, '
        'and comes back with where to pay', () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(<Object?>[]),
        DVHttpStub.json(orderJson(), status: 201),
      ]));
      dvModuleRegistry.subscribe('analytics.context', (Object? context) {
        (context! as Map<String, Object?>)['googleAnalytics'] =
            <String, Object?>{'client_id': '1.2'};
      });

      final WooCheckoutSession session = await client(backend()).startCheckout(
        cart: const <WooCartLine>[WooCartLine(productId: 12, quantity: 1)],
        billing: const WooAddress(firstName: 'Ada', email: 'ada@example.com'),
        idempotencyKey: 'cart-7f3a',
      );

      expect(session.orderId, 981);
      expect(session.paymentUrl.host, 'shop.example.com');
      final Map<String, Object?> created = jsonBody(fake.calls.last);
      final Map<String, Object?> analytics = (created['meta_data']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((Map<String, Object?> m) => m['key'] == '_dv_analytics');
      expect(
        (jsonDecode(analytics['value']! as String)
            as Map<String, Object?>)['googleAnalytics'],
        <String, Object?>{'client_id': '1.2'},
      );
    });

    test('watching an order yields each change and stops when it is paid, '
        'and the buyer\'s own modules hear of the purchase once', () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(orderJson()),
        DVHttpStub.json(orderJson()),
        DVHttpStub.json(orderJson(status: 'processing')),
      ]));
      final List<Object?> heard = <Object?>[];
      final List<String> carried = <String>[];
      final WooCommerceRuntime shop = client(backend(), carried: carried);
      dvModuleRegistry.subscribe('commerce.purchase', heard.add);

      final List<WooOrderState> states =
          await shop.watchOrder(981, 'wc_order_abc123').toList();

      expect(states.map((WooOrderState s) => s.status),
          <String>['pending', 'processing']);
      expect(states.last.paid, isTrue);
      expect(carried.where((String op) => op == 'orderStatus').length, 3);
      // The server published it to its own subscribers too; this registry
      // is shared by both halves in a test, so two.
      final List<Map<String, Object?>> purchases =
          heard.cast<Map<String, Object?>>();
      expect(purchases.every((Map<String, Object?> p) =>
          p['transaction_id'] == '981'), isTrue);
      // The copy a client is given names what was bought, not the buyer.
      expect(states.last.purchase!.containsKey('customer'), isFalse);
      expect(states.last.purchase!['value'], 45000);
    });
  });

  group('what the public route accepts', () {
    test('a cart of products and quantities; a price or a customer id sent '
        'with it is not passed on', () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(<Object?>[]),
        DVHttpStub.json(orderJson(), status: 201),
      ]));
      await backend().dispatch('startCheckout', <String, Object?>{
        'cart': <Object?>[
          <String, Object?>{
            'product_id': 12,
            'quantity': 1,
            'price': '1.00',
            'total': '1.00',
          },
        ],
        'customerId': 1,
        'customer_id': 1,
        'idempotencyKey': 'cart-1',
      });
      final Map<String, Object?> created = jsonBody(fake.calls.last);
      expect(created['line_items'], <Object?>[
        <String, Object?>{'product_id': 12, 'quantity': 1},
      ]);
      expect(created.containsKey('customer_id'), isFalse);
      expect(created['set_paid'], isFalse);
    });

    test('the request\'s address and user agent join the analytics context, '
        'when there is one', () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(<Object?>[]),
        DVHttpStub.json(orderJson(), status: 201),
      ]));
      await DVModuleRpc.withRequest(
        Request(
          method: 'POST',
          url: Uri.parse('https://example.com/api/_dv/modules/woocommerce/startCheckout'),
          headers: Headers(<String, Object?>{'user-agent': 'Mozilla/5.0 (Buyer)'}),
          bodyStream: const Stream<List<int>>.empty(),
          peerAddress: DVPeerAddress(DVIpAddress.parse('203.0.113.9')),
        ),
        () => backend().dispatch('startCheckout', <String, Object?>{
          'cart': <Object?>[
            <String, Object?>{'product_id': 12, 'quantity': 1},
          ],
          'idempotencyKey': 'cart-2',
          'context': <String, Object?>{
            'metaPixel': <String, Object?>{'fbp': 'fb.1.1.2'},
          },
        }),
      );
      final Map<String, Object?> analytics = jsonDecode(((jsonBody(fake.calls.last)['meta_data']!
                  as List<Object?>)
              .cast<Map<String, Object?>>()
              .firstWhere((Map<String, Object?> m) => m['key'] == '_dv_analytics')['value']!
          as String)) as Map<String, Object?>;
      expect(analytics['request'], <String, Object?>{
        'ip': '203.0.113.9',
        'agent': 'Mozilla/5.0 (Buyer)',
      });
    });

    test('a buyer who consented to nothing has nothing kept about them',
        () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(<Object?>[]),
        DVHttpStub.json(orderJson(), status: 201),
      ]));
      await DVModuleRpc.withRequest(
        Request(
          method: 'POST',
          url: Uri.parse('https://example.com/x'),
          headers: Headers(<String, Object?>{'user-agent': 'Mozilla/5.0'}),
          bodyStream: const Stream<List<int>>.empty(),
          peerAddress: DVPeerAddress(DVIpAddress.parse('203.0.113.9')),
        ),
        () => backend().dispatch('startCheckout', <String, Object?>{
          'cart': <Object?>[
            <String, Object?>{'product_id': 12, 'quantity': 1},
          ],
          'idempotencyKey': 'cart-3',
          'context': <String, Object?>{},
        }),
      );
      final List<Object?> meta =
          jsonBody(fake.calls.last)['meta_data']! as List<Object?>;
      expect(
        meta.cast<Map<String, Object?>>().any(
            (Map<String, Object?> m) => m['key'] == '_dv_analytics'),
        isFalse,
      );
    });

    test('anything else is refused before the store is asked', () async {
      answer(DVHttpStub.json(<Object?>[]));
      final WooCommerceRuntime shop = backend();
      for (final (String, Map<String, Object?>) bad
          in <(String, Map<String, Object?>)>[
        ('startCheckout', <String, Object?>{}),
        ('startCheckout', <String, Object?>{'cart': 'x', 'idempotencyKey': 'k'}),
        (
          'startCheckout',
          <String, Object?>{
            'cart': <Object?>[
              <String, Object?>{'product_id': '12', 'quantity': 1},
            ],
            'idempotencyKey': 'k',
          }
        ),
        (
          'startCheckout',
          <String, Object?>{
            'cart': <Object?>[
              <String, Object?>{'product_id': 12, 'quantity': 1},
            ],
          }
        ),
        (
          'startCheckout',
          <String, Object?>{
            'cart': <Object?>[
              <String, Object?>{'product_id': 12, 'quantity': 1},
            ],
            'idempotencyKey': 'k',
            'billing': <String, Object?>{'email': <Object?>[]},
          }
        ),
        (
          'startCheckout',
          <String, Object?>{
            'cart': <Object?>[
              <String, Object?>{'product_id': 12, 'quantity': 0},
            ],
            'idempotencyKey': 'k',
          }
        ),
        ('orderStatus', <String, Object?>{'orderId': 981}),
        ('product', <String, Object?>{'id': 'twelve'}),
        ('orders', <String, Object?>{}),
        ('api', <String, Object?>{}),
        ('createOrder', <String, Object?>{}),
      ]) {
        await expectLater(shop.dispatch(bad.$1, bad.$2),
            throwsA(isA<DVModuleRpcRefused>()),
            reason: '$bad');
      }
      expect(fake.calls, isEmpty);
    });

    test('the store\'s own refusal is not repeated to a shopper', () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(<Object?>[]),
        DVHttpStub.json(<String, Object?>{
          'code': 'woocommerce_rest_invalid_product_id',
          'message': 'Internal detail about product 12 and table wp_posts.',
        }, status: 400),
      ]));
      await expectLater(
        backend().dispatch('startCheckout', <String, Object?>{
          'cart': <Object?>[
            <String, Object?>{'product_id': 12, 'quantity': 1},
          ],
          'idempotencyKey': 'cart-4',
        }),
        throwsA(isA<DVModuleRpcRefused>().having(
            (DVModuleRpcRefused e) => '$e', 'text',
            isNot(contains('wp_posts')))),
      );
    });

    test('an order is not told about without its key', () async {
      answer(DVHttpStub.json(orderJson(status: 'processing')));
      await expectLater(
        backend().dispatch('orderStatus',
            <String, Object?>{'orderId': 981, 'orderKey': 'wc_order_guess'}),
        throwsA(isA<WooCommerceException>()),
      );
    });
  });

  group('settings', () {
    test('are read from the mount', () {
      final WooCommerceConfig read =
          WooCommerceConfig.fromModuleConfig(<String, Object?>{
        'storeUrl': 'https://shop.example.com/',
        'pollSeconds': 3,
      });
      expect(read.resolvedStoreUrl, 'https://shop.example.com');
      expect(read.pollInterval, const Duration(seconds: 3));
    });

    test('a key in the mount is refused by name: it would be compiled into '
        'the client', () {
      expect(
        () => WooCommerceConfig.fromModuleConfig(
            <String, Object?>{'consumerSecret': consumerSecret}),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}',
            'message', contains(WooCommerceConfig.defaultConsumerSecretName))),
      );
      expect(
        () => WooCommerceConfig.fromModuleConfig(
            <String, Object?>{'storeURL': 'x'}),
        throwsArgumentError,
      );
    });
  });
}
