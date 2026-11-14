// Checkout: an order made in the store, the buyer sent to the store's own
// payment page, and the payment confirmed from the store -- never from the
// buyer coming back.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_woocommerce/dartvel_woocommerce.dart';
import 'package:dartvel_woocommerce/src/checkout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late DVHttpFake fake;
  late List<Object?> published;

  void answer(DVHttpStub stub) {
    fake = const DVHttp()
        .fake(<String, DVHttpStub>{'shop.example.com': stub});
  }

  WooCommerceCheckout checkout() => WooCommerceCheckout(
        config,
        clock: () => DateTime.utc(2026, 11, 14, 12),
        publish: (String topic, Object? payload) async {
          expect(topic, 'commerce.purchase');
          published.add(payload);
        },
      );

  setUp(() {
    DVHttp.reset();
    DVSecrets.reset();
    configureSecrets();
    published = <Object?>[];
    WooCommerceCheckout.resetForTesting();
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  const WooCheckoutRequest request = WooCheckoutRequest(
    cart: <WooCartLine>[WooCartLine(productId: 12, quantity: 1)],
    billing: WooAddress(firstName: 'Ada', email: 'ada@example.com'),
    idempotencyKey: 'cart-7f3a',
    context: <String, Object?>{
      'googleAnalytics': <String, Object?>{'client_id': '1.2'},
    },
  );

  group('starting a checkout', () {
    test('makes a pending, unpaid order and answers with where to pay',
        () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(<Object?>[]), // nothing with this key yet
        DVHttpStub.json(orderJson(), status: 201),
      ]));
      final WooCheckoutSession session = await checkout().start(request);

      expect(session.orderId, 981);
      expect(session.orderKey, 'wc_order_abc123');
      expect(session.needsPayment, isTrue);
      expect(session.total, '47500.00');
      expect(session.currency, 'NGN');
      expect(
        '${session.paymentUrl}',
        'https://shop.example.com/checkout/order-pay/981/?pay_for_order=true&key=wc_order_abc123',
      );

      final DVHttpCall create = fake.calls.last;
      expect(create.method, 'POST');
      final Map<String, Object?> body = jsonBody(create);
      expect(body['status'], 'pending');
      expect(body['set_paid'], isFalse);
      // Products and quantities only: the store prices them.
      expect(body['line_items'], <Object?>[
        <String, Object?>{'product_id': 12, 'quantity': 1},
      ]);
      final List<Object?> meta = body['meta_data']! as List<Object?>;
      expect(
        meta,
        anyElement(equals(<String, Object?>{
          'key': '_dv_idempotency_key',
          'value': 'cart-7f3a',
        })),
      );
      final Map<String, Object?> analytics = meta
          .cast<Map<String, Object?>>()
          .firstWhere((Map<String, Object?> m) => m['key'] == '_dv_analytics');
      expect(jsonDecode(analytics['value']! as String), request.context);
    });

    test('asked twice with one key, makes one order', () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(<Object?>[]),
        DVHttpStub.json(orderJson(), status: 201),
      ]));
      final WooCommerceCheckout shop = checkout();
      final List<WooCheckoutSession> sessions =
          await Future.wait(<Future<WooCheckoutSession>>[
        shop.start(request),
        shop.start(request),
      ]);
      await shop.start(request);

      expect(sessions.first.orderId, sessions.last.orderId);
      expect(fake.calls.where((DVHttpCall c) => c.method == 'POST'),
          hasLength(1));
    });

    test('after a restart, the order already in the store is found by its '
        'key instead of made again', () async {
      answer(DVHttpStub.json(<Object?>[
        orderJson(id: 400, key: 'wc_order_other'),
        orderJson(meta: <Map<String, Object?>>[
          <String, Object?>{'key': '_dv_idempotency_key', 'value': 'cart-7f3a'},
        ]),
      ]));
      final WooCheckoutSession session = await checkout().start(request);
      expect(session.orderId, 981);
      expect(fake.calls.single.method, 'GET');
      expect(fake.calls.single.url.path, '/wp-json/wc/v3/orders');
      expect(fake.calls.single.url.queryParameters['after'],
          startsWith('2026-11-13T12:00:00'));
    });

    test('an empty cart, an impossible quantity or no key is refused before '
        'the store is asked', () async {
      answer(DVHttpStub.json(<Object?>[]));
      for (final WooCheckoutRequest bad in const <WooCheckoutRequest>[
        WooCheckoutRequest(cart: <WooCartLine>[], idempotencyKey: 'k'),
        WooCheckoutRequest(
            cart: <WooCartLine>[WooCartLine(productId: 12, quantity: 0)],
            idempotencyKey: 'k'),
        WooCheckoutRequest(
            cart: <WooCartLine>[WooCartLine(productId: 0, quantity: 1)],
            idempotencyKey: 'k'),
        WooCheckoutRequest(
            cart: <WooCartLine>[WooCartLine(productId: 12, quantity: 1)],
            idempotencyKey: ''),
      ]) {
        await expectLater(
            checkout().start(bad), throwsA(isA<WooCommerceException>()));
      }
      expect(fake.calls, isEmpty);
    });

    test('a store too old to say where to pay is an error, not a guess',
        () async {
      answer(DVHttpStub.sequence(<DVHttpStub>[
        DVHttpStub.json(<Object?>[]),
        DVHttpStub.json(orderJson()..remove('payment_url'), status: 201),
      ]));
      await expectLater(
        checkout().start(request),
        throwsA(isA<WooCommerceException>().having(
            (WooCommerceException e) => e.code, 'code', 'no_payment_url')),
      );
    });
  });

  group('asking whether an order is paid', () {
    test('needs the order\'s key, so an order number alone tells nobody '
        'anything', () async {
      answer(DVHttpStub.json(orderJson(status: 'processing')));
      await expectLater(
        checkout().status(981, 'wc_order_guess'),
        throwsA(isA<WooCommerceException>()
            .having((WooCommerceException e) => e.status, 'status', 404)),
      );
      expect(published, isEmpty);
    });

    test('pending is not paid', () async {
      answer(DVHttpStub.json(orderJson()));
      final WooOrderState state =
          await checkout().status(981, 'wc_order_abc123');
      expect(state.paid, isFalse);
      expect(state.finished, isFalse);
      expect(published, isEmpty);
    });

    test('failed and cancelled are finished and not paid', () async {
      for (final String status in <String>['failed', 'cancelled', 'refunded']) {
        answer(DVHttpStub.json(orderJson(status: status)));
        final WooOrderState state =
            await checkout().status(981, 'wc_order_abc123');
        expect(state.paid, isFalse, reason: status);
        expect(state.finished, isTrue, reason: status);
      }
    });

    test('processing is paid, and the purchase is published, which is how '
        'payment is confirmed when no webhook arrives', () async {
      answer(DVHttpStub.json(orderJson(
        status: 'processing',
        datePaid: '2026-11-14T11:58:00',
        meta: <Map<String, Object?>>[
          <String, Object?>{
            'key': '_dv_analytics',
            'value': jsonEncode(request.context),
          },
        ],
      )));
      final WooOrderState state =
          await checkout().status(981, 'wc_order_abc123');
      expect(state.paid, isTrue);
      expect(state.finished, isTrue);

      final Map<String, Object?> purchase =
          published.single! as Map<String, Object?>;
      expect(purchase['transaction_id'], '981');
      expect(purchase['order_id'], 981);
      expect(purchase['currency'], 'NGN');
      expect(purchase['total'], 47500);
      // The items' own total: shipping and tax are beside it.
      expect(purchase['value'], 45000);
      expect(purchase['tax'], 1500);
      expect(purchase['shipping'], 1000);
      expect(purchase['coupon'], 'launch');
      expect(purchase['paid_at'], '2026-11-14T11:58:00Z');
      expect(purchase['items'], <Object?>[
        <String, Object?>{
          'item_id': 'SKU-1',
          'item_name': 'Website audit',
          'price': 45000,
          'quantity': 1,
        },
      ]);
      expect((purchase['customer']! as Map<String, Object?>)['email'],
          'ada@example.com');
      expect(purchase['context'], request.context);
    });
  });

  group('a confirmed purchase', () {
    WooOrder paid({List<Map<String, Object?>> meta = const <Map<String, Object?>>[]}) =>
        WooOrder.fromJson(orderJson(
            status: 'completed', datePaid: '2026-11-14T11:58:00', meta: meta));

    test('is published once, however many times the store says so',
        () async {
      answer(DVHttpStub.json(orderJson(status: 'completed')));
      final WooCommerceCheckout shop = checkout();
      expect(await shop.confirm(paid()), isTrue);
      expect(await shop.confirm(paid()), isFalse);
      expect(published, hasLength(1));
    });

    test('is marked on the order, so another server or a restart does not '
        'publish it again', () async {
      answer(DVHttpStub.json(orderJson(status: 'completed')));
      await checkout().confirm(paid());
      final DVHttpCall mark = fake.calls.single;
      expect(mark.method, 'PUT');
      expect(mark.url.path, '/wp-json/wc/v3/orders/981');
      expect(jsonBody(mark), <String, Object?>{
        'meta_data': <Object?>[
          <String, Object?>{
            'key': '_dv_purchase_reported',
            'value': '2026-11-14T12:00:00.000Z',
          },
        ],
      });

      WooCommerceCheckout.resetForTesting();
      expect(
        await checkout().confirm(paid(meta: <Map<String, Object?>>[
          <String, Object?>{
            'key': '_dv_purchase_reported',
            'value': '2026-11-14T12:00:00.000Z',
          },
        ])),
        isFalse,
      );
      expect(published, hasLength(1));
    });

    test('an order that is not paid is not published', () async {
      answer(DVHttpStub.json(orderJson()));
      expect(
          await checkout().confirm(WooOrder.fromJson(orderJson())), isFalse);
      expect(published, isEmpty);
      expect(fake.calls, isEmpty);
    });

    test('a subscriber or the store failing afterwards does not undo it',
        () async {
      answer(DVHttpStub.status(500));
      final WooCommerceCheckout shop = WooCommerceCheckout(
        config,
        clock: () => DateTime.utc(2026, 11, 14, 12),
        publish: (String topic, Object? payload) async {
          published.add(payload);
          throw StateError('analytics is down');
        },
      );
      expect(await shop.confirm(paid()), isTrue);
      expect(published, hasLength(1));
    });
  });
}
