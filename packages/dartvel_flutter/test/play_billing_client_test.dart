// What the Play Billing bridge answers, read into DV.Purchases' own types.
//
// The JNI half needs a device. This half does not, and it is where a wrong
// answer still looks like an answer: a price read through a double, a
// pending purchase read as paid, a consumable token lost on the way to
// consumeAsync.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/src/purchases/play_billing_jni.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('listings', () {
    test('a subscription carries its base price and its offers', () {
      final List<DVStoreListing> listed = dvPlayListings('''
{"listings": [{
  "storeProductId": "pro", "title": "Pro (Example)", "description": "All",
  "displayPrice": "\$4.99", "priceMicros": "4990000", "currency": "USD",
  "period": "P1M",
  "offers": [
    {"id": "monthly", "basePlanId": "monthly", "kind": "basePlan",
     "token": "tok-base", "displayPrice": "\$4.99", "priceMicros": "4990000",
     "currency": "USD", "period": "P1M", "periods": 1, "tags": [],
     "eligible": true},
    {"id": "trial", "basePlanId": "monthly", "kind": "freeTrial",
     "token": "tok-trial", "displayPrice": "Free", "priceMicros": "0",
     "currency": "USD", "period": "P1W", "periods": 1, "tags": ["trial"],
     "eligible": true}
  ]
}]}''');

      final DVStoreListing pro = listed.single;
      expect(pro.storeProductId, 'pro');
      expect(pro.price, DVMoney(amount: 499, currency: 'USD'));
      expect(pro.displayPrice, r'$4.99');
      expect(pro.period, 'P1M');
      expect(pro.offers, hasLength(2));
      final DVStoreOffer trial = pro.offers.last;
      expect(trial.kind, DVStoreOfferKind.freeTrial);
      expect(trial.token, 'tok-trial');
      expect(trial.price, DVMoney(amount: 0, currency: 'USD'));
      expect(trial.period, 'P1W');
    });

    test('a price is converted from micros exactly, in the currency exponent',
        () {
      final DVStoreListing yen = dvPlayListings('''
{"listings": [{"storeProductId": "coins", "title": "Coins",
  "displayPrice": "¥120", "priceMicros": "120000000", "currency": "JPY",
  "offers": []}]}''').single;
      expect(yen.price, DVMoney(amount: 120, currency: 'JPY'));
    });

    test('a price that is not whole minor units is shown without a number',
        () {
      // Rounding it would display one price above a sheet charging another.
      final DVStoreListing odd = dvPlayListings('''
{"listings": [{"storeProductId": "x", "title": "X", "displayPrice": "\$0.995",
  "priceMicros": "995000", "currency": "USD", "offers": []}]}''').single;
      expect(odd.price, isNull);
      expect(odd.displayPrice, r'$0.995');
    });
  });

  group('purchase outcomes', () {
    test('a purchase carries the transaction and its receipt', () {
      final DVStorePurchaseOutcome outcome = dvPlayPurchaseOutcome('''
{"outcome": "purchased", "transaction": {"storeProductId": "pro",
  "transactionId": "GPA.1", "state": "purchased", "quantity": 1,
  "receipt": "{\\"purchaseToken\\":\\"tok\\",\\"productId\\":\\"pro\\",\\"type\\":\\"subs\\",\\"orderId\\":\\"GPA.1\\"}"}}''');
      final DVStoreDeviceTransaction transaction =
          (outcome as DVStorePurchased).transaction;
      expect(transaction.store, DVStore.play);
      expect(transaction.transactionId, 'GPA.1');
      expect(dvPlayPurchaseTokenOf(transaction.receipt), 'tok');
    });

    test('pending, cancelled and failed are told apart', () {
      expect(dvPlayPurchaseOutcome('{"outcome":"pending"}'),
          isA<DVStorePending>());
      expect(dvPlayPurchaseOutcome('{"outcome":"cancelled"}'),
          isA<DVStoreCancelled>());
      expect(
          (dvPlayPurchaseOutcome('{"outcome":"failed","reason":"declined"}')
                  as DVStoreFailed)
              .reason,
          'declined');
    });

    test('a bridge error is a failure, not a purchase', () {
      expect(dvPlayPurchaseOutcome('{"error":"no Activity is resumed"}'),
          isA<DVStoreFailed>());
    });
  });

  test('owned purchases keep pending ones marked pending', () {
    final List<DVStoreDeviceTransaction> owned = dvPlayTransactions('''
[{"storeProductId": "coins", "transactionId": "t1", "state": "pending",
  "quantity": 2, "receipt": "{\\"purchaseToken\\":\\"t1\\"}"},
 {"storeProductId": "pro", "transactionId": "t2", "state": "purchased",
  "quantity": 1, "receipt": "{\\"purchaseToken\\":\\"t2\\"}"}]''');
    expect(owned.first.state, DVStoreTransactionState.pending);
    expect(owned.first.quantity, 2);
    expect(owned.last.state, DVStoreTransactionState.purchased);
  });

  test('a receipt with no token has none to consume', () {
    expect(dvPlayPurchaseTokenOf('not json'), isNull);
    expect(dvPlayPurchaseTokenOf('{"productId":"x"}'), isNull);
  });
}
