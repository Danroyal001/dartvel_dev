/// Marketplace payouts: split what was collected, keep a ledger, and let a
/// connected-account provider move the money.
///
/// A marketplace that holds a seller's money is a money transmitter, so funds
/// never flow through the application: a [DVConnectedAccountProvider] --
/// Stripe Connect and its equivalents -- transfers from the platform's
/// balance at the provider to the seller's. What the application holds is the
/// decision about how much, and that decision is where money goes missing
/// without an error. A split rounded per recipient hands out a cent the sale
/// never collected; a sale webhook delivered twice credits the seller twice;
/// two payout runs at once transfer one balance twice; a refund after a
/// payout is forgotten because the seller's share already left.
///
/// So: a split allocates by largest remainder and sums to what was collected;
/// a sale, a refund and a lost dispute are each recorded once by their id; a
/// refund reverses every share in proportion, cumulatively, so a sale refunded
/// in full reverses exactly what it credited; a payout reserves the available
/// balance as one step and transfers under an idempotency key the caller
/// names; and a payout to an account whose verification is not complete is
/// held rather than attempted (`DV-COMMERCE-006`).
///
/// What is not here: onboarding documents and verification state beyond the
/// status a provider reports. Those are sensitive model fields, which this
/// runtime does not hold.
library dartvel.commerce.payouts;

import 'dart:async';

import '../billing/money.dart';
import '../observability/observability.dart';
import '../transaction/transaction.dart';
import 'exact.dart';

/// A refund, or a reversal of payout shares, larger than what is left.
class DVRefundRefused implements Exception {
  const DVRefundRefused({
    required this.saleId,
    required this.remaining,
    required this.reason,
  });

  final String saleId;

  /// What can still be refunded or reversed.
  final DVMoney remaining;
  final String reason;

  @override
  String toString() =>
      'DVRefundRefused: $saleId: $reason ($remaining remaining)';
}

/// Where a connected account's verification stands, as the provider reports.
enum DVConnectedAccountStatus { unverified, pending, verified, restricted }

/// A seller's account at the payments provider.
class DVConnectedAccount {
  const DVConnectedAccount({
    required this.id,
    required this.status,
    this.payoutsEnabled = false,
  });

  final String id;
  final DVConnectedAccountStatus status;

  /// Whether the provider will pay this account out. A verified account with
  /// payouts disabled is not payable.
  final bool payoutsEnabled;

  /// Verified, and the provider says payouts are enabled.
  bool get canReceivePayouts =>
      status == DVConnectedAccountStatus.verified && payoutsEnabled;

  @override
  String toString() => 'DVConnectedAccount($id, ${status.name})';
}

/// A transfer the provider made.
class DVTransfer {
  const DVTransfer({
    required this.reference,
    required this.accountId,
    required this.amount,
  });

  final String reference;
  final String accountId;
  final DVMoney amount;
}

/// A connected-account provider.
abstract class DVConnectedAccountProvider {
  /// The account's current standing, read from the provider.
  Future<DVConnectedAccount> account(String accountId);

  /// Moves [amount] to [accountId] at the provider. [idempotencyKey] is passed
  /// through, so a repeated key is the first transfer rather than a second.
  Future<DVTransfer> transfer({
    required String accountId,
    required DVMoney amount,
    required String idempotencyKey,
  });
}

/// How a sale's collected amount is divided.
class DVPayoutSplit {
  DVPayoutSplit({
    required Map<String, int> recipients,
    this.platformFeeBasisPoints = 0,
    this.platformFixedFee,
  }) : recipients = Map<String, int>.unmodifiable(recipients) {
    if (recipients.isEmpty) {
      throw ArgumentError.value(recipients, 'recipients', 'names nobody');
    }
    for (final MapEntry<String, int> r in recipients.entries) {
      if (r.key == DVPayouts.platform || r.key.isEmpty) {
        throw ArgumentError.value(r.key, 'recipients',
            'is not a connected account id; the platform takes its fee');
      }
      if (r.value < 1) {
        throw ArgumentError.value(r.value, 'recipients',
            'weight of ${r.key} is not positive; leave the recipient out');
      }
    }
    if (platformFeeBasisPoints < 0 || platformFeeBasisPoints > 10000) {
      throw ArgumentError.value(platformFeeBasisPoints,
          'platformFeeBasisPoints', 'is between 0 and 10000');
    }
  }

