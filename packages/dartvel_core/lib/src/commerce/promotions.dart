/// Promotions: coupons, campaigns and credits, decided on the server when the
/// charge is made.
///
/// Two rules, because their absence is how discount fraud works. Eligibility
/// is decided at charge time on the server: [DVPromotions.redeem] resolves the
/// order again from the codes alone, so a discount computed by a client is
/// never an input. And stacking is explicit: every promotion declares a
/// [DVPromotionStacking], at most one applies from each group, and an
/// exclusive one combines with nothing -- a 20% coupon does not quietly meet
/// a 30% campaign.
///
/// A limit is a count, and counting is where concurrency bites. Checking the
/// count and then recording a redemption is two steps, and a hundred requests
/// that all pass the check before any records gives away a hundred
/// redemptions of a coupon limited to one. [DVPromotionLedger.redeem] is the
/// check and the record together.
///
/// There is no rule engine here. Eligibility is a [DVPromotionPolicy] --
/// ordinary application code -- and anything past a policy, a window, a
/// minimum and a limit is a marketing product.
library dartvel.commerce.promotions;

import 'dart:async';

import '../../dartvel.dart' show dvBillingCustomerKey;
import '../billing/money.dart';
import '../database/adapter.dart';
import '../observability/observability.dart';
import '../transaction/transaction.dart';
import 'exact.dart';
import 'tax.dart';

/// One line of an order.
class DVOrderLine {
  DVOrderLine({
    required this.reference,
    required this.productId,
    required this.unitPrice,
    required this.category,
    this.quantity = 1,
  }) {
    if (reference.isEmpty) {
      throw ArgumentError.value(reference, 'reference', 'must not be empty');
    }
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'must be at least one');
    }
  }

  /// The application's name for the line, unique in the order.
  final String reference;
  final String productId;
  final DVMoney unitPrice;
  final int quantity;

  /// How the line is taxed. Declared on the line because the order is what
  /// is taxed, and the same product can be sold as two categories.
  final DVTaxCategory category;

  /// The line's price before discounts: [unitPrice] times [quantity].
  DVMoney get amount => DVMoney(
      amount: unitPrice.amount * quantity, currency: unitPrice.currency);
}

/// What a promotion takes off.
sealed class DVDiscount {
  const DVDiscount();

  /// A whole percentage of the eligible lines.
  const factory DVDiscount.percent(int percent) = DVPercentDiscount.percent;

  /// Hundredths of a percent, for 12.5% and the like.
  const factory DVDiscount.basisPoints(int basisPoints) = DVPercentDiscount;

  /// A fixed amount, capped at what the eligible lines cost.
  const factory DVDiscount.fixed(DVMoney amount) = DVFixedDiscount;

  /// Throws when the discount cannot be applied as declared.
  void validate();
}

/// See [DVDiscount.percent].
final class DVPercentDiscount extends DVDiscount {
  const DVPercentDiscount(this.basisPoints);
  const DVPercentDiscount.percent(int percent) : basisPoints = percent * 100;

  /// 2000 is 20%.
  final int basisPoints;

  @override
  void validate() {
    if (basisPoints < 1 || basisPoints > 10000) {
      throw ArgumentError.value(basisPoints, 'basisPoints',
          'a percentage discount is more than 0% and at most 100%');
    }
  }
}

/// See [DVDiscount.fixed].
final class DVFixedDiscount extends DVDiscount {
  const DVFixedDiscount(this.amount);
  final DVMoney amount;

  @override
  void validate() {
    if (amount.amount < 1) {
      throw ArgumentError.value(amount, 'amount', 'a discount takes something off');
    }
  }
}

/// How a promotion combines with others. There is no default.
class DVPromotionStacking {
  /// Combines with promotions in other groups; at most one from [group]
  /// applies.
  const DVPromotionStacking.group(String this.group);

  /// Combines with nothing.
  const DVPromotionStacking.exclusive() : group = null;

  final String? group;

  bool get exclusive => group == null;
}

