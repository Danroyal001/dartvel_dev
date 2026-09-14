// The purchase ledger in the application's own database.
//
// The in-memory ledger proves the rules. This proves what makes a grant a
// grant rather than a variable: a restart keeps it, and two instances of the
// application behind one load balancer see one ledger -- so a store that
// retries a notification against the other instance is still told it is a
// replay, and a refund applied on one instance revokes on both.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const Entitlement analytics = Entitlement('analytics');

const DVPurchaseProduct pro = DVPurchaseProduct(
  'book_pro',
  billable: DVBillable.digital(play: 'book_pro'),
  entitlements: <Entitlement>{analytics},
);

void main() {
  final DateTime start = DateTime.utc(2026, 9, 14, 12, 0, 0, 0, 123);

  DVStoreTransaction bought({DateTime? revokedAt, DateTime? signedAt}) =>
      DVStoreTransaction(
        store: DVStore.play,
        originalTransactionId: 'otx_1',
        transactionId: 'otx_1_1',
        storeProductId: 'book_pro',
        purchasedAt: start,
        expiresAt: start.add(const Duration(days: 30)),
        revokedAt: revokedAt,
        acknowledged: revokedAt != null,
        signedAt: signedAt ?? start,
      );

  for (final (String name, DVDatabaseAdapter Function() open)
      in <(String, DVDatabaseAdapter Function())>[
    ('in-memory', MemoryDVDatabaseAdapter.new),
    ('sqlite', SqliteDVDatabaseAdapter.memory),
  ]) {
    group('on the $name adapter', () {
      late DVDatabaseAdapter db;
      late DVFakeStoreAdapter play;

      DVPurchases instance() => DVPurchases(
            products: const <DVPurchaseProduct>[pro],
            stores: <DVStoreAdapter>[play],
            ledger: DVDatabasePurchaseLedger(db),
            clock: () => start.add(const Duration(hours: 3)),
            logger: DVLogger(),
          );

      setUp(() {
        db = open();
        play = DVFakeStoreAdapter(
          DVStore.play,
          signingKey: 'k',
          acknowledgementWindow: const Duration(days: 3),
        );
      });

      test('a grant written by one instance is held on another', () async {
        play.issue('r1', bought());
        await instance().verifyPurchase(DVStore.play, 'r1', customer: 'alice');

        expect(await instance().entitled('alice', analytics), isTrue);
        expect(await instance().entitled('bob', analytics), isFalse);
      });

      test('the grant reads back exactly as it was written', () async {
        play.issue('r1', bought());
        await instance().verifyPurchase(DVStore.play, 'r1', customer: 'alice');

        final DVPurchaseGrant grant =
            (await DVDatabasePurchaseLedger(db).find(DVStore.play, 'otx_1'))!;
        expect(grant.customerKey, 'alice');
        expect(grant.productId, 'book_pro');
        expect(grant.transactionId, 'otx_1_1');
        expect(grant.purchasedAt, start);
        expect(grant.purchasedAt.isUtc, isTrue);
        expect(grant.notAfter, start.add(const Duration(days: 30)));
        expect(grant.revokedAt, isNull);
        expect(grant.acknowledged, isTrue);
        expect(await DVDatabasePurchaseLedger(db).forCustomer('alice'),
            hasLength(1));
      });

      test('a notification applied on one instance is a replay on another',
          () async {
        play.issue('r1', bought());
        await instance().verifyPurchase(DVStore.play, 'r1', customer: 'alice');
        final DateTime at = start.add(const Duration(hours: 1));
        final DVSignedStoreNotification refund = play.sign(DVStoreNotification(
          notificationId: 'n1',
          type: 'REFUND',
          signedAt: at,
          transaction: bought(revokedAt: at, signedAt: at),
        ));

        final DVPurchaseResult first = await instance().acceptNotification(
            DVContext(), DVStore.play,
            body: refund.body, headers: refund.headers);
        final DVPurchaseResult second = await instance().acceptNotification(
            DVContext(), DVStore.play,
            body: refund.body, headers: refund.headers);

        expect(first.handled, isTrue);
        expect(second.replayed, isTrue);
        expect(await instance().entitled('alice', analytics), isFalse);
      });

      test('a released claim can be claimed again', () async {
        final DVPurchaseLedger ledger = DVDatabasePurchaseLedger(db);
        expect(await ledger.claimNotification(DVStore.play, 'n1'), isTrue);
        expect(await ledger.claimNotification(DVStore.play, 'n1'), isFalse);
        // One store's id says nothing about another store's.
        expect(await ledger.claimNotification(DVStore.appStore, 'n1'), isTrue);
        await ledger.releaseNotification(DVStore.play, 'n1');
        expect(await ledger.claimNotification(DVStore.play, 'n1'), isTrue);
      });

      test('an unacknowledged grant survives for the sweep to find', () async {
        await DVDatabasePurchaseLedger(db).put(DVPurchaseGrant(
          store: DVStore.play,
          originalTransactionId: 'otx_5',
          transactionId: 'otx_5_1',
          customerKey: 'alice',
          productId: 'book_pro',
          storeProductId: 'book_pro',
          purchasedAt: start,
          notAfter: null,
          acknowledged: false,
          lastEventAt: start,
        ));

        final List<DVPurchaseGrant> pending =
            await DVDatabasePurchaseLedger(db).unacknowledged();
        expect(pending.single.originalTransactionId, 'otx_5');
        expect(pending.single.notAfter, isNull);
      });

      test('removing a grant removes only that one', () async {
        final DVPurchaseLedger ledger = DVDatabasePurchaseLedger(db);
        for (final String id in <String>['otx_1', 'otx_2']) {
          await ledger.put(DVPurchaseGrant(
            store: DVStore.play,
            originalTransactionId: id,
            transactionId: '${id}_1',
            customerKey: 'alice',
            productId: 'book_pro',
            storeProductId: 'book_pro',
            purchasedAt: start,
            notAfter: start,
            acknowledged: true,
            lastEventAt: start,
          ));
        }
        await ledger.remove(DVStore.play, 'otx_1');

        expect(await ledger.find(DVStore.play, 'otx_1'), isNull);
        expect(await ledger.find(DVStore.play, 'otx_2'), isNotNull);
      });
    });
  }
}
