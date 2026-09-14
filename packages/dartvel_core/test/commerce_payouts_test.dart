// Payouts: splitting what was collected, and paying it out once.
//
// Funds never flow through the application -- a connected-account provider
// moves them -- but the application decides how much, and that decision can
// be silently wrong. A split rounded per recipient hands out a cent more or
// less than was collected. A sale webhook delivered twice credits the seller
// twice, and the next payout pays both. Two payout runs at once both see the
// same balance and both transfer it. A refund after a payout is forgotten
// because the seller's share was already sent. A payout to an account that
// has not finished verification is attempted and fails in front of somebody
// who expected money, instead of being held (DV-COMMERCE-006).
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVMoney usd(int amount) => DVMoney(amount: amount, currency: 'USD');

class FakeConnect implements DVConnectedAccountProvider {
  final Map<String, DVConnectedAccount> accounts = <String, DVConnectedAccount>{
    'acct_a': const DVConnectedAccount(
        id: 'acct_a',
        status: DVConnectedAccountStatus.verified,
        payoutsEnabled: true),
    'acct_b': const DVConnectedAccount(
        id: 'acct_b',
        status: DVConnectedAccountStatus.verified,
        payoutsEnabled: true),
  };
  final Map<String, DVTransfer> transfers = <String, DVTransfer>{};
  int transferCalls = 0;
  bool failTransfers = false;

  int transferredTo(String account) => transfers.values
      .where((DVTransfer t) => t.accountId == account)
      .fold<int>(0, (int s, DVTransfer t) => s + t.amount.amount);

  @override
  Future<DVConnectedAccount> account(String accountId) async =>
      accounts[accountId]!;

  @override
  Future<DVTransfer> transfer({
    required String accountId,
    required DVMoney amount,
    required String idempotencyKey,
  }) async {
    transferCalls++;
    await Future<void>.delayed(Duration.zero);
    if (failTransfers) throw StateError('transfer failed');
    return transfers.putIfAbsent(
      idempotencyKey,
      () => DVTransfer(
        reference: 'tr_${transfers.length + 1}',
        accountId: accountId,
        amount: amount,
      ),
    );
  }
}

