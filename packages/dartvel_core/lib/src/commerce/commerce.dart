/// A sale through a payment gateway, and the refund that reverses it.
///
/// A sale here is what Billing's subscriptions and Purchases' store products
/// are not: a one-off order, priced on the server from its lines, its
/// promotion codes and a tax quote, and captured through a
/// [DVPaymentGateway]. The order of the steps is the design. Promotions are
/// redeemed and the sale recorded and granted first, each registering its
/// compensation, and the capture comes last -- so a capture that fails undoes
/// everything before it, and nothing after it can.
///
/// A refund is a reversal the application chooses, so it is a transaction
/// too: the amount is reserved against what was captured, the entitlements
/// go, the application's restock runs, and the gateway credit is last. Either
/// all of that happens or none of it does, and when a compensation itself
/// fails the reversal is incomplete, which is reported as `DV-COMMERCE-004`
/// and thrown as [DVRefundIncomplete] rather than left as a half-reversed
/// order nobody notices.
///
/// Store refunds arrive differently -- the store decides, and the purchases
/// ledger hears about it -- so [DVCommerce.storeRevocations] adapts a
/// reversal to `DVPurchases(onChange: ...)`, under the same rule.
library dartvel.commerce.sales;

import 'dart:async';

import '../../dartvel.dart'
    show DVLocalBillingProvider, Entitlement, dvBillingCustomerKey;
import '../billing/money.dart';
import '../observability/observability.dart';
import '../purchases/purchases.dart';
import '../transaction/transaction.dart';
import 'exact.dart';
import 'payouts.dart' show DVRefundRefused;
import 'promotions.dart';
import 'tax.dart';

/// Where a sale's entitlements are granted.
abstract class DVEntitlementGrants {
  Future<void> grant(String customerKey, Set<Entitlement> entitlements);
  Future<void> revoke(String customerKey, Set<Entitlement> entitlements);
}

/// Grants kept by [DVLocalBillingProvider].
class DVLocalBillingGrants implements DVEntitlementGrants {
  DVLocalBillingGrants(this.billing);
  final DVLocalBillingProvider billing;

  @override
  Future<void> grant(String customerKey, Set<Entitlement> entitlements) async {
    for (final Entitlement e in entitlements) {
      billing.grant(customerKey, e);
    }
  }

  @override
  Future<void> revoke(String customerKey, Set<Entitlement> entitlements) async {
    for (final Entitlement e in entitlements) {
      billing.revoke(customerKey, e);
    }
  }
}

/// A capture, as the gateway reports it.
class DVGatewayCharge {
  const DVGatewayCharge({required this.reference, required this.amount});
  final String reference;

  /// What the gateway says it captured, which is checked against the sale.
  final DVMoney amount;
}

/// A credit back to the customer, as the gateway reports it.
class DVGatewayRefund {
  const DVGatewayRefund({required this.reference, required this.amount});
  final String reference;
  final DVMoney amount;
}

/// A payment gateway: Stripe PaymentIntents, Adyen, a card terminal.
///
/// Both calls carry an idempotency key, and an implementation passes it to
/// the gateway, which answers a repeated key with its first answer. That is
/// what makes a retried charge a single capture and a retried refund a single
/// credit.
abstract class DVPaymentGateway {
  Future<DVGatewayCharge> charge({
    required String orderId,
    required String customerKey,
    required DVMoney amount,
    required String idempotencyKey,
  });

  Future<DVGatewayRefund> refund({
    required String chargeReference,
    required DVMoney amount,
    required String idempotencyKey,
  });
}

enum DVSaleStatus {
  /// Recorded, not yet captured. Only ever seen part-way through a charge.
  pending,
  captured,
}

/// One line of a sale, with what was taken off it and what was taxed on it.
class DVSaleLine {
  const DVSaleLine({
    required this.reference,
    required this.productId,
    required this.category,
    required this.amount,
    required this.discount,
    required this.taxable,
    required this.tax,
  });

  final String reference;
  final String productId;
  final DVTaxCategory category;

  /// Before discounts.
  final DVMoney amount;
  final DVMoney discount;
  final DVMoney taxable;
  final DVMoney tax;
}