  /// Connected account id to its weight in what is left after the fee.
  final Map<String, int> recipients;

  /// The platform's percentage, in hundredths of a percent.
  final int platformFeeBasisPoints;

  /// A fixed amount the platform takes on top of the percentage.
  final DVMoney? platformFixedFee;

  /// [collected], divided: the platform's fee under [DVPayouts.platform] and
  /// the rest by weight. Always sums to [collected].
  ///
  /// The percentage is rounded once, half up, the fixed fee added and the
  /// total capped at [collected]; the remainder is allocated by largest
  /// remainder, the earlier-declared recipient first on a tie.
  Map<String, DVMoney> allocate(DVMoney collected) {
    final DVMoney? fixed = platformFixedFee;
    if (fixed != null && fixed.currency != collected.currency) {
      throw ArgumentError.value(fixed, 'platformFixedFee',
          'is not in ${collected.currency}, the currency collected');
    }
    final int percentage = DVExact(
      BigInt.from(collected.amount) * BigInt.from(platformFeeBasisPoints),
      BigInt.from(10000),
    ).round(halfEven: false);
    final int wanted = percentage + (fixed?.amount ?? 0);
    final int fee = wanted < collected.amount ? wanted : collected.amount;
    final List<String> ids = recipients.keys.toList();
    final List<int> shares = dvAllocateByWeight(collected.amount - fee,
        <int>[for (final String id in ids) recipients[id]!]);
    DVMoney money(int amount) =>
        DVMoney(amount: amount, currency: collected.currency);
    return <String, DVMoney>{
      DVPayouts.platform: money(fee),
      for (int i = 0; i < ids.length; i++) ids[i]: money(shares[i]),
    };
  }
}

enum DVPayoutEntryKind { sale, refund, disputeLoss, payout }

/// One line of the payout ledger. [amount] is signed: a credit is positive,
/// a reversal or a payout negative.
class DVPayoutEntry {
  const DVPayoutEntry({
    required this.id,
    required this.accountId,
    required this.currency,
    required this.amount,
    required this.kind,
    required this.reference,
    required this.at,
    this.saleId,
  });

  final String id;

  /// A connected account id, or [DVPayouts.platform].
  final String accountId;
  final String currency;
  final int amount;
  final DVPayoutEntryKind kind;

  /// The sale, refund, dispute or payout id this entry records.
  final String reference;

  /// The sale the entry belongs to, so a hold on the sale holds it.
  final String? saleId;
  final DateTime at;
}

/// A sale as the payout ledger knows it: what it collected and how that was
/// divided.
class DVPayoutSaleRecord {
  DVPayoutSaleRecord({
    required this.saleId,
    required this.collected,
    required Map<String, int> shares,
    this.reversed = 0,
  }) : shares = Map<String, int>.unmodifiable(shares);

  final String saleId;
  final DVMoney collected;
  final Map<String, int> shares;

  /// How much of [collected] refunds and lost disputes have reversed.
  final int reversed;
}

/// A payout, reserved or completed.
class DVPayoutRecord {
  const DVPayoutRecord({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.at,
    this.transferReference,
  });

  final String id;
  final String accountId;
  final DVMoney amount;
  final DateTime at;

  /// The provider's transfer, once made.
  final String? transferReference;
}

/// What reserving a payout did.
class DVPayoutReservation {
  const DVPayoutReservation({this.record, this.existed = false});