/// A coupon, campaign or credit.
///
/// Normally a generated model; this is the shape the resolver reads.
class DVPromotion {
  const DVPromotion({
    required this.id,
    required this.discount,
    required this.stacking,
    this.code,
    this.maxRedemptions,
    this.maxRedemptionsPerCustomer,
    this.startsAt,
    this.endsAt,
    this.products,
    this.minimumSubtotal,
    this.priority = 0,
  });

  final String id;

  /// What a customer types, matched without regard to case. Null for a
  /// promotion that applies to every order it is eligible for.
  final String? code;
  final DVDiscount discount;
  final DVPromotionStacking stacking;

  /// Redemptions across everybody, or null for no limit.
  final int? maxRedemptions;

  /// Redemptions by one customer, or null for no limit.
  final int? maxRedemptionsPerCustomer;

  /// Live from this moment, inclusive.
  final DateTime? startsAt;

  /// Live until this moment, exclusive.
  final DateTime? endsAt;

  /// The product ids it discounts, or null for every line.
  final Set<String>? products;

  /// The order, before any discount, has to cost at least this.
  final DVMoney? minimumSubtotal;

  /// Order of application: lower first, then by [id]. Each promotion is
  /// applied to what the earlier ones left.
  final int priority;

  @override
  String toString() => 'DVPromotion($id)';
}

/// Whether a customer may redeem a promotion: the `@DVPolicy` the
/// specification writes as `redeem(User user, Coupon coupon)`.
abstract class DVPromotionPolicy {
  FutureOr<bool> redeem(Object customer, DVPromotion promotion);
}

/// A policy that lets any customer redeem anything live. Explicit, so that
/// allowing everybody is a decision somebody made.
class DVAnyCustomerPromotionPolicy implements DVPromotionPolicy {
  const DVAnyCustomerPromotionPolicy();

  @override
  bool redeem(Object customer, DVPromotion promotion) => true;
}

/// Why a promotion did not apply.
enum DVPromotionRefusal {
  /// No promotion has the code.
  unknown,

  /// The code was given twice.
  duplicate,

  /// Before its start or at or after its end.
  notLive,

  /// Nothing in the order is discounted by it, including a fixed amount in
  /// another currency.
  notApplicable,

  /// The order is below its minimum.
  belowMinimum,

  /// Redeemed as many times as it may be.
  limitReached,

  /// Redeemed by this customer as many times as they may.
  customerLimitReached,

  /// Its policy refused this customer: `DV-COMMERCE-003`.
  ineligible,

  /// Another promotion in its group, or an exclusive one, gave more.
  notStacked,
}

/// What recording a redemption did.
enum DVRedeemOutcome {
  redeemed,

  /// This order already holds the redemption. Not a second one.
  alreadyRedeemed,
  limitReached,
  customerLimitReached,
}

/// Where redemptions are counted.
abstract class DVPromotionLedger {
  /// Redemptions of [promotionId] by everybody.
  Future<int> redeemed(String promotionId);

  /// Redemptions of [promotionId] by [customerKey].
  Future<int> redeemedBy(String promotionId, String customerKey);

  /// Whether [orderId] holds a redemption of [promotionId].
  Future<bool> redeemedFor(String promotionId, String orderId);

  /// Records that [orderId] redeems [promotion] for [customerKey], unless a
  /// limit is reached -- the check and the record as one step.
  Future<DVRedeemOutcome> redeem(
    DVPromotion promotion, {
    required String customerKey,
    required String orderId,
    required DateTime at,
  });

  /// Gives back [orderId]'s redemption of [promotionId], if it holds one.
  Future<void> release(String promotionId, String orderId);
}

/// Redemptions in memory, for tests and development.
///
/// [redeem] does not await, so on one isolate the check and the record cannot
/// be interleaved.
class DVMemoryPromotionLedger implements DVPromotionLedger {
  final Map<(String, String), String> _orders = <(String, String), String>{};
  final Map<String, int> _counts = <String, int>{};
  final Map<(String, String), int> _customerCounts = <(String, String), int>{};

  @override
  Future<int> redeemed(String promotionId) async => _counts[promotionId] ?? 0;

  @override
  Future<int> redeemedBy(String promotionId, String customerKey) async =>
      _customerCounts[(promotionId, customerKey)] ?? 0;