/// A sale, as the application keeps it.
class DVSale {
  DVSale({
    required this.id,
    required this.customerKey,
    required List<DVSaleLine> lines,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.behavior,
    required this.taxSource,
    required this.taxJurisdiction,
    required List<String> promotions,
    required Set<String> entitlements,
    required this.createdAt,
    this.status = DVSaleStatus.pending,
    this.taxReference,
    this.chargeReference,
    DVMoney? refunded,
    DVMoney? taxRefunded,
    this.revokedAt,
  })  : lines = List<DVSaleLine>.unmodifiable(lines),
        promotions = List<String>.unmodifiable(promotions),
        entitlements = Set<String>.unmodifiable(entitlements),
        refunded = refunded ?? DVMoney(amount: 0, currency: total.currency),
        taxRefunded =
            taxRefunded ?? DVMoney(amount: 0, currency: total.currency);

  /// The order id.
  final String id;
  final String customerKey;
  final List<DVSaleLine> lines;
  final DVMoney subtotal;
  final DVMoney discount;
  final DVMoney tax;

  /// What was captured.
  final DVMoney total;
  final DVTaxBehavior behavior;
  final DVTaxSource taxSource;
  final String taxJurisdiction;

  /// The tax provider's calculation, which its invoice refers to.
  final String? taxReference;
  final List<String> promotions;

  /// Entitlement ids the sale granted.
  final Set<String> entitlements;
  final DateTime createdAt;
  final DVSaleStatus status;
  final String? chargeReference;
  final DVMoney refunded;

  /// The part of [refunded] that was tax.
  final DVMoney taxRefunded;

  /// When the sale's entitlements were taken back, by a full refund or a lost
  /// dispute.
  final DateTime? revokedAt;

  String get currency => total.currency;

  /// Priced from the offline tax table, and to be re-rated:
  /// `DV-COMMERCE-001`.
  bool get needsRerating => taxSource == DVTaxSource.offlineTable;

  /// Whether the sale still grants what it sold.
  bool get grants => status == DVSaleStatus.captured && revokedAt == null;

  DVSale copyWith({
    DVSaleStatus? status,
    String? chargeReference,
    DVMoney? refunded,
    DVMoney? taxRefunded,
    DateTime? revokedAt,
    bool clearRevokedAt = false,
  }) =>
      DVSale(
        id: id,
        customerKey: customerKey,
        lines: lines,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        total: total,
        behavior: behavior,
        taxSource: taxSource,
        taxJurisdiction: taxJurisdiction,
        taxReference: taxReference,
        promotions: promotions,
        entitlements: entitlements,
        createdAt: createdAt,
        status: status ?? this.status,
        chargeReference: chargeReference ?? this.chargeReference,
        refunded: refunded ?? this.refunded,
        taxRefunded: taxRefunded ?? this.taxRefunded,
        revokedAt: clearRevokedAt ? null : revokedAt ?? this.revokedAt,
      );

  @override
  String toString() => 'DVSale($id, $total, ${status.name})';
}

enum DVRefundStatus {
  /// Counted against the capture; the gateway credit is not yet recorded.
  reserved,
  completed,
}

/// A refund of part or all of a sale.
class DVRefund {
  const DVRefund({
    required this.id,
    required this.saleId,
    required this.amount,
    required this.tax,
    required this.createdAt,
    this.reason,
    this.status = DVRefundStatus.reserved,
    this.gatewayReference,
  });

  final String id;
  final String saleId;
  final DVMoney amount;

  /// The tax inside [amount], reversed cumulatively so a sale refunded in
  /// parts reverses exactly the tax it collected.
  final DVMoney tax;
  final String? reason;
  final DateTime createdAt;
  final DVRefundStatus status;
  final String? gatewayReference;

  DVRefund completed(String reference) => DVRefund(
        id: id,
        saleId: saleId,
        amount: amount,
        tax: tax,
        reason: reason,
        createdAt: createdAt,
        status: DVRefundStatus.completed,
        gatewayReference: reference,
      );
}

/// A refund failed and its compensation failed too: the reversal is
/// incomplete. `DV-COMMERCE-004`.
class DVRefundIncomplete implements Exception {
  const DVRefundIncomplete({
    required this.saleId,
    required this.refundId,
    required this.cause,
    required this.compensationErrors,
  });

