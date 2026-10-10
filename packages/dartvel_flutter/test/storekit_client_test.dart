// What the StoreKit 2 bridge answers, read into DV.Purchases' own types.
//
// The Swift shim speaks JSON so that Dart never needs a block or a callback
// from a StoreKit thread. That puts the whole contract in these decoders, and
// their failures are quiet ones: a price read through a double shows a
// button one cent off the sheet; an "unverified" transaction dropped on the
// device is a receipt check the server never got to make; an unknown
// outcome read as "cancelled" is a paid purchase nobody grants.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/src/purchases/storekit_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('listings', () {
    test('a price in milliunits becomes exact minor units', () {
      final List<DVStoreListing> listings =
          dvStoreKitListings(<String, Object?>{
        'listings': <Object?>[
          <String, Object?>{
            'storeProductId': 'com.example.pro',
            'title': 'Pro',
            'description': 'Everything',
            'displayPrice': r'$4.99',
            'currency': 'USD',
            'priceMilliunits': 4990,
            'period': 'P1M',
            'offers': <Object?>[
              <String, Object?>{
                'id': 'freeTrial',
                'kind': 'freeTrial',
                'displayPrice': r'$0.00',
                'period': 'P1W',
                'periods': 1,
                'eligible': true,
                'currency': 'USD',
                'priceMilliunits': 0,
              },
              <String, Object?>{
                'id': 'come_back',
                'kind': 'promotional',
                'displayPrice': r'$1.99',
                'period': 'P1M',
                'periods': 3,
                'eligible': true,
                'currency': 'USD',
                'priceMilliunits': 1990,
              },
            ],
          },
        ],
      });

      final DVStoreListing pro = listings.single;
      expect(pro.storeProductId, 'com.example.pro');
      expect(pro.price, DVMoney(amount: 499, currency: 'USD'));
      expect(pro.displayPrice, r'$4.99');
      expect(pro.period, 'P1M');
      expect(pro.offers.map((DVStoreOffer o) => o.kind), <DVStoreOfferKind>[
        DVStoreOfferKind.freeTrial,
        DVStoreOfferKind.promotional,
      ]);
      expect(pro.offers.last.price, DVMoney(amount: 199, currency: 'USD'));
      expect(pro.offers.last.periods, 3);
    });

    test('a zero-decimal currency keeps its whole units', () {
      final List<DVStoreListing> listings =
          dvStoreKitListings(<String, Object?>{
        'listings': <Object?>[
          <String, Object?>{
            'storeProductId': 'p',
            'title': 'P',
            'displayPrice': '¥600',
            'currency': 'JPY',
            'priceMilliunits': 600000,
          },
        ],
      });
      expect(listings.single.price, DVMoney(amount: 600, currency: 'JPY'));
    });

    test('a price that is not whole minor units shows no price, not a guess',
        () {
      final List<DVStoreListing> listings =
          dvStoreKitListings(<String, Object?>{
        'listings': <Object?>[
          <String, Object?>{
            'storeProductId': 'p',
            'title': 'P',
            'displayPrice': r'$4.995',
            'currency': 'USD',
            'priceMilliunits': 4995,
          },
        ],
      });
      expect(listings.single.price, isNull);
      expect(listings.single.displayPrice, r'$4.995');
    });

    test('a StoreKit error is thrown, not read as an empty catalogue', () {
      expect(() => dvStoreKitListings(<String, Object?>{'error': 'offline'}),
          throwsA(isA<DVStoreUnavailable>()));
    });
  });

  group('purchase outcomes', () {
    test('a purchase carries the JWS for the server to verify', () {
      final DVStorePurchaseOutcome outcome =
          dvStoreKitOutcome(<String, Object?>{
        'outcome': 'purchased',
        'transaction': <String, Object?>{
          'storeProductId': 'com.example.pro',
          'transactionId': '2000000123',
          'receipt': 'eyJhbGciOiJFUzI1NiJ9.e30.sig',
          'state': 'purchased',
          'quantity': 1,
        },
      });
      final DVStoreDeviceTransaction transaction =
          (outcome as DVStorePurchased).transaction;
      expect(transaction.store, DVStore.appStore);
      expect(transaction.receipt, 'eyJhbGciOiJFUzI1NiJ9.e30.sig');
      expect(transaction.transactionId, '2000000123');
    });

    test('pending and cancelled are what StoreKit said', () {
      expect(dvStoreKitOutcome(<String, Object?>{'outcome': 'pending'}),
          isA<DVStorePending>());
      expect(dvStoreKitOutcome(<String, Object?>{'outcome': 'cancelled'}),
          isA<DVStoreCancelled>());
    });

    test('anything else is a failure with its reason, never a cancel', () {
      final DVStorePurchaseOutcome outcome = dvStoreKitOutcome(
          <String, Object?>{'outcome': 'failed', 'reason': 'no product'});
      expect((outcome as DVStoreFailed).reason, 'no product');
      expect(dvStoreKitOutcome(<String, Object?>{'error': 'boom'}),
          isA<DVStoreFailed>());
      expect(dvStoreKitOutcome(<String, Object?>{'outcome': 'surprise'}),
          isA<DVStoreFailed>());
    });
  });

  test('owned transactions and drained updates read the same shape', () {
    final List<DVStoreDeviceTransaction> owned =
        dvStoreKitTransactions(<String, Object?>{
      'transactions': <Object?>[
        <String, Object?>{
          'storeProductId': 'a',
          'transactionId': '1',
          'receipt': 'jws-a',
          'state': 'purchased',
        },
      ],
    }['transactions']);
    final List<DVStoreDeviceTransaction> drained =
        dvStoreKitTransactions(<Object?>[
      <String, Object?>{
        'storeProductId': 'b',
        'transactionId': '2',
        'receipt': 'jws-b',
        'state': 'purchased',
      },
    ]);
    expect(owned.single.receipt, 'jws-a');
    expect(drained.single.storeProductId, 'b');
  });

  test('a request is one JSON object with its operation', () {
    expect(dvStoreKitRequest('listings', <String, Object?>{
      'ids': <String>['a'],
    }), '{"op":"listings","ids":["a"]}');
  });
}