  @override
  Future<bool> redeemedFor(String promotionId, String orderId) async =>
      _orders.containsKey((promotionId, orderId));

  @override
  Future<DVRedeemOutcome> redeem(
    DVPromotion promotion, {
    required String customerKey,
    required String orderId,
    required DateTime at,
  }) async {
    final String id = promotion.id;
    if (_orders.containsKey((id, orderId))) return DVRedeemOutcome.alreadyRedeemed;
    final int? max = promotion.maxRedemptions;
    if (max != null && (_counts[id] ?? 0) >= max) {
      return DVRedeemOutcome.limitReached;
    }
    final int? perCustomer = promotion.maxRedemptionsPerCustomer;
    if (perCustomer != null &&
        (_customerCounts[(id, customerKey)] ?? 0) >= perCustomer) {
      return DVRedeemOutcome.customerLimitReached;
    }
    _orders[(id, orderId)] = customerKey;
    _counts[id] = (_counts[id] ?? 0) + 1;
    _customerCounts[(id, customerKey)] =
        (_customerCounts[(id, customerKey)] ?? 0) + 1;
    return DVRedeemOutcome.redeemed;
  }

  @override
  Future<void> release(String promotionId, String orderId) async {
    final String? customerKey = _orders.remove((promotionId, orderId));
    if (customerKey == null) return;
    _counts[promotionId] = (_counts[promotionId] ?? 1) - 1;
    _customerCounts[(promotionId, customerKey)] =
        (_customerCounts[(promotionId, customerKey)] ?? 1) - 1;
  }
}

/// Redemptions in the application's database, counted across instances.
///
/// A counter row per promotion, and per promotion and customer, moved by
/// compare-and-set: `UPDATE ... SET redeemed = n + 1 WHERE redeemed = n`
/// changes one row or none, and none means another instance counted first,
/// so the count is read again. That is atomic on every database without a
/// lock or an isolation level, and it is why the limit check cannot be
/// passed by two requests at once.
///
/// A crash between recording the order and moving the counters leaves a
/// count higher than the redemptions, which refuses a customer rather than
/// giving a discount away. The development in-memory adapter does not
/// enforce primary keys, so there only this process's own serialisation of
/// first inserts stands in for them.
class DVDatabasePromotionLedger implements DVPromotionLedger {
  DVDatabasePromotionLedger(
    this.db, {
    this.redemptionsTable = 'dv_promotion_redemptions',
    this.countersTable = 'dv_promotion_counters',
  }) {
    for (final String table in <String>[redemptionsTable, countersTable]) {
      if (!RegExp(r'^[A-Za-z_]\w*$').hasMatch(table)) {
        throw ArgumentError.value(table, 'table', 'is not a table name');
      }
    }
  }

  final DVDatabaseAdapter db;
  final String redemptionsTable;
  final String countersTable;

  static const String _everybody = '*';
  static const int _attempts = 1000;

  Future<void>? _ready;
  final Map<(String, String), Future<void>> _creating =
      <(String, String), Future<void>>{};

  Future<void> _ensureTables() => _ready ??= () async {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $redemptionsTable (promotion_id TEXT NOT '
          'NULL, order_id TEXT NOT NULL, customer_key TEXT NOT NULL, '
          'redeemed_at_us INTEGER NOT NULL, PRIMARY KEY (promotion_id, order_id))',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $countersTable (promotion_id TEXT NOT '
          'NULL, scope TEXT NOT NULL, redeemed INTEGER NOT NULL, '
          'PRIMARY KEY (promotion_id, scope))',
        );
      }();

  static String _customerScope(String customerKey) => 'customer:$customerKey';

  Future<int?> _count(String promotionId, String scope) async {
    await _ensureTables();
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT redeemed FROM $countersTable WHERE promotion_id = ? AND scope = ?',
      <Object?>[promotionId, scope],
    );
    return rows.isEmpty ? null : (rows.first['redeemed']! as num).toInt();
  }