  final String saleId;
  final String refundId;
  final Object cause;
  final List<Object> compensationErrors;

  @override
  String toString() =>
      'DVRefundIncomplete: refund $refundId of $saleId failed ($cause) and '
      '${compensationErrors.length} compensation(s) failed too: '
      '${compensationErrors.join('; ')}';
}

/// What reserving a refund did.
class DVRefundReservation {
  const DVRefundReservation({this.refund, this.existed = false, this.remaining});

  /// The reservation, or null when refused.
  final DVRefund? refund;

  /// A refund with this id was already there.
  final bool existed;

  /// What was left, when refused.
  final int? remaining;
}

/// Where sales and refunds are kept.
abstract class DVCommerceLedger {
  Future<DVSale?> find(String saleId);
  Future<DVSale?> findByCharge(String chargeReference);

  /// Records [sale] unless one with its id exists. False when it does.
  Future<bool> insert(DVSale sale);
  Future<void> update(DVSale sale);
  Future<void> remove(String saleId);
  Future<void> setRevokedAt(String saleId, DateTime? at);
  Future<List<DVSale>> forCustomer(String customerKey);

  /// Captured sales priced from the offline tax table.
  Future<List<DVSale>> needingRerating();

  Future<DVRefund?> findRefund(String refundId);

  /// Counts [amount] against what is left of [saleId]'s capture, as one step
  /// with checking that it fits. [taxFor] is given the amount refunded before
  /// and after, and returns the tax this refund reverses.
  Future<DVRefundReservation> reserveRefund({
    required String saleId,
    required String refundId,
    required int amount,
    required int Function(int refundedBefore, int refundedAfter) taxFor,
    required DateTime at,
    String? reason,
  });

  /// Undoes a reservation.
  Future<void> releaseRefund(String refundId);
  Future<void> completeRefund(String refundId, String gatewayReference);
}

/// Sales in memory, for tests and development.
///
/// [reserveRefund] does not await, so on one isolate two refunds cannot both
/// pass the check before either is counted.
class DVMemoryCommerceLedger implements DVCommerceLedger {
  final Map<String, DVSale> _sales = <String, DVSale>{};
  final Map<String, DVRefund> _refunds = <String, DVRefund>{};

  @override
  Future<DVSale?> find(String saleId) async => _sales[saleId];

  @override
  Future<DVSale?> findByCharge(String chargeReference) async {
    for (final DVSale sale in _sales.values) {
      if (sale.chargeReference == chargeReference) return sale;
    }
    return null;
  }

  @override
  Future<bool> insert(DVSale sale) async {
    if (_sales.containsKey(sale.id)) return false;
    _sales[sale.id] = sale;
    return true;
  }

  @override
  Future<void> update(DVSale sale) async {
    _sales[sale.id] = sale;
  }

  @override
  Future<void> remove(String saleId) async {
    _sales.remove(saleId);
  }

  @override
  Future<void> setRevokedAt(String saleId, DateTime? at) async {
    final DVSale? sale = _sales[saleId];
    if (sale == null) return;
    _sales[saleId] = sale.copyWith(revokedAt: at, clearRevokedAt: at == null);
  }

  @override
  Future<List<DVSale>> forCustomer(String customerKey) async => <DVSale>[
        for (final DVSale s in _sales.values)
          if (s.customerKey == customerKey) s,
      ];

  @override
  Future<List<DVSale>> needingRerating() async => <DVSale>[
        for (final DVSale s in _sales.values)
          if (s.status == DVSaleStatus.captured && s.needsRerating) s,
      ];

  @override
  Future<DVRefund?> findRefund(String refundId) async => _refunds[refundId];