  /// Null when nothing was available.
  final DVPayoutRecord? record;
  final bool existed;
}

/// Where payout entries are kept.
///
/// Every write that checks a balance or an id is one step with the check.
abstract class DVPayoutLedger {
  Future<DVPayoutSaleRecord?> sale(String saleId);

  /// Records [sale] and its [credits] unless the sale is recorded. False
  /// when it is.
  Future<bool> recordSale(DVPayoutSaleRecord sale, List<DVPayoutEntry> credits);

  /// Records a reversal of [amount] of [saleId] under [reference], unless one
  /// is recorded under it (false). [entries] is given the sale and how much
  /// was reversed before, and returns the entries. Returns null when [amount]
  /// is more than is left, recording nothing.
  Future<bool?> recordReversal({
    required String saleId,
    required String reference,
    required int amount,
    required List<DVPayoutEntry> Function(DVPayoutSaleRecord sale, int before)
        entries,
  });

  Future<void> hold(String saleId, String reason);
  Future<void> release(String saleId);

  /// The sum of [accountId]'s entries in [currency]; with [available], leaving
  /// out entries of sales on hold.
  Future<int> balance(String accountId, String currency,
      {bool available = false});

  Future<DVPayoutRecord?> findPayout(String payoutId);

  /// Reserves everything available to [accountId] in [currency] as payout
  /// [payoutId], debiting it, as one step with reading the balance. Returns
  /// the existing record when [payoutId] is already reserved.
  Future<DVPayoutReservation> reservePayout({
    required String accountId,
    required String currency,
    required String payoutId,
    required DateTime at,
  });

  Future<void> removePayout(String payoutId);
  Future<void> completePayout(String payoutId, String transferReference);
}

/// The payout ledger in memory, for tests and development.
///
/// Its checks and writes do not await, so on one isolate nothing interleaves
/// between reading a balance and debiting it.
class DVMemoryPayoutLedger implements DVPayoutLedger {
  final List<DVPayoutEntry> _entries = <DVPayoutEntry>[];
  final Set<String> _references = <String>{};
  final Map<String, DVPayoutSaleRecord> _sales = <String, DVPayoutSaleRecord>{};
  final Map<String, String> _holds = <String, String>{};
  final Map<String, DVPayoutRecord> _payouts = <String, DVPayoutRecord>{};

  /// Every entry, oldest first.
  List<DVPayoutEntry> get entries => List<DVPayoutEntry>.unmodifiable(_entries);

  @override
  Future<DVPayoutSaleRecord?> sale(String saleId) async => _sales[saleId];

  @override
  Future<bool> recordSale(
      DVPayoutSaleRecord sale, List<DVPayoutEntry> credits) async {
    if (_sales.containsKey(sale.saleId)) return false;
    _sales[sale.saleId] = sale;
    _entries.addAll(credits);
    return true;
  }

  @override
  Future<bool?> recordReversal({
    required String saleId,
    required String reference,
    required int amount,
    required List<DVPayoutEntry> Function(DVPayoutSaleRecord sale, int before)
        entries,
  }) async {
    final String key = '$saleId $reference';
    if (_references.contains(key)) return false;
    final DVPayoutSaleRecord sale = _sales[saleId]!;
    if (amount > sale.collected.amount - sale.reversed) return null;
    _entries.addAll(entries(sale, sale.reversed));
    _references.add(key);
    _sales[saleId] = DVPayoutSaleRecord(
      saleId: saleId,
      collected: sale.collected,
      shares: sale.shares,
      reversed: sale.reversed + amount,
    );
    return true;
  }

  @override
  Future<void> hold(String saleId, String reason) async {
    _holds[saleId] = reason;
  }

  @override
  Future<void> release(String saleId) async {
    _holds.remove(saleId);
  }