  /// Creates the counter row once. Concurrent first redemptions in this
  /// process share one insert; another instance's is refused by the key.
  Future<void> _ensureCounter(String promotionId, String scope) {
    final (String, String) key = (promotionId, scope);
    return _creating[key] ??= () async {
      try {
        if (await _count(promotionId, scope) != null) return;
        try {
          await db.execute(
            'INSERT INTO $countersTable (promotion_id, scope, redeemed) '
            'VALUES (?, ?, ?)',
            <Object?>[promotionId, scope, 0],
          );
        } on Object catch (error) {
          if (!_isUniqueViolation(error)) rethrow;
        }
      } finally {
        // This future is the one being removed; nothing waits on removing it.
        unawaited(_creating.remove(key));
      }
    }();
  }

  /// Moves a counter by [delta], refusing to pass [limit]. False when the
  /// limit is reached.
  Future<bool> _move(
    String promotionId,
    String scope,
    int delta, {
    int? limit,
  }) async {
    await _ensureCounter(promotionId, scope);
    for (int attempt = 0; attempt < _attempts; attempt++) {
      final int current = (await _count(promotionId, scope))!;
      if (delta > 0 && limit != null && current >= limit) return false;
      if (delta < 0 && current <= 0) return true;
      final int changed = await db.execute(
        'UPDATE $countersTable SET redeemed = ? WHERE promotion_id = ? AND '
        'scope = ? AND redeemed = ?',
        <Object?>[current + delta, promotionId, scope, current],
      );
      if (changed > 0) return true;
    }
    throw StateError(
        'the $promotionId counter changed under every one of $_attempts '
        'attempts to move it');
  }

  @override
  Future<int> redeemed(String promotionId) async =>
      await _count(promotionId, _everybody) ?? 0;

  @override
  Future<int> redeemedBy(String promotionId, String customerKey) async =>
      await _count(promotionId, _customerScope(customerKey)) ?? 0;

  @override
  Future<bool> redeemedFor(String promotionId, String orderId) async {
    await _ensureTables();
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT COUNT(*) AS n FROM $redemptionsTable WHERE promotion_id = ? AND '
      'order_id = ?',
      <Object?>[promotionId, orderId],
    );
    return rows.isNotEmpty && ((rows.first['n'] as num?) ?? 0) > 0;
  }

  @override
  Future<DVRedeemOutcome> redeem(
    DVPromotion promotion, {
    required String customerKey,
    required String orderId,
    required DateTime at,
  }) async {
    final String id = promotion.id;
    if (await redeemedFor(id, orderId)) return DVRedeemOutcome.alreadyRedeemed;
    try {
      await db.execute(
        'INSERT INTO $redemptionsTable (promotion_id, order_id, customer_key, '
        'redeemed_at_us) VALUES (?, ?, ?, ?)',
        <Object?>[id, orderId, customerKey, at.toUtc().microsecondsSinceEpoch],
      );
    } on Object catch (error) {
      if (_isUniqueViolation(error)) return DVRedeemOutcome.alreadyRedeemed;
      rethrow;
    }
    if (!await _move(id, _everybody, 1, limit: promotion.maxRedemptions)) {
      await _forget(id, orderId);
      return DVRedeemOutcome.limitReached;
    }
    if (!await _move(id, _customerScope(customerKey), 1,
        limit: promotion.maxRedemptionsPerCustomer)) {
      await _move(id, _everybody, -1);
      await _forget(id, orderId);
      return DVRedeemOutcome.customerLimitReached;
    }
    return DVRedeemOutcome.redeemed;
  }

  @override
  Future<void> release(String promotionId, String orderId) async {
    await _ensureTables();
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT customer_key FROM $redemptionsTable WHERE promotion_id = ? AND '
      'order_id = ?',
      <Object?>[promotionId, orderId],
    );
    if (rows.isEmpty) return;
    if (await _forget(promotionId, orderId) == 0) return;
    await _move(promotionId, _everybody, -1);
    await _move(
        promotionId, _customerScope('${rows.first['customer_key']}'), -1);
  }

  Future<int> _forget(String promotionId, String orderId) => db.execute(
        'DELETE FROM $redemptionsTable WHERE promotion_id = ? AND order_id = ?',
        <Object?>[promotionId, orderId],
      );

  static bool _isUniqueViolation(Object error) {
    final String text = '$error'.toUpperCase();
    return text.contains('UNIQUE') || text.contains('DUPLICATE');
  }
}