  @override
  Future<DVRefundReservation> reserveRefund({
    required String saleId,
    required String refundId,
    required int amount,
    required int Function(int refundedBefore, int refundedAfter) taxFor,
    required DateTime at,
    String? reason,
  }) async {
    final DVRefund? existing = _refunds[refundId];
    if (existing != null) {
      return DVRefundReservation(refund: existing, existed: true);
    }
    final DVSale sale = _sales[saleId]!;
    final int before = sale.refunded.amount;
    final int remaining = sale.total.amount - before;
    if (amount > remaining) return DVRefundReservation(remaining: remaining);
    final int tax = taxFor(before, before + amount);
    final DVRefund refund = DVRefund(
      id: refundId,
      saleId: saleId,
      amount: DVMoney(amount: amount, currency: sale.currency),
      tax: DVMoney(amount: tax, currency: sale.currency),
      reason: reason,
      createdAt: at,
    );
    _refunds[refundId] = refund;
    _sales[saleId] = sale.copyWith(
      refunded: DVMoney(amount: before + amount, currency: sale.currency),
      taxRefunded: DVMoney(
          amount: sale.taxRefunded.amount + tax, currency: sale.currency),
    );
    return DVRefundReservation(refund: refund);
  }

  @override
  Future<void> releaseRefund(String refundId) async {
    final DVRefund? refund = _refunds.remove(refundId);
    if (refund == null) return;
    final DVSale? sale = _sales[refund.saleId];
    if (sale == null) return;
    _sales[sale.id] = sale.copyWith(
      refunded: DVMoney(
          amount: sale.refunded.amount - refund.amount.amount,
          currency: sale.currency),
      taxRefunded: DVMoney(
          amount: sale.taxRefunded.amount - refund.tax.amount,
          currency: sale.currency),
    );
  }

  @override
  Future<void> completeRefund(String refundId, String gatewayReference) async {
    final DVRefund? refund = _refunds[refundId];
    if (refund != null) _refunds[refundId] = refund.completed(gatewayReference);
  }
}

/// Sales, refunds and store reversals.
class DVCommerce {
  DVCommerce({
    required this.tax,
    required this.gateway,
    required this.ledger,
    this.promotions,
    this.grants,
    DateTime Function()? clock,
    DVLogger? logger,
  })  : _clock = clock ?? DateTime.now,
        _logger = logger;

  final DVTax tax;
  final DVPaymentGateway gateway;
  final DVCommerceLedger ledger;
  final DVPromotions? promotions;
  final DVEntitlementGrants? grants;
  final DateTime Function() _clock;
  final DVLogger? _logger;
  final Map<String, Future<DVSale>> _charging = <String, Future<DVSale>>{};

  DVLogger get _log => _logger ?? DVObservability.logger;
  DateTime get _now => _clock().toUtc();

  /// Prices [lines] for [customer] on the server and captures the total.
  ///
  /// Nothing about the amount comes from the caller except the lines and the
  /// codes. Charging the same [orderId] again -- a double click, a retried
  /// request -- returns the sale rather than capturing a second time.
  ///
  /// Throws [DVSaleRefused] when tax cannot be resolved,
  /// [DVPromotionUnavailable] when a promotion's limit was reached since it
  /// was shown, and whatever the gateway throws when it declines; in each case
  /// nothing stays redeemed, recorded or granted.
  Future<DVSale> charge({
    required String orderId,
    required Object customer,
    required List<DVOrderLine> lines,
    required DVTaxAddress to,
    List<String> codes = const <String>[],
    Set<Entitlement> entitlements = const <Entitlement>{},
    DVTaxBehavior behavior = DVTaxBehavior.exclusive,
  }) {
    if (orderId.isEmpty) {
      throw ArgumentError.value(orderId, 'orderId', 'must not be empty');
    }
    if (codes.isNotEmpty && promotions == null) {
      throw ArgumentError.value(codes, 'codes',
          'were given and no promotions are configured to resolve them');
    }
    final String customerKey = dvBillingCustomerKey(customer);
    // The callback must not return the removed future: whenComplete waits on
    // a future its callback returns, and this one is the future completing.
    return _charging[orderId] ??= _charge(
      orderId: orderId,
      customer: customer,
      customerKey: customerKey,
      lines: lines,
      to: to,
      codes: codes,
      entitlements: entitlements,
      behavior: behavior,
    ).whenComplete(() {
      unawaited(_charging.remove(orderId));
    });
  }