void main() {
  final DateTime now = DateTime.utc(2026, 9, 14, 12);
  late DVMemoryLogSink logs;
  late FakeConnect connect;
  late DVMemoryPayoutLedger ledger;
  late DVPayouts payouts;

  final DVPayoutSplit split = DVPayoutSplit(
    recipients: const <String, int>{'acct_a': 2, 'acct_b': 1},
    platformFeeBasisPoints: 1000,
  );

  List<String> codes() =>
      logs.records.map((DVLogRecord r) => r.code).whereType<String>().toList();

  setUp(() {
    logs = DVMemoryLogSink();
    connect = FakeConnect();
    ledger = DVMemoryPayoutLedger();
    payouts = DVPayouts(
      ledger: ledger,
      provider: connect,
      clock: () => now,
      logger: DVLogger(sinks: <DVLogSink>[logs]),
    );
  });

  Future<DVPayoutResult> pay(String account, String key) =>
      payouts.payout(accountId: account, currency: 'USD', key: key);

  group('a split', () {
    test('takes the fee, then divides the rest by weight', () {
      final Map<String, DVMoney> shares = split.allocate(usd(1000));
      expect(shares[DVPayouts.platform], usd(100));
      expect(shares['acct_a'], usd(600));
      expect(shares['acct_b'], usd(300));
    });

    test('always sums to what was collected', () {
      final DVPayoutSplit awkward = DVPayoutSplit(
        recipients: const <String, int>{'a': 1, 'b': 1, 'c': 1},
        platformFeeBasisPoints: 333,
        platformFixedFee: usd(7),
      );
      for (int collected = 0; collected < 3000; collected += 13) {
        final Map<String, DVMoney> shares = awkward.allocate(usd(collected));
        expect(
          shares.values.fold<int>(0, (int s, DVMoney m) => s + m.amount),
          collected,
          reason: '$collected',
        );
      }
      // A third of a cent each would round to nothing three times.
      final Map<String, DVMoney> ten = DVPayoutSplit(
        recipients: const <String, int>{'a': 1, 'b': 1, 'c': 1},
      ).allocate(usd(10));
      expect(
          <int>[for (final String k in <String>['a', 'b', 'c']) ten[k]!.amount],
          <int>[4, 3, 3]);
    });

    test('a fixed fee larger than the sale takes the sale, not more', () {
      final Map<String, DVMoney> shares = DVPayoutSplit(
        recipients: const <String, int>{'a': 1},
        platformFixedFee: usd(50),
      ).allocate(usd(30));
      expect(shares[DVPayouts.platform], usd(30));
      expect(shares['a'], usd(0));
    });

    test('is declared sensibly or not at all', () {
      expect(() => DVPayoutSplit(recipients: const <String, int>{}),
          throwsArgumentError);
      expect(
          () => DVPayoutSplit(
              recipients: const <String, int>{DVPayouts.platform: 1}),
          throwsArgumentError);
      expect(() => DVPayoutSplit(recipients: const <String, int>{'a': 0}),
          throwsArgumentError);
      expect(
          () => DVPayoutSplit(
              recipients: const <String, int>{'a': 1},
              platformFeeBasisPoints: 10001),
          throwsArgumentError);
    });
  });

  group('the ledger', () {
    test('a sale recorded twice is credited once', () async {
      expect(
          await payouts.recordSale(
              saleId: 's1', collected: usd(1000), split: split),
          isTrue);
      expect(
          await payouts.recordSale(
              saleId: 's1', collected: usd(1000), split: split),
          isFalse);
      expect(await payouts.balance('acct_a', 'USD'), 600);
    });

    test('a sale recorded twice with different amounts is an error', () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      await expectLater(
        payouts.recordSale(saleId: 's1', collected: usd(900), split: split),
        throwsStateError,
      );
    });

    test('refunds reverse every share, and in full leave nothing', () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      for (int i = 0; i < 3; i++) {
        await payouts.recordRefund(
            saleId: 's1', refundId: 'r$i', amount: usd(333));
      }
      await payouts.recordRefund(saleId: 's1', refundId: 'r3', amount: usd(1));
      for (final String account in <String>[
        'acct_a',
        'acct_b',
        DVPayouts.platform,
      ]) {
        expect(await payouts.balance(account, 'USD'), 0, reason: account);
      }
    });

    test('each refund reverses exactly its amount', () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      await payouts.recordRefund(
          saleId: 's1', refundId: 'r1', amount: usd(333));
      final int total = ledger.entries
          .where((DVPayoutEntry e) => e.reference == 'r1')
          .fold<int>(0, (int s, DVPayoutEntry e) => s + e.amount);
      expect(total, -333);
    });

    test('a refund is recorded once, and not past what was collected',
        () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      await payouts.recordRefund(
          saleId: 's1', refundId: 'r1', amount: usd(600));
      expect(
          await payouts.recordRefund(
              saleId: 's1', refundId: 'r1', amount: usd(600)),
          isFalse);
      await expectLater(
        payouts.recordRefund(saleId: 's1', refundId: 'r2', amount: usd(401)),
        throwsA(isA<DVRefundRefused>()),
      );
      expect(await payouts.balance('acct_a', 'USD'), 240);
    });
  });

  group('a payout', () {
    test('pays the balance once, however often it is asked', () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      // The sale webhook arrives again.
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      final DVPayoutResult first = await pay('acct_a', 'daily-2026-09-14');
      final DVPayoutResult again = await pay('acct_a', 'daily-2026-09-14');
      expect(first.status, DVPayoutStatus.paid);
      expect(first.amount, usd(600));
      expect(again.status, DVPayoutStatus.alreadyPaid);
      expect(connect.transferCalls, 1);
      expect(connect.transferredTo('acct_a'), 600);

      final DVPayoutResult next = await pay('acct_a', 'daily-2026-09-15');
      expect(next.status, DVPayoutStatus.nothingDue);
      expect(connect.transferredTo('acct_a'), 600);
    });

    test('run several times at once transfers the balance once', () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      final List<DVPayoutResult> results =
          await Future.wait(<Future<DVPayoutResult>>[
        for (int i = 0; i < 4; i++) pay('acct_a', 'run-$i'),
        for (int i = 0; i < 3; i++) pay('acct_a', 'same-key'),
      ]);
      expect(connect.transferredTo('acct_a'), 600);
      expect(connect.transfers, hasLength(1));
      expect(
          results
              .where((DVPayoutResult r) => r.status == DVPayoutStatus.paid)
              .map((DVPayoutResult r) => r.transferReference)
              .toSet(),
          hasLength(1));
    });

    test('to an unverified account is held, not attempted', () async {
      connect.accounts['acct_a'] = const DVConnectedAccount(
        id: 'acct_a',
        status: DVConnectedAccountStatus.pending,
      );
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      final DVPayoutResult result = await pay('acct_a', 'k');
      expect(result.status, DVPayoutStatus.held);
      expect(result.amount, usd(600));
      expect(connect.transferCalls, 0);
      expect(codes(), <String>['DV-COMMERCE-006']);
      expect(logs.records.single.level, DVLogLevel.warn);
      expect(await payouts.balance('acct_a', 'USD'), 600);

      // Verified with payouts still disabled is not verified enough.
      connect.accounts['acct_a'] = const DVConnectedAccount(
        id: 'acct_a',
        status: DVConnectedAccountStatus.verified,
      );
      expect((await pay('acct_a', 'k')).status, DVPayoutStatus.held);
      expect(connect.transferCalls, 0);
    });

    test('that fails gives the balance back, and the retry pays it', () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      connect.failTransfers = true;
      await expectLater(pay('acct_a', 'k'), throwsStateError);
      expect(await payouts.balance('acct_a', 'USD'), 600);
      connect.failTransfers = false;
      final DVPayoutResult retried = await pay('acct_a', 'k');
      expect(retried.amount, usd(600));
      expect(await payouts.balance('acct_a', 'USD'), 0);
    });

    test('leaves out a sale on hold, and pays it when released', () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      await payouts.recordSale(saleId: 's2', collected: usd(500), split: split);
      await payouts.hold('s2', reason: 'dispute dp_1');
      expect((await pay('acct_a', 'k1')).amount, usd(600));
      await payouts.release('s2');
      expect((await pay('acct_a', 'k2')).amount, usd(300));
    });

    test('after a refund of a paid-out sale, recovers before paying again',
        () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      await pay('acct_a', 'k1');
      await payouts.recordRefund(
          saleId: 's1', refundId: 'r1', amount: usd(1000));
      expect(await payouts.balance('acct_a', 'USD'), -600);
      await payouts.recordSale(saleId: 's2', collected: usd(500), split: split);
      expect((await pay('acct_a', 'k2')).status, DVPayoutStatus.nothingDue);
      expect(connect.transferredTo('acct_a'), 600);
    });

    test('a lost dispute reverses the shares like a refund', () async {
      await payouts.recordSale(saleId: 's1', collected: usd(1000), split: split);
      await payouts.hold('s1', reason: 'dispute dp_1');
      await payouts.recordDisputeLoss(
          saleId: 's1', disputeId: 'dp_1', amount: usd(1000));
      await payouts.release('s1');
      expect(await payouts.balance('acct_a', 'USD'), 0);
      expect((await pay('acct_a', 'k')).status, DVPayoutStatus.nothingDue);
    });
  });
}