  int _sum(String accountId, String currency, bool available) {
    int sum = 0;
    for (final DVPayoutEntry e in _entries) {
      if (e.accountId != accountId || e.currency != currency) continue;
      if (available && e.saleId != null && _holds.containsKey(e.saleId)) {
        continue;
      }
      sum += e.amount;
    }
    return sum;
  }

  @override
  Future<int> balance(String accountId, String currency,
          {bool available = false}) async =>
      _sum(accountId, currency.toUpperCase(), available);

  @override
  Future<DVPayoutRecord?> findPayout(String payoutId) async =>
      _payouts[payoutId];

  @override
  Future<DVPayoutReservation> reservePayout({
    required String accountId,
    required String currency,
    required String payoutId,
    required DateTime at,
  }) async {
    final DVPayoutRecord? existing = _payouts[payoutId];
    if (existing != null) {
      return DVPayoutReservation(record: existing, existed: true);
    }
    final String code = currency.toUpperCase();
    final int available = _sum(accountId, code, true);
    if (available <= 0) return const DVPayoutReservation();
    final DVPayoutRecord record = DVPayoutRecord(
      id: payoutId,
      accountId: accountId,
      amount: DVMoney(amount: available, currency: code),
      at: at,
    );
    _payouts[payoutId] = record;
    _entries.add(DVPayoutEntry(
      id: payoutId,
      accountId: accountId,
      currency: code,
      amount: -available,
      kind: DVPayoutEntryKind.payout,
      reference: payoutId,
      at: at,
    ));
    return DVPayoutReservation(record: record);
  }

  @override
  Future<void> removePayout(String payoutId) async {
    _payouts.remove(payoutId);
    _entries.removeWhere((DVPayoutEntry e) =>
        e.kind == DVPayoutEntryKind.payout && e.id == payoutId);
  }

  @override
  Future<void> completePayout(String payoutId, String transferReference) async {
    final DVPayoutRecord? record = _payouts[payoutId];
    if (record == null) return;
    _payouts[payoutId] = DVPayoutRecord(
      id: record.id,
      accountId: record.accountId,
      amount: record.amount,
      at: record.at,
      transferReference: transferReference,
    );
  }
}

enum DVPayoutStatus {
  /// Transferred by this call.
  paid,

  /// Transferred by an earlier call with the same key.
  alreadyPaid,

  /// Not attempted: the account is not fully verified. `DV-COMMERCE-006`.
  held,

  /// Nothing available.
  nothingDue,
}

/// What a payout did.
class DVPayoutResult {
  const DVPayoutResult(this.status, {this.amount, this.transferReference});
  final DVPayoutStatus status;
  final DVMoney? amount;
  final String? transferReference;

  @override
  String toString() => 'DVPayoutResult(${status.name}, $amount)';
}

/// Splits, reversals and payouts.
class DVPayouts {
  DVPayouts({
    required this.ledger,
    required this.provider,
    DateTime Function()? clock,
    DVLogger? logger,
  })  : _clock = clock ?? DateTime.now,
        _logger = logger;

  /// The account id the platform's fee is kept under.
  static const String platform = 'platform';

  final DVPayoutLedger ledger;
  final DVConnectedAccountProvider provider;
  final DateTime Function() _clock;
  final DVLogger? _logger;
  final Map<String, Future<DVPayoutResult>> _paying =
      <String, Future<DVPayoutResult>>{};

  DVLogger get _log => _logger ?? DVObservability.logger;
  DateTime get _now => _clock().toUtc();