  Future<DVSale> _charge({
    required String orderId,
    required Object customer,
    required String customerKey,
    required List<DVOrderLine> lines,
    required DVTaxAddress to,
    required List<String> codes,
    required Set<Entitlement> entitlements,
    required DVTaxBehavior behavior,
  }) async {
    final DVSale? existing = await ledger.find(orderId);
    if (existing != null) return _sameCustomer(existing, customerKey);

    return DVTransactionRunner().call<DVSale>((DVContext context) async {
      final DVPromotions? resolver = promotions;
      final DVPromotionResolution? resolution = resolver == null
          ? null
          : await resolver.redeem(context,
              customer: customer, lines: lines, codes: codes, orderId: orderId);

      final DVTaxQuote quote = await tax.quoteLines(DVTaxRequest(
        to: to,
        behavior: behavior,
        lines: <DVTaxLine>[
          for (final DVOrderLine l in lines)
            DVTaxLine(
              reference: l.reference,
              amount: l.amount,
              category: l.category,
              discount: resolution?.discountFor(l.reference),
            ),
        ],
      ));

      final String currency = quote.currency;
      DVMoney money(int amount) => DVMoney(amount: amount, currency: currency);
      final int subtotal =
          lines.fold<int>(0, (int s, DVOrderLine l) => s + l.amount.amount);
      final int discount = resolution?.discount.amount ?? 0;
      final int total = behavior == DVTaxBehavior.exclusive
          ? subtotal - discount + quote.tax.amount
          : subtotal - discount;

      final DVSale sale = DVSale(
        id: orderId,
        customerKey: customerKey,
        lines: <DVSaleLine>[
          for (final DVOrderLine l in lines)
            DVSaleLine(
              reference: l.reference,
              productId: l.productId,
              category: l.category,
              amount: l.amount,
              discount: resolution?.discountFor(l.reference) ?? money(0),
              taxable: quote.line(l.reference).taxable,
              tax: quote.line(l.reference).tax,
            ),
        ],
        subtotal: money(subtotal),
        discount: money(discount),
        tax: quote.tax,
        total: money(total),
        behavior: behavior,
        taxSource: quote.source,
        taxJurisdiction: quote.jurisdiction,
        taxReference: quote.providerReference,
        promotions: <String>[
          for (final DVAppliedPromotion a
              in resolution?.applied ?? const <DVAppliedPromotion>[])
            a.promotion.id,
        ],
        entitlements: <String>{for (final Entitlement e in entitlements) e.id},
        createdAt: _now,
      );

      if (!await ledger.insert(sale)) {
        // Another instance is charging this order. Its redemptions and its
        // capture are the order's; this attempt adds nothing.
        return _sameCustomer((await ledger.find(orderId))!, customerKey);
      }
      context.compensate(() => ledger.remove(orderId));

      final DVEntitlementGrants? granter = grants;
      if (granter != null && entitlements.isNotEmpty) {
        await granter.grant(customerKey, entitlements);
        context.compensate(() async {
          final Set<Entitlement> unheld =
              await _notHeldElsewhere(customerKey, orderId, sale.entitlements);
          if (unheld.isNotEmpty) await granter.revoke(customerKey, unheld);
        });
      }

      DVSale captured = sale.copyWith(status: DVSaleStatus.captured);
      if (total > 0) {
        final DVGatewayCharge charge = await gateway.charge(
          orderId: orderId,
          customerKey: customerKey,
          amount: money(total),
          idempotencyKey: 'charge:$orderId',
        );
        context.compensate(() => gateway.refund(
              chargeReference: charge.reference,
              amount: charge.amount,
              idempotencyKey: 'charge-reversal:$orderId',
            ));
        if (charge.amount != money(total)) {
          throw StateError(
            'the gateway captured ${charge.amount} for order $orderId, which '
            'costs ${money(total)}; the capture is being reversed rather than '
            'recorded as a sale for an amount nobody agreed to',
          );
        }
        captured = captured.copyWith(chargeReference: charge.reference);
      }
      await ledger.update(captured);
      return captured;
    });
  }

  static DVSale _sameCustomer(DVSale sale, String customerKey) {
    if (sale.customerKey != customerKey) {
      throw StateError(
          'order ${sale.id} was charged to another customer; an order id is '
          'not reused');
    }
    return sale;
  }