/// A promotion that applied, and what it took off each line.
class DVAppliedPromotion {
  DVAppliedPromotion(this.promotion, this.amount, Map<String, int> byLine)
      : byLine = Map<String, int>.unmodifiable(byLine);

  final DVPromotion promotion;
  final DVMoney amount;

  /// Minor units taken off each line, by line reference. Sums to [amount].
  final Map<String, int> byLine;
}

/// A promotion that did not apply, and why.
class DVRefusedPromotion {
  const DVRefusedPromotion(this.reason, {this.promotionId, this.code});
  final DVPromotionRefusal reason;

  /// Null for a code no promotion has.
  final String? promotionId;

  /// The code as given, when one was.
  final String? code;

  @override
  String toString() =>
      'DVRefusedPromotion(${promotionId ?? code}, ${reason.name})';
}

/// What promotions do to an order.
class DVPromotionResolution {
  DVPromotionResolution._({
    required this.subtotal,
    required List<DVAppliedPromotion> applied,
    required List<DVRefusedPromotion> refused,
    required Map<String, int> byLine,
  })  : applied = List<DVAppliedPromotion>.unmodifiable(applied),
        refused = List<DVRefusedPromotion>.unmodifiable(refused),
        _byLine = Map<String, int>.unmodifiable(byLine);

  /// The order before discounts.
  final DVMoney subtotal;

  /// In the order they were applied.
  final List<DVAppliedPromotion> applied;
  final List<DVRefusedPromotion> refused;
  final Map<String, int> _byLine;

  DVMoney get discount => DVMoney(
        amount: applied.fold<int>(
            0, (int sum, DVAppliedPromotion a) => sum + a.amount.amount),
        currency: subtotal.currency,
      );

  /// The order after discounts, before tax.
  DVMoney get total => DVMoney(
      amount: subtotal.amount - discount.amount, currency: subtotal.currency);

  /// Everything promotions took off the line [reference].
  DVMoney discountFor(String reference) {
    final int? amount = _byLine[reference];
    if (amount == null) {
      throw ArgumentError.value(reference, 'reference', 'is not a line of the order');
    }
    return DVMoney(amount: amount, currency: subtotal.currency);
  }
}

/// A promotion that resolved as applying could not be redeemed when the
/// charge was made. The charge does not go ahead at a price the customer was
/// not shown.
class DVPromotionUnavailable implements Exception {
  const DVPromotionUnavailable(this.promotionId, this.reason);
  final String promotionId;
  final DVPromotionRefusal reason;

  @override
  String toString() =>
      'DVPromotionUnavailable: $promotionId (${reason.name}); price the order '
      'again';
}

/// The declared promotions and the resolver that applies them.
class DVPromotions {
  DVPromotions({
    required List<DVPromotion> promotions,
    required this.policy,
    required this.ledger,
    DateTime Function()? clock,
    DVLogger? logger,
  })  : promotions = List<DVPromotion>.unmodifiable(promotions),
        _clock = clock ?? DateTime.now,
        _logger = logger {
    final Set<String> ids = <String>{};
    for (final DVPromotion p in promotions) {
      if (!ids.add(p.id)) {
        throw ArgumentError('promotion "${p.id}" is declared twice');
      }
      p.discount.validate();
      final String? group = p.stacking.group;
      if (group != null && group.isEmpty) {
        throw ArgumentError.value(group, 'group', 'of ${p.id} is empty');
      }
      for (final (String name, int? limit) in <(String, int?)>[
        ('maxRedemptions', p.maxRedemptions),
        ('maxRedemptionsPerCustomer', p.maxRedemptionsPerCustomer),
      ]) {
        if (limit != null && limit < 1) {
          throw ArgumentError.value(limit, name,
              'of ${p.id} allows no redemptions; leave the promotion out');
        }
      }
      final DateTime? start = p.startsAt;
      final DateTime? end = p.endsAt;
      if (start != null && end != null && !end.isAfter(start)) {
        throw ArgumentError('${p.id} ends before it starts');
      }
      final String? code = p.code;
      if (code != null) {
        final String normal = _normal(code);
        if (normal.isEmpty) {
          throw ArgumentError.value(code, 'code', 'of ${p.id} is empty');
        }
        final DVPromotion? other = _byCode[normal];
        if (other != null) {
          throw ArgumentError(
              '${other.id} and ${p.id} share the code "$code"; a customer '
              'typing it would get whichever was declared last');
        }
        _byCode[normal] = p;
      }
    }
  }