  /// Credits [collected] from [saleId] as [split] divides it.
  ///
  /// False when the sale is already recorded with the same amounts -- the
  /// webhook that reported it arrived again. Throws when it is recorded with
  /// different ones, which is not a replay and not something to pick between.
  Future<bool> recordSale({
    required String saleId,
    required DVMoney collected,
    required DVPayoutSplit split,
  }) async {
    final Map<String, DVMoney> shares = split.allocate(collected);
    final DVPayoutSaleRecord record = DVPayoutSaleRecord(
      saleId: saleId,
      collected: collected,
      shares: <String, int>{
        for (final MapEntry<String, DVMoney> s in shares.entries)
          s.key: s.value.amount,
      },
    );
    final DateTime at = _now;
    final bool recorded = await ledger.recordSale(record, <DVPayoutEntry>[
      for (final MapEntry<String, int> s in record.shares.entries)
        if (s.value != 0)
          DVPayoutEntry(
            id: 'sale:$saleId:${s.key}',
            accountId: s.key,
            currency: collected.currency,
            amount: s.value,
            kind: DVPayoutEntryKind.sale,
            reference: saleId,
            saleId: saleId,
            at: at,
          ),
    ]);
    if (recorded) return true;
    final DVPayoutSaleRecord existing = (await ledger.sale(saleId))!;
    final bool same = existing.collected == collected &&
        existing.shares.length == record.shares.length &&
        record.shares.entries.every(
            (MapEntry<String, int> s) => existing.shares[s.key] == s.value);
    if (!same) {
      throw StateError(
        'sale $saleId is recorded as ${existing.collected} divided '
        '${existing.shares}, and was reported again as $collected divided '
        '${record.shares}',
      );
    }
    return false;
  }

  /// Reverses [amount] of [saleId]'s shares for refund [refundId].
  Future<bool> recordRefund({
    required String saleId,
    required String refundId,
    required DVMoney amount,
  }) =>
      _reverse(saleId, refundId, amount, DVPayoutEntryKind.refund);

  /// Reverses [amount] of [saleId]'s shares for lost dispute [disputeId].
  Future<bool> recordDisputeLoss({
    required String saleId,
    required String disputeId,
    required DVMoney amount,
  }) =>
      _reverse(saleId, disputeId, amount, DVPayoutEntryKind.disputeLoss);

  Future<bool> _reverse(
    String saleId,
    String reference,
    DVMoney amount,
    DVPayoutEntryKind kind,
  ) async {
    final DVPayoutSaleRecord? sale = await ledger.sale(saleId);
    if (sale == null) {
      throw ArgumentError.value(saleId, 'saleId', 'is not a recorded sale');
    }
    if (amount.currency != sale.collected.currency) {
      throw ArgumentError.value(
          amount, 'amount', 'is not in ${sale.collected.currency}');
    }
    final DateTime at = _now;
    final bool? recorded = await ledger.recordReversal(
      saleId: saleId,
      reference: reference,
      amount: amount.amount,
      entries: (DVPayoutSaleRecord current, int before) {
        final List<String> ids = current.shares.keys.toList();
        final List<int> weights = <int>[
          for (final String id in ids) current.shares[id]!,
        ];
        // Cumulative: what has been reversed from each share once the new
        // total is reversed, minus what had been before. A sale reversed in
        // full reverses exactly each share.
        final List<int> was = dvAllocateByWeight(before, weights);
        final List<int> now =
            dvAllocateByWeight(before + amount.amount, weights);
        return <DVPayoutEntry>[
          for (int i = 0; i < ids.length; i++)
            if (now[i] != was[i])
              DVPayoutEntry(
                id: '${kind.name}:$reference:${ids[i]}',
                accountId: ids[i],
                currency: amount.currency,
                amount: was[i] - now[i],
                kind: kind,
                reference: reference,
                saleId: saleId,
                at: at,
              ),
        ];
      },
    );
    if (recorded == null) {
      final DVPayoutSaleRecord current = (await ledger.sale(saleId))!;
      throw DVRefundRefused(
        saleId: saleId,
        remaining: DVMoney(
            amount: current.collected.amount - current.reversed,
            currency: amount.currency),
        reason: 'the reversal is more than is left of what the sale collected',
      );
    }
    return recorded;
  }

  /// Keeps [saleId]'s entries out of every payout until [release].
  Future<void> hold(String saleId, {required String reason}) =>
      ledger.hold(saleId, reason);