  /// Refunds [amount] of [saleId], or everything left of it.
  ///
  /// [refundId] identifies the refund: asking again with the same id returns
  /// it rather than crediting twice. [restock] runs inside the reversal and
  /// registers its own compensation on the context it is given.
  ///
  /// Throws [DVRefundRefused] when the amount is more than is left of the
  /// capture, and [DVRefundIncomplete] (reporting `DV-COMMERCE-004`) when the
  /// refund failed and undoing it failed too. Any other failure has been
  /// fully undone and is rethrown.
  Future<DVRefund> refund({
    required String saleId,
    required String refundId,
    DVMoney? amount,
    String? reason,
    FutureOr<void> Function(DVContext context, DVRefund refund)? restock,
  }) async {
    final DVSale? sale = await ledger.find(saleId);
    if (sale == null || sale.status != DVSaleStatus.captured) {
      throw ArgumentError.value(saleId, 'saleId', 'is not a captured sale');
    }
    final DVRefund? existing = await ledger.findRefund(refundId);
    if (existing != null) {
      if (existing.saleId != saleId) {
        throw ArgumentError.value(
            refundId, 'refundId', 'was used for sale ${existing.saleId}');
      }
      if (existing.status == DVRefundStatus.completed) return existing;
      throw StateError('refund $refundId is already in progress');
    }
    if (amount != null && amount.currency != sale.currency) {
      throw ArgumentError.value(amount, 'amount', 'is not in ${sale.currency}');
    }
    final int remaining = sale.total.amount - sale.refunded.amount;
    final int value = amount?.amount ?? remaining;
    final String? chargeReference = sale.chargeReference;
    if (value <= 0 || chargeReference == null) {
      throw DVRefundRefused(
        saleId: saleId,
        remaining: DVMoney(amount: remaining, currency: sale.currency),
        reason: 'there is nothing to refund',
      );
    }

    try {
      return await DVTransactionRunner().call<DVRefund>(
        (DVContext context) async {
          final DVRefundReservation reservation = await ledger.reserveRefund(
            saleId: saleId,
            refundId: refundId,
            amount: value,
            reason: reason,
            at: _now,
            taxFor: (int before, int after) =>
                _taxReversed(sale, after) - _taxReversed(sale, before),
          );
          final DVRefund? refund = reservation.refund;
          if (refund == null) {
            throw DVRefundRefused(
              saleId: saleId,
              remaining: DVMoney(
                  amount: reservation.remaining!, currency: sale.currency),
              reason: 'the refund is more than is left of the capture',
            );
          }
          if (reservation.existed) {
            throw StateError('refund $refundId is already in progress');
          }
          context.compensate(() => ledger.releaseRefund(refundId));

          final DVSale after = (await ledger.find(saleId))!;
          if (after.refunded == after.total) await revokeSale(context, saleId);

          if (restock != null) await restock(context, refund);

          // Last: the one step nothing after it could undo.
          final DVGatewayRefund credit = await gateway.refund(
            chargeReference: chargeReference,
            amount: refund.amount,
            idempotencyKey: 'refund:$refundId',
          );
          await ledger.completeRefund(refundId, credit.reference);
          return refund.completed(credit.reference);
        },
      );
    } on DVCompensationException catch (failure) {
      _incomplete('refund $refundId of sale $saleId', failure,
          <String, Object?>{'sale': saleId, 'refund': refundId});
      throw DVRefundIncomplete(
        saleId: saleId,
        refundId: refundId,
        cause: failure.cause,
        compensationErrors: failure.compensationErrors,
      );
    }
  }

  /// Takes back what [saleId] granted, inside [context], unless the customer
  /// holds it from another sale. Returns what was revoked.
  ///
  /// Used by a full refund and by a lost dispute.
  Future<Set<Entitlement>> revokeSale(DVContext context, String saleId) async {
    final DVSale? sale = await ledger.find(saleId);
    if (sale == null) {
      throw ArgumentError.value(saleId, 'saleId', 'is not a sale');
    }
    if (sale.revokedAt != null) return const <Entitlement>{};
    await ledger.setRevokedAt(saleId, _now);
    context.compensate(() => ledger.setRevokedAt(saleId, null));
    final DVEntitlementGrants? granter = grants;
    if (granter == null) return const <Entitlement>{};
    final Set<Entitlement> revoked =
        await _notHeldElsewhere(sale.customerKey, saleId, sale.entitlements);
    if (revoked.isEmpty) return revoked;
    await granter.revoke(sale.customerKey, revoked);
    context.compensate(() => granter.grant(sale.customerKey, revoked));
    return revoked;
  }

