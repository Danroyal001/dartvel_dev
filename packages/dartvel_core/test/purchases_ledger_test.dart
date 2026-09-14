// A store purchase is granted from the store's answer, and only from it.
//
// The device reports what it bought; the server decides whether it did. Every
// failure worth a test here is silent: a receipt nobody verified, a refund
// that never revokes, a late notification that hands a refunded customer
// their access back, a replay that applies twice, a Play purchase granted
// and never acknowledged so the store refunds it three days later while the
// application goes on granting. None of them throws and all of them cost
// money.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const Entitlement analytics = Entitlement('analytics');
const Entitlement exports = Entitlement('exports');

const DVPurchaseProduct pro = DVPurchaseProduct(
  'book_pro',
  billable: DVBillable.digital(
    appStore: 'com.example.book.pro',
    play: 'book_pro',
  ),
  entitlements: <Entitlement>{analytics},
);

const DVPurchaseProduct lifetime = DVPurchaseProduct(
  'book_lifetime',
  billable: DVBillable.digital(
    appStore: 'com.example.book.lifetime',
    play: 'book_lifetime',
  ),
  entitlements: <Entitlement>{exports},
  kind: DVPurchaseKind.nonConsumable,
);

class User implements DVBillingCustomer {
  const User(this.id);
  final String id;

  @override
  String get billingCustomerId => 'user:$id';
}

const User alice = User('alice');
const User bob = User('bob');

final DateTime start = DateTime.utc(2026, 9, 14, 12);
late DateTime now;
late DVFakeStoreAdapter play;
late DVFakeStoreAdapter apple;
late DVMemoryLogSink logs;
late List<DVPurchaseChange> changes;
late DVPurchases purchases;

DVStoreTransaction transaction({
  DVStore store = DVStore.play,
  String original = 'otx_1',
  String? id,
  String product = 'book_pro',
  Duration? expiresIn = const Duration(days: 30),
  Duration? graceIn,
  DateTime? revokedAt,
  Object? owner,
  DateTime? signedAt,
  bool acknowledged = false,
}) =>
    DVStoreTransaction(
      store: store,
      originalTransactionId: original,
      transactionId: id ?? '${original}_1',
      storeProductId: product,
      purchasedAt: start,
      expiresAt: expiresIn == null ? null : start.add(expiresIn),
      graceEndsAt: graceIn == null ? null : start.add(graceIn),
      revokedAt: revokedAt,
      appAccountToken:
          owner == null ? null : DVPurchases.accountTokenFor(owner),
      acknowledged: acknowledged,
      signedAt: signedAt ?? now,
    );

Future<DVPurchaseResult> deliver(
  DVFakeStoreAdapter store, {
  required String id,
  required String type,
  required DVStoreTransaction transaction,
}) {
  final DVSignedStoreNotification signed = store.sign(DVStoreNotification(
    notificationId: id,
    type: type,
    signedAt: transaction.signedAt,
    transaction: transaction,
  ));
  return purchases.acceptNotification(
    DVContext(),
    store.store,
    body: signed.body,
    headers: signed.headers,
  );
}

List<String> codes() =>
    logs.records.map((DVLogRecord r) => r.code).whereType<String>().toList();

/// Alice buys pro on Play: thirty days, acknowledged as part of the grant.
Future<void> aliceBuysPro({Duration? graceIn}) async {
  play.issue('r1', transaction(owner: alice, graceIn: graceIn));
  await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);
}