  Future<void> release(String saleId) => ledger.release(saleId);

  /// [accountId]'s balance in [currency] in minor units, holds included.
  /// Negative when refunds reversed more than has been credited since the
  /// last payout.
  Future<int> balance(String accountId, String currency) =>
      ledger.balance(accountId, currency.toUpperCase());

  /// Pays [accountId] everything available in [currency].
  ///
  /// [key] names the payout -- a schedule's date, a run id -- and is required
  /// for the same reason a usage record's idempotency key is: payouts are run
  /// from jobs, which redeliver. The same key again is
  /// [DVPayoutStatus.alreadyPaid], and the transfer is made under it so the
  /// provider dedupes too.
  Future<DVPayoutResult> payout({
    required String accountId,
    required String currency,
    required String key,
  }) {
    final String code = currency.toUpperCase();
    final String payoutId = 'payout:$accountId:$code:$key';
    // The callback must not return the removed future: whenComplete waits on
    // a future its callback returns, and this one is the future completing.
    return _paying[payoutId] ??= _payout(accountId, code, payoutId)
        .whenComplete(() {
      unawaited(_paying.remove(payoutId));
    });
  }

  Future<DVPayoutResult> _payout(
      String accountId, String currency, String payoutId) async {
    final DVPayoutRecord? existing = await ledger.findPayout(payoutId);
    if (existing != null && existing.transferReference != null) {
      return DVPayoutResult(DVPayoutStatus.alreadyPaid,
          amount: existing.amount,
          transferReference: existing.transferReference);
    }
    final int available =
        await ledger.balance(accountId, currency, available: true);
    if (existing == null && available <= 0) {
      return const DVPayoutResult(DVPayoutStatus.nothingDue);
    }

    final DVConnectedAccount account = await provider.account(accountId);
    if (!account.canReceivePayouts) {
      final DVMoney due =
          existing?.amount ?? DVMoney(amount: available, currency: currency);
      _log.log(
        'DV-COMMERCE-006: a payout of $due to $accountId is held: the '
        'connected account is ${account.status.name} with payouts '
        '${account.payoutsEnabled ? 'enabled' : 'disabled'}, so no transfer '
        'was attempted',
        level: DVLogLevel.warn,
        code: 'DV-COMMERCE-006',
        context: <String, Object?>{
          'account': accountId,
          'status': account.status.name,
          'amount': due.amount,
          'currency': currency,
        },
      );
      return DVPayoutResult(DVPayoutStatus.held, amount: due);
    }

    return DVTransactionRunner().call<DVPayoutResult>(
      (DVContext context) async {
        final DVPayoutReservation reservation = await ledger.reservePayout(
          accountId: accountId,
          currency: currency,
          payoutId: payoutId,
          at: _now,
        );
        final DVPayoutRecord? record = reservation.record;
        if (record == null) {
          return const DVPayoutResult(DVPayoutStatus.nothingDue);
        }
        if (!reservation.existed) {
          context.compensate(() => ledger.removePayout(payoutId));
        } else if (record.transferReference != null) {
          return DVPayoutResult(DVPayoutStatus.alreadyPaid,
              amount: record.amount,
              transferReference: record.transferReference);
        }
        // A reservation that exists without a transfer is one a crash
        // interrupted. The transfer is retried under the same key, which the
        // provider answers with the first transfer if there was one.
        final DVTransfer transfer = await provider.transfer(
          accountId: accountId,
          amount: record.amount,
          idempotencyKey: payoutId,
        );
        if (transfer.amount != record.amount) {
          throw StateError(
            'the provider transferred ${transfer.amount} for payout '
            '$payoutId of ${record.amount}',
          );
        }
        await ledger.completePayout(payoutId, transfer.reference);
        return DVPayoutResult(DVPayoutStatus.paid,
            amount: record.amount, transferReference: transfer.reference);
      },
      isolated: true,
    );
  }
}
