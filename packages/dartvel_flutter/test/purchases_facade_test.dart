// DV.Purchases is the purchase surface, and it is configured, not assumed.
//
// A facade that answered with a default when nothing was configured would
// have to invent a ledger and a store to verify against, and the only store
// that needs no configuration is one that believes whatever it is told.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const Entitlement analytics = Entitlement('analytics');

void main() {
  tearDown(DVPurchases.unconfigure);

  test('DV.Purchases refuses to answer before it is configured', () {
    expect(() => DV.Purchases, throwsStateError);
  });

  test('DV.Purchases is the configured purchases', () async {
    final DVFakeStoreAdapter play = DVFakeStoreAdapter(
      DVStore.play,
      signingKey: 'k',
      acknowledgementWindow: const Duration(days: 3),
    );
    final DateTime now = DateTime.utc(2026, 9, 14, 12);
    final DVPurchases purchases = DVPurchases(
      products: const <DVPurchaseProduct>[
        DVPurchaseProduct(
          'book_pro',
          billable: DVBillable.digital(play: 'book_pro'),
          entitlements: <Entitlement>{analytics},
        ),
      ],
      stores: <DVStoreAdapter>[play],
      ledger: DVMemoryPurchaseLedger(),
      clock: () => now,
    );
    DVPurchases.configure(purchases);
    play.issue(
      'r1',
      DVStoreTransaction(
        store: DVStore.play,
        originalTransactionId: 'otx_1',
        transactionId: 'otx_1_1',
        storeProductId: 'book_pro',
        purchasedAt: now,
        signedAt: now,
        expiresAt: now.add(const Duration(days: 30)),
      ),
    );

    await DV.Purchases.verifyPurchase(DVStore.play, 'r1', customer: 'alice');

    expect(identical(DV.Purchases, purchases), isTrue);
    expect(await DV.Purchases.entitled('alice', analytics), isTrue);
  });
}