  final List<DVPromotion> promotions;
  final DVPromotionPolicy policy;
  final DVPromotionLedger ledger;
  final DateTime Function() _clock;
  final DVLogger? _logger;
  final Map<String, DVPromotion> _byCode = <String, DVPromotion>{};

  DVLogger get _log => _logger ?? DVObservability.logger;

  static String _normal(String code) => code.trim().toUpperCase();

  /// What [codes], and every automatic promotion, do to [lines] for
  /// [customer], without redeeming anything.
  ///
  /// For showing a price. The amount charged comes from [redeem], which
  /// resolves again.
  Future<DVPromotionResolution> resolve({
    required Object customer,
    required List<DVOrderLine> lines,
    required List<String> codes,
  }) =>
      _resolve(customer, lines, codes, orderId: null);

  /// Resolves [lines] again for [customer] and redeems what applies, inside
  /// [context]'s transaction, so a charge that fails gives the redemptions
  /// back.
  ///
  /// Throws [DVPromotionUnavailable] when a limit was reached between the
  /// check and the redemption; the transaction then rolls back whatever this
  /// order had already redeemed. Redeeming the same [orderId] again, as a
  /// retried charge does, holds the same redemptions rather than taking
  /// more.
  Future<DVPromotionResolution> redeem(
    DVContext context, {
    required Object customer,
    required List<DVOrderLine> lines,
    required List<String> codes,
    required String orderId,
  }) async {
    final String customerKey = dvBillingCustomerKey(customer);
    final DVPromotionResolution resolution =
        await _resolve(customer, lines, codes, orderId: orderId);
    final DateTime now = _clock().toUtc();
    for (final DVAppliedPromotion applied in resolution.applied) {
      final DVPromotion promotion = applied.promotion;
      final DVRedeemOutcome outcome = await ledger.redeem(
        promotion,
        customerKey: customerKey,
        orderId: orderId,
        at: now,
      );
      switch (outcome) {
        case DVRedeemOutcome.redeemed:
          context.compensate(() => ledger.release(promotion.id, orderId));
        case DVRedeemOutcome.alreadyRedeemed:
          break;
        case DVRedeemOutcome.limitReached:
          throw DVPromotionUnavailable(
              promotion.id, DVPromotionRefusal.limitReached);
        case DVRedeemOutcome.customerLimitReached:
          throw DVPromotionUnavailable(
              promotion.id, DVPromotionRefusal.customerLimitReached);
      }
    }
    return resolution;
  }

  Future<DVPromotionResolution> _resolve(
    Object customer,
    List<DVOrderLine> lines,
    List<String> codes, {
    required String? orderId,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'an order has at least one line');
    }
    final String currency = lines.first.unitPrice.currency;
    final Set<String> references = <String>{};
    for (final DVOrderLine line in lines) {
      if (line.unitPrice.currency != currency) {
        throw ArgumentError.value(line.reference, 'lines', 'mixes currencies');
      }
      if (!references.add(line.reference)) {
        throw ArgumentError.value(line.reference, 'lines', 'reference repeats');
      }
    }
    final String customerKey = dvBillingCustomerKey(customer);
    final DateTime now = _clock().toUtc();
    final DVMoney subtotal = DVMoney(
      amount: lines.fold<int>(0, (int s, DVOrderLine l) => s + l.amount.amount),
      currency: currency,
    );