  /// Gives back what [revokeSale] took, inside [context]. Returns what was
  /// granted.
  Future<Set<Entitlement>> restoreSale(DVContext context, String saleId) async {
    final DVSale? sale = await ledger.find(saleId);
    if (sale == null) {
      throw ArgumentError.value(saleId, 'saleId', 'is not a sale');
    }
    final DateTime? revokedAt = sale.revokedAt;
    if (revokedAt == null) return const <Entitlement>{};
    await ledger.setRevokedAt(saleId, null);
    context.compensate(() => ledger.setRevokedAt(saleId, revokedAt));
    final DVEntitlementGrants? granter = grants;
    if (granter == null || sale.entitlements.isEmpty) {
      return const <Entitlement>{};
    }
    final Set<Entitlement> restored = <Entitlement>{
      for (final String id in sale.entitlements) Entitlement(id),
    };
    await granter.grant(sale.customerKey, restored);
    context.compensate(() async {
      final Set<Entitlement> unheld =
          await _notHeldElsewhere(sale.customerKey, saleId, sale.entitlements);
      if (unheld.isNotEmpty) await granter.revoke(sale.customerKey, unheld);
    });
    return restored;
  }

  /// A `DVPurchases(onChange: ...)` handler that runs [reverse] when a store
  /// takes a purchase back.
  ///
  /// Only for a revocation -- a refund, a chargeback -- and never for a
  /// subscription that lapsed, which revokes the same entitlements and moves
  /// no money. [reverse] runs as its own transaction. A failure is logged
  /// rather than thrown, because the store's notification has already been
  /// applied and must still be acknowledged; a reversal whose compensation
  /// failed is `DV-COMMERCE-004`.
  Future<void> Function(DVPurchaseChange change) storeRevocations(
    FutureOr<void> Function(DVContext context, DVPurchaseChange change) reverse,
  ) =>
      (DVPurchaseChange change) async {
        if (change.revokedAt == null || change.revoked.isEmpty) return;
        final Map<String, Object?> context = <String, Object?>{
          'store': change.store.name,
          'transaction': change.originalTransactionId,
        };
        try {
          await DVTransactionRunner().call<void>(
            (DVContext unit) => reverse(unit, change),
            isolated: true,
          );
        } on DVCompensationException catch (failure) {
          _incomplete(
              'the reversal of ${change.store.name} purchase '
              '${change.originalTransactionId}',
              failure,
              context);
        } on Object catch (error, stackTrace) {
          _log.log(
            'The reversal of ${change.store.name} purchase '
            '${change.originalTransactionId} failed and was rolled back: '
            '$error',
            level: DVLogLevel.error,
            error: error,
            stackTrace: stackTrace,
            context: context,
          );
        }
      };

  void _incomplete(
    String what,
    DVCompensationException failure,
    Map<String, Object?> context,
  ) {
    _log.log(
      'DV-COMMERCE-004: $what failed (${failure.cause}) and its compensation '
      'failed too; the reversal is incomplete: '
      '${failure.compensationErrors.join('; ')}',
      level: DVLogLevel.error,
      code: 'DV-COMMERCE-004',
      context: context,
    );
  }

  /// The tax reversed once [refunded] of [sale] has been refunded: the sale's
  /// tax in proportion, rounded half up. Taking differences of this is what
  /// makes partial refunds sum to the tax.
  static int _taxReversed(DVSale sale, int refunded) {
    if (sale.total.amount == 0) return 0;
    return DVExact(
      BigInt.from(sale.tax.amount) * BigInt.from(refunded),
      BigInt.from(sale.total.amount),
    ).round(halfEven: false);
  }

  Future<Set<Entitlement>> _notHeldElsewhere(
    String customerKey,
    String saleId,
    Set<String> entitlementIds,
  ) async {
    final Set<String> elsewhere = <String>{
      for (final DVSale other in await ledger.forCustomer(customerKey))
        if (other.id != saleId && other.grants) ...other.entitlements,
    };
    return <Entitlement>{
      for (final String id in entitlementIds)
        if (!elsewhere.contains(id)) Entitlement(id),
    };
  }
}