void main() {
  setUp(() {
    now = start;
    play = DVFakeStoreAdapter(
      DVStore.play,
      signingKey: 'play-key',
      acknowledgementWindow: const Duration(days: 3),
    );
    apple = DVFakeStoreAdapter(DVStore.appStore, signingKey: 'apple-key');
    logs = DVMemoryLogSink();
    changes = <DVPurchaseChange>[];
    purchases = DVPurchases(
      products: const <DVPurchaseProduct>[pro, lifetime],
      stores: <DVStoreAdapter>[play, apple],
      ledger: DVMemoryPurchaseLedger(),
      clock: () => now,
      logger: DVLogger(sinks: <DVLogSink>[logs]),
      onChange: changes.add,
    );
  });

  group('a purchase is granted from the store\'s answer', () {
    test('a receipt the store validates grants that customer the product',
        () async {
      play.issue('r1', transaction(owner: alice));

      final DVPurchaseResult result =
          await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);

      expect(result.granted.map((Entitlement e) => e.id), <String>['analytics']);
      expect(await purchases.entitled(alice, analytics), isTrue);
      expect(await purchases.entitled(bob, analytics), isFalse);
      expect(await purchases.entitled(alice, exports), isFalse);
    });

    test('a receipt the store refuses writes nothing and says DV-PURCHASE-003',
        () async {
      play.refuse('forged', 'the purchase token is not valid');

      await expectLater(
        purchases.verifyPurchase(DVStore.play, 'forged', customer: alice),
        throwsA(isA<DVPurchaseRefused>()),
      );

      expect(await purchases.entitled(alice, analytics), isFalse);
      expect(codes(), contains('DV-PURCHASE-003'));
      expect(changes, isEmpty);
    });

    test('a store that cannot be reached is not a refusal and grants nothing',
        () async {
      play.issue('r1', transaction(owner: alice));
      play.unavailable = true;

      await expectLater(
        purchases.verifyPurchase(DVStore.play, 'r1', customer: alice),
        throwsA(isA<DVStoreUnavailable>()),
      );

      expect(await purchases.entitled(alice, analytics), isFalse);
      expect(codes(), isNot(contains('DV-PURCHASE-003')));
    });

    test('what was bought is what the store says, not what the device says',
        () async {
      // The device thinks it bought pro; the token is for lifetime.
      play.issue('r1',
          transaction(owner: alice, product: 'book_lifetime', expiresIn: null));

      await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);

      expect(await purchases.entitled(alice, exports), isTrue);
      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    test('a store answer that has already expired grants nothing', () async {
      now = start.add(const Duration(days: 31));
      play.issue('r1', transaction(owner: alice));

      final DVPurchaseResult result =
          await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);

      expect(result.granted, isEmpty);
      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    test('a store answer carrying a revocation grants nothing', () async {
      play.issue(
        'r1',
        transaction(owner: alice, revokedAt: start, acknowledged: true),
      );

      await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);

      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    test('a receipt bought under another application user grants nothing',
        () async {
      play.issue('r1', transaction(owner: bob));

      await expectLater(
        purchases.verifyPurchase(DVStore.play, 'r1', customer: alice),
        throwsA(isA<DVPurchaseRefused>().having(
            (DVPurchaseRefused e) => e.reason, 'reason', contains('another'))),
      );

      expect(await purchases.entitled(alice, analytics), isFalse);
      expect(await purchases.entitled(bob, analytics), isFalse);
      expect(await purchases.ledger.find(DVStore.play, 'otx_1'), isNull);
    });

    test('a purchase one user holds is not moved to the next user to present it',
        () async {
      play.issue('r1', transaction());
      await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);

      await expectLater(
        purchases.verifyPurchase(DVStore.play, 'r1', customer: bob),
        throwsA(isA<DVPurchaseRefused>()),
      );

      expect(await purchases.entitled(bob, analytics), isFalse);
      expect(await purchases.entitled(alice, analytics), isTrue);
    });

    test('a customer with no billing identity is refused, not filed under one',
        () async {
      play.issue('r1', transaction());

      await expectLater(
        purchases.verifyPurchase(DVStore.play, 'r1', customer: Object()),
        throwsArgumentError,
      );
    });

    test('an older store answer presented after a refund does not re-grant',
        () async {
      // StoreKit 2 hands the device a signed transaction it can keep. The one
      // signed before the refund is still genuinely Apple's signature.
      await aliceBuysPro();
      final DateTime refundedAt = start.add(const Duration(hours: 1));
      now = refundedAt;
      await deliver(
        play,
        id: 'n1',
        type: 'REFUND',
        transaction: transaction(
            revokedAt: refundedAt, acknowledged: true, signedAt: refundedAt),
      );

      final DVPurchaseResult result =
          await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);

      expect(result.stale, isTrue);
      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    test('a receipt presented to the wrong store is refused', () async {
      apple.issue('r1', transaction(store: DVStore.appStore, owner: alice));

      await expectLater(
        purchases.verifyPurchase(DVStore.play, 'r1', customer: alice),
        throwsA(isA<DVPurchaseRefused>()),
      );
      expect(await purchases.entitled(alice, analytics), isFalse);
    });
  });

  group('acknowledgement is part of the grant', () {
    test('a Play grant is acknowledged in the same step', () async {
      await aliceBuysPro();

      expect(play.acknowledged, <String>['otx_1_1']);
      expect(
        (await purchases.ledger.find(DVStore.play, 'otx_1'))!.acknowledged,
        isTrue,
      );
    });

    test('when acknowledgement fails the grant is released', () async {
      play.issue('r1', transaction(owner: alice));
      play.failAcknowledgements = true;

      await expectLater(
        purchases.verifyPurchase(DVStore.play, 'r1', customer: alice),
        throwsA(isA<DVStoreUnavailable>()),
      );

      expect(await purchases.entitled(alice, analytics), isFalse);
      expect(await purchases.ledger.find(DVStore.play, 'otx_1'), isNull);
      expect(changes, isEmpty);
    });

    test('the App Store needs no acknowledgement and gets none', () async {
      apple.issue(
        'r1',
        transaction(
          store: DVStore.appStore,
          product: 'com.example.book.pro',
          owner: alice,
        ),
      );

      await purchases.verifyPurchase(DVStore.appStore, 'r1', customer: alice);

      expect(apple.acknowledged, isEmpty);
      expect(await purchases.entitled(alice, analytics), isTrue);
    });

    test('an already acknowledged purchase is not acknowledged again',
        () async {
      play.issue('r1', transaction(owner: alice, acknowledged: true));

      await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);

      expect(play.acknowledged, isEmpty);
      expect(await purchases.entitled(alice, analytics), isTrue);
    });

    DVPurchaseGrant unacknowledged(DateTime purchasedAt) => DVPurchaseGrant(
          store: DVStore.play,
          originalTransactionId: 'otx_5',
          transactionId: 'otx_5_1',
          customerKey: 'user:alice',
          productId: 'book_pro',
          storeProductId: 'book_pro',
          purchasedAt: purchasedAt,
          notAfter: purchasedAt.add(const Duration(days: 30)),
          acknowledged: false,
          lastEventAt: purchasedAt,
        );

    test('an acknowledgement still missing inside the window is retried',
        () async {
      await purchases.ledger.put(unacknowledged(start));
      now = start.add(const Duration(days: 2));

      final List<DVPurchaseGrant> late = await purchases.checkAcknowledgements();

      expect(late, isEmpty);
      expect(play.acknowledged, <String>['otx_5_1']);
      expect(
        (await purchases.ledger.find(DVStore.play, 'otx_5'))!.acknowledged,
        isTrue,
      );
      expect(codes(), isNot(contains('DV-PURCHASE-006')));
    });

    test('one still missing when the window closes is DV-PURCHASE-006',
        () async {
      await purchases.ledger.put(unacknowledged(start));
      now = start.add(const Duration(days: 3, minutes: 1));

      final List<DVPurchaseGrant> late = await purchases.checkAcknowledgements();

      expect(late.map((DVPurchaseGrant g) => g.originalTransactionId),
          <String>['otx_5']);
      final DVLogRecord record = logs.records
          .singleWhere((DVLogRecord r) => r.code == 'DV-PURCHASE-006');
      expect(record.level, DVLogLevel.error);
    });
  });

  group('store notifications write the same ledger', () {
    test('a renewal carries access past the old period', () async {
      await aliceBuysPro();
      await deliver(
        play,
        id: 'n1',
        type: 'SUBSCRIPTION_RENEWED',
        transaction: transaction(
          id: 'otx_1_2',
          expiresIn: const Duration(days: 60),
          acknowledged: true,
          signedAt: start.add(const Duration(days: 29)),
        ),
      );

      now = start.add(const Duration(days: 31));
      expect(await purchases.entitled(alice, analytics), isTrue);
    });

    test('with no renewal, access ends at the end of the paid period',
        () async {
      await aliceBuysPro();

      now = start.add(const Duration(days: 30));
      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    test('the store\'s grace period is added to the paid period', () async {
      await aliceBuysPro(graceIn: const Duration(days: 36));

      now = start.add(const Duration(days: 33));
      expect(await purchases.entitled(alice, analytics), isTrue);
      now = start.add(const Duration(days: 37));
      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    for (final String type in <String>['REFUND', 'REVOKE', 'CHARGEBACK']) {
      test('a $type revokes access', () async {
        await aliceBuysPro();
        final DateTime at = start.add(const Duration(hours: 1));
        now = at;

        final DVPurchaseResult result = await deliver(
          play,
          id: 'n1',
          type: type,
          transaction: transaction(
            revokedAt: at,
            acknowledged: true,
            signedAt: at,
          ),
        );

        expect(result.revoked.map((Entitlement e) => e.id), <String>['analytics']);
        expect(await purchases.entitled(alice, analytics), isFalse);
        expect(changes.last.revoked, <String>{'analytics'});
        expect(changes.last.customerKey, 'user:alice');
      });
    }

    test('the same notification delivered twice is recognised as a replay',
        () async {
      await aliceBuysPro();
      final DVStoreTransaction renewed = transaction(
        id: 'otx_1_2',
        expiresIn: const Duration(days: 60),
        acknowledged: true,
        signedAt: start.add(const Duration(days: 29)),
      );

      final DVPurchaseResult first = await deliver(play,
          id: 'n1', type: 'SUBSCRIPTION_RENEWED', transaction: renewed);
      final DVPurchaseResult second = await deliver(play,
          id: 'n1', type: 'SUBSCRIPTION_RENEWED', transaction: renewed);

      expect(first.handled, isTrue);
      expect(first.replayed, isFalse);
      expect(second.handled, isFalse);
      expect(second.replayed, isTrue);
    });

    test('a replayed refund does not undo a later resubscription', () async {
      await aliceBuysPro();
      final DateTime refundedAt = start.add(const Duration(hours: 1));
      final DVStoreTransaction refunded = transaction(
          revokedAt: refundedAt, acknowledged: true, signedAt: refundedAt);
      await deliver(play, id: 'n1', type: 'REFUND', transaction: refunded);

      now = start.add(const Duration(hours: 2));
      await deliver(
        play,
        id: 'n2',
        type: 'SUBSCRIPTION_RECOVERED',
        transaction: transaction(
          id: 'otx_1_2',
          expiresIn: const Duration(days: 30),
          acknowledged: true,
          signedAt: now,
        ),
      );
      await deliver(play, id: 'n1', type: 'REFUND', transaction: refunded);

      expect(await purchases.entitled(alice, analytics), isTrue);
    });

    test('a notification older than one already applied changes nothing',
        () async {
      await aliceBuysPro();
      final DateTime refundedAt = start.add(const Duration(hours: 2));
      now = refundedAt;
      await deliver(
        play,
        id: 'refund',
        type: 'REFUND',
        transaction: transaction(
            revokedAt: refundedAt, acknowledged: true, signedAt: refundedAt),
      );

      // Sent before the refund, delivered after it: a retried renewal.
      final DVPurchaseResult late = await deliver(
        play,
        id: 'renewal',
        type: 'SUBSCRIPTION_RENEWED',
        transaction: transaction(
          id: 'otx_1_2',
          expiresIn: const Duration(days: 60),
          acknowledged: true,
          signedAt: start.add(const Duration(hours: 1)),
        ),
      );

      expect(late.stale, isTrue);
      expect(late.handled, isFalse);
      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    test('two different notifications in the same millisecond both apply',
        () async {
      await aliceBuysPro();
      final DateTime at = start.add(const Duration(hours: 1));
      now = at;

      await deliver(
        play,
        id: 'renewal',
        type: 'SUBSCRIPTION_RENEWED',
        transaction: transaction(
          id: 'otx_1_2',
          expiresIn: const Duration(days: 60),
          acknowledged: true,
          signedAt: at,
        ),
      );
      await deliver(
        play,
        id: 'refund',
        type: 'REFUND',
        transaction: transaction(
          id: 'otx_1_2',
          expiresIn: const Duration(days: 60),
          revokedAt: at,
          acknowledged: true,
          signedAt: at,
        ),
      );

      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    test('a notification whose signature does not match changes nothing',
        () async {
      await aliceBuysPro();
      final DateTime at = start.add(const Duration(hours: 1));
      final DVSignedStoreNotification refund = play.sign(DVStoreNotification(
        notificationId: 'n1',
        type: 'REFUND',
        signedAt: at,
        transaction:
            transaction(revokedAt: at, acknowledged: true, signedAt: at),
      ));
      final DVSignedStoreNotification test = play.sign(DVStoreNotification(
        notificationId: 'n2',
        type: 'TEST',
        signedAt: at,
        transaction: transaction(acknowledged: true, signedAt: at),
      ));

      // The refund's body under another notification's signature.
      await expectLater(
        purchases.acceptNotification(DVContext(), DVStore.play,
            body: refund.body, headers: test.headers),
        throwsA(isA<DVPurchaseRefused>()),
      );
      await expectLater(
        purchases.acceptNotification(DVContext(), DVStore.play,
            body: refund.body, headers: const <String, String>{}),
        throwsA(isA<DVPurchaseRefused>()),
      );

      expect(await purchases.entitled(alice, analytics), isTrue);
    });

    test('a notification for an undeclared product is DV-PURCHASE-004',
        () async {
      final DVPurchaseResult result = await deliver(
        play,
        id: 'n1',
        type: 'SUBSCRIPTION_PURCHASED',
        transaction: transaction(original: 'otx_9', product: 'book_deluxe'),
      );

      expect(result.undeclared, isTrue);
      expect(result.handled, isFalse);
      expect(codes(), contains('DV-PURCHASE-004'));
      expect(await purchases.ledger.find(DVStore.play, 'otx_9'), isNull);
    });

    test('a notification for a purchase nobody has validated grants nothing',
        () async {
      final DVPurchaseResult result = await deliver(
        play,
        id: 'n1',
        type: 'SUBSCRIPTION_PURCHASED',
        transaction: transaction(original: 'otx_7', owner: alice),
      );

      expect(result.handled, isFalse);
      expect(result.unattributed, isTrue);
      expect(await purchases.ledger.find(DVStore.play, 'otx_7'), isNull);
      expect(await purchases.entitled(alice, analytics), isFalse);
    });

    test('a notification that failed to acknowledge applies when retried',
        () async {
      await aliceBuysPro();
      now = start.add(const Duration(days: 31));
      final DVStoreTransaction resubscribed = transaction(
        id: 'otx_1_2',
        expiresIn: const Duration(days: 62),
        signedAt: now,
      );

      play.failAcknowledgements = true;
      await expectLater(
        deliver(play,
            id: 'n1', type: 'SUBSCRIPTION_RESTARTED', transaction: resubscribed),
        throwsA(isA<DVStoreUnavailable>()),
      );
      expect(await purchases.entitled(alice, analytics), isFalse);
      // Put back as it was, not deleted: the thirty days alice paid for.
      expect(
        (await purchases.ledger.find(DVStore.play, 'otx_1'))!.notAfter,
        start.add(const Duration(days: 30)),
      );

      play.failAcknowledgements = false;
      final DVPurchaseResult retried = await deliver(play,
          id: 'n1', type: 'SUBSCRIPTION_RESTARTED', transaction: resubscribed);

      expect(retried.replayed, isFalse);
      expect(await purchases.entitled(alice, analytics), isTrue);
    });
  });

  group('restore', () {
    test('revalidates each receipt and grants what this customer owns',
        () async {
      play.issue('r1', transaction(owner: alice));
      play.issue(
        'r2',
        transaction(
            original: 'otx_2', product: 'book_lifetime', expiresIn: null),
      );

      final List<DVPurchaseResult> results = await purchases.restore(
        customer: alice,
        store: DVStore.play,
        receipts: const <String>['r1', 'r2'],
      );

      expect(results.every((DVPurchaseResult r) => !r.refused), isTrue);
      expect(await purchases.entitled(alice, analytics), isTrue);
      expect(await purchases.entitled(alice, exports), isTrue);
    });

    test('a receipt held by another user grants nothing and says so',
        () async {
      play.issue('r1', transaction());
      await purchases.verifyPurchase(DVStore.play, 'r1', customer: bob);
      play.refuse('r2', 'expired token');

      final List<DVPurchaseResult> results = await purchases.restore(
        customer: alice,
        store: DVStore.play,
        receipts: const <String>['r1', 'r2'],
      );

      expect(results.map((DVPurchaseResult r) => r.refused), <bool>[true, true]);
      expect(results.first.reason, contains('another'));
      expect(await purchases.entitled(alice, analytics), isFalse);
      expect(await purchases.entitled(bob, analytics), isTrue);
    });
  });

  group('snapshots', () {
    test('carry notAfter from the paid period with the store grace added',
        () async {
      await aliceBuysPro(graceIn: const Duration(days: 36));

      final List<DVEntitlementSnapshot> snapshots =
          await purchases.snapshots(alice);

      expect(snapshots.single.entitlement, 'analytics');
      expect(snapshots.single.notAfter, start.add(const Duration(days: 36)));
    });

    test('leave out what was revoked or has lapsed', () async {
      await aliceBuysPro();
      final DateTime at = start.add(const Duration(hours: 1));
      now = at;
      await deliver(play,
          id: 'n1',
          type: 'REFUND',
          transaction:
              transaction(revokedAt: at, acknowledged: true, signedAt: at));

      expect(await purchases.snapshots(alice), isEmpty);
    });

    test('bound a purchase that never expires, so a refund still reaches it',
        () async {
      play.issue(
        'r1',
        transaction(product: 'book_lifetime', expiresIn: null, owner: alice),
      );
      await purchases.verifyPurchase(DVStore.play, 'r1', customer: alice);

      final DVEntitlementSnapshot snapshot =
          (await purchases.snapshots(alice)).single;

      expect(snapshot.notAfter, now.add(purchases.perpetualSnapshotLifetime));
    });
  });
}