    final List<DVRefusedPromotion> refused = <DVRefusedPromotion>[];
    final List<DVPromotion> candidates = <DVPromotion>[
      for (final DVPromotion p in promotions)
        if (p.code == null) p,
    ];
    final Set<String> seen = <String>{for (final DVPromotion p in candidates) p.id};
    for (final String code in codes) {
      final DVPromotion? p = _byCode[_normal(code)];
      if (p == null) {
        refused.add(DVRefusedPromotion(DVPromotionRefusal.unknown, code: code));
      } else if (!seen.add(p.id)) {
        refused.add(DVRefusedPromotion(DVPromotionRefusal.duplicate,
            promotionId: p.id, code: code));
      } else {
        candidates.add(p);
      }
    }

    final List<DVPromotion> eligible = <DVPromotion>[];
    for (final DVPromotion p in candidates) {
      final DVPromotionRefusal? reason =
          await _refusal(p, lines, subtotal, now, customerKey, orderId);
      if (reason != null) {
        refused.add(DVRefusedPromotion(reason, promotionId: p.id, code: p.code));
        continue;
      }
      if (!await policy.redeem(customer, p)) {
        _log.log(
          'DV-COMMERCE-003: promotion ${p.id} was refused by its eligibility '
          'policy',
          level: DVLogLevel.info,
          code: 'DV-COMMERCE-003',
          context: <String, Object?>{'promotion': p.id, 'customer': customerKey},
        );
        refused.add(DVRefusedPromotion(DVPromotionRefusal.ineligible,
            promotionId: p.id, code: p.code));
        continue;
      }
      eligible.add(p);
    }

    final List<DVPromotion> chosen = _choose(eligible, lines);
    for (final DVPromotion p in eligible) {
      if (!chosen.contains(p)) {
        refused.add(DVRefusedPromotion(DVPromotionRefusal.notStacked,
            promotionId: p.id, code: p.code));
      }
    }

    final Map<String, int> remaining = <String, int>{
      for (final DVOrderLine l in lines) l.reference: l.amount.amount,
    };
    final List<DVAppliedPromotion> applied = <DVAppliedPromotion>[];
    for (final DVAppliedPromotion a in _apply(_ordered(chosen), lines)) {
      if (a.amount.amount == 0) {
        // Nothing left for it to take: not a redemption worth counting.
        refused.add(DVRefusedPromotion(DVPromotionRefusal.notApplicable,
            promotionId: a.promotion.id, code: a.promotion.code));
        continue;
      }
      applied.add(a);
      a.byLine.forEach((String ref, int n) => remaining[ref] = remaining[ref]! - n);
    }
    return DVPromotionResolution._(
      subtotal: subtotal,
      applied: applied,
      refused: refused,
      byLine: <String, int>{
        for (final DVOrderLine l in lines)
          l.reference: l.amount.amount - remaining[l.reference]!,
      },
    );
  }

  Future<DVPromotionRefusal?> _refusal(
    DVPromotion p,
    List<DVOrderLine> lines,
    DVMoney subtotal,
    DateTime now,
    String customerKey,
    String? orderId,
  ) async {
    final DateTime? start = p.startsAt;
    final DateTime? end = p.endsAt;
    if ((start != null && now.isBefore(start)) ||
        (end != null && !now.isBefore(end))) {
      return DVPromotionRefusal.notLive;
    }
    final DVDiscount discount = p.discount;
    if (discount is DVFixedDiscount &&
        discount.amount.currency != subtotal.currency) {
      return DVPromotionRefusal.notApplicable;
    }
    if (!lines.any((DVOrderLine l) => _covers(p, l))) {
      return DVPromotionRefusal.notApplicable;
    }
    final DVMoney? minimum = p.minimumSubtotal;
    if (minimum != null) {
      if (minimum.currency != subtotal.currency) {
        return DVPromotionRefusal.notApplicable;
      }
      if (subtotal.amount < minimum.amount) return DVPromotionRefusal.belowMinimum;
    }
    // A retried charge for an order that already holds the redemption is not
    // over the limit it counted towards.
    if (orderId != null && await ledger.redeemedFor(p.id, orderId)) return null;
    final int? max = p.maxRedemptions;
    if (max != null && await ledger.redeemed(p.id) >= max) {
      return DVPromotionRefusal.limitReached;
    }
    final int? perCustomer = p.maxRedemptionsPerCustomer;
    if (perCustomer != null &&
        await ledger.redeemedBy(p.id, customerKey) >= perCustomer) {
      return DVPromotionRefusal.customerLimitReached;
    }
    return null;
  }

  static bool _covers(DVPromotion p, DVOrderLine line) =>
      p.products == null || p.products!.contains(line.productId);

  static List<DVPromotion> _ordered(Iterable<DVPromotion> promotions) =>
      promotions.toList()
        ..sort((DVPromotion a, DVPromotion b) {
          final int byPriority = a.priority.compareTo(b.priority);
          return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
        });

  /// The best of: one promotion from each group together, or any exclusive
  /// promotion alone. Most discount wins; on a tie, fewer promotions, then
  /// the ids in order.
  List<DVPromotion> _choose(List<DVPromotion> eligible, List<DVOrderLine> lines) {
    int value(Iterable<DVPromotion> option) => _apply(_ordered(option), lines)
        .fold<int>(0, (int s, DVAppliedPromotion a) => s + a.amount.amount);

    final Map<String, DVPromotion> bestInGroup = <String, DVPromotion>{};
    final Map<String, int> standalone = <String, int>{
      for (final DVPromotion p in eligible) p.id: value(<DVPromotion>[p]),
    };
    for (final DVPromotion p in _ordered(eligible)) {
      final String? group = p.stacking.group;
      if (group == null) continue;
      final DVPromotion? held = bestInGroup[group];
      if (held == null || standalone[p.id]! > standalone[held.id]!) {
        bestInGroup[group] = p;
      }
    }
    final List<List<DVPromotion>> options = <List<DVPromotion>>[
      if (bestInGroup.isNotEmpty) bestInGroup.values.toList(),
      for (final DVPromotion p in eligible)
        if (p.stacking.exclusive) <DVPromotion>[p],
    ];
    List<DVPromotion> best = const <DVPromotion>[];
    int bestValue = -1;
    String bestIds = '';
    for (final List<DVPromotion> option in options) {
      final int v = value(option);
      final String ids = _ordered(option).map((DVPromotion p) => p.id).join(',');
      final bool better = v > bestValue ||
          (v == bestValue &&
              (option.length < best.length ||
                  (option.length == best.length && ids.compareTo(bestIds) < 0)));
      if (better) {
        best = option;
        bestValue = v;
        bestIds = ids;
      }
    }
    return best;
  }

  /// Applies [ordered] in turn, each to what the earlier ones left.
  static List<DVAppliedPromotion> _apply(
      List<DVPromotion> ordered, List<DVOrderLine> lines) {
    final String currency = lines.first.unitPrice.currency;
    final Map<String, int> remaining = <String, int>{
      for (final DVOrderLine l in lines) l.reference: l.amount.amount,
    };
    final List<DVAppliedPromotion> result = <DVAppliedPromotion>[];
    for (final DVPromotion p in ordered) {
      final List<DVOrderLine> covered =
          <DVOrderLine>[for (final DVOrderLine l in lines) if (_covers(p, l)) l];
      final List<int> weights = <int>[
        for (final DVOrderLine l in covered) remaining[l.reference]!,
      ];
      final int base = weights.fold<int>(0, (int s, int w) => s + w);
      final int amount = switch (p.discount) {
        // Rounded once, on the total, half up; then allocated. Rounding each
        // line gives away or keeps a unit the total never agreed to.
        final DVPercentDiscount pct => DVExact(
                BigInt.from(base) * BigInt.from(pct.basisPoints),
                BigInt.from(10000))
            .round(halfEven: false),
        final DVFixedDiscount fixed =>
          fixed.amount.amount < base ? fixed.amount.amount : base,
      };
      final List<int> shares =
          base == 0 ? <int>[for (final int _ in weights) 0] : dvAllocateByWeight(amount, weights);
      final Map<String, int> byLine = <String, int>{};
      for (int i = 0; i < covered.length; i++) {
        byLine[covered[i].reference] = shares[i];
        remaining[covered[i].reference] = remaining[covered[i].reference]! - shares[i];
      }
      result.add(DVAppliedPromotion(
          p, DVMoney(amount: amount, currency: currency), byLine));
    }
    return result;
  }
}
