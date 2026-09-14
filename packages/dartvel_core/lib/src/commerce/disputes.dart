/// Disputes: a chargeback is not a refund.
///
/// A refund is a reversal the application chooses. A dispute is started by
/// the customer's bank, arrives as a provider webhook, has evidence deadlines
/// the application does not control, and when it is lost costs the amount
/// plus a fee. So it is a record with a clock rather than a status field: a
/// deadline, an evidence checklist, and a timeline in the shape an incident
/// has, with `DV-COMMERCE-005` fired while there is still time to act.
///
/// What a dispute does to the rest of the application is decided here rather
/// than in each webhook route, because each of its failures is silent. The
/// webhook is believed only when its signature is the provider's. An event is
/// applied once however often it is delivered, and one older than an event
/// already applied is stale -- a late "created" does not put back the hold a
/// "lost" released. While a dispute is open, the sale's payout shares are
/// held; when it is lost, what the sale granted is taken back (unless the
/// customer holds it from another sale) and the shares are reversed; when it
/// is won, the hold is released. A delivery that fails part-way is rolled back
/// and its claim released, so the provider's retry is applied rather than
/// mistaken for a replay.
///
/// What is deliberately absent: responding. Evidence is assembled from records
/// the application holds and submitted by a person; a machine deciding what to
/// argue is a machine losing money on the application's behalf.
library dartvel.commerce.disputes;

import 'dart:async';

import '../billing/money.dart';
import '../billing/stripe.dart';
import '../billing/webhooks.dart';
import '../observability/observability.dart';
import '../transaction/transaction.dart';
import 'commerce.dart';
import 'payouts.dart';

/// Where a dispute stands, in Stripe's vocabulary, which the other providers
/// map onto.
enum DVDisputeStatus {
  /// An inquiry, before it is a chargeback, awaiting a response.
  warningNeedsResponse,
  warningUnderReview,
  warningClosed,
  needsResponse,
  underReview,
  won,
  lost,

  /// A status this code does not know. Neither open for a response nor
  /// closed, so it neither warns nor releases anything.
  unknown;

  /// Waiting for evidence, with the deadline running.
  bool get awaitingEvidence =>
      this == DVDisputeStatus.warningNeedsResponse ||
      this == DVDisputeStatus.needsResponse;

  /// Over, one way or the other.
  bool get closed =>
      this == DVDisputeStatus.won ||
      this == DVDisputeStatus.lost ||
      this == DVDisputeStatus.warningClosed;

  /// Closed without the money leaving.
  bool get kept =>
      this == DVDisputeStatus.won || this == DVDisputeStatus.warningClosed;
}

/// When a dispute takes back what the sale granted.
enum DVDisputeRevocation {
  /// As soon as it opens, restored if it is won. For goods whose value is
  /// used up while a dispute runs.
  onOpen,

  /// Only when it is lost.
  onLoss,
}

/// A dispute webhook, verified and read into a provider-neutral shape.
class DVDisputeEvent {
  const DVDisputeEvent({
    required this.eventId,
    required this.disputeId,
    required this.chargeReference,
    required this.amount,
    required this.reason,
    required this.status,
    required this.occurredAt,
    this.evidenceDueBy,
    this.provider = 'stripe',
  });

  /// The provider's event id, which is what makes a redelivery a replay.
  final String eventId;
  final String disputeId;

  /// The charge disputed, which finds the sale.
  final String chargeReference;
  final DVMoney amount;
  final String reason;
  final DVDisputeStatus status;

  /// When the provider produced the event. Orders events about one dispute.
  final DateTime occurredAt;
  final DateTime? evidenceDueBy;
  final String provider;
}

/// One item of evidence a response needs.
class DVEvidenceItem {
  const DVEvidenceItem(this.key, this.description, {this.provided = false});

  /// The provider's evidence field, such as `receipt`.
  final String key;
  final String description;
  final bool provided;
}

/// One line of a dispute's timeline, in the shape an incident's has.
class DVDisputeEntry {
  const DVDisputeEntry({
    required this.at,
    required this.message,
    this.status,
    this.source = 'provider',
  });

  final DateTime at;
  final String message;

  /// The status this entry moved the dispute to, if it moved it.
  final DVDisputeStatus? status;

  /// `provider`, `deadline` or `human`.
  final String source;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toUtc().toIso8601String(),
        'message': message,
        if (status != null) 'status': status!.name,
        'source': source,
      };
}

/// A dispute and its timeline.
class DVDispute {
  DVDispute({
    required this.id,
    required this.provider,
    required this.chargeReference,
    required this.amount,
    required this.reason,
    required this.status,
    required this.openedAt,
    required this.lastEventAt,
    required List<DVEvidenceItem> evidence,
    required List<DVDisputeEntry> timeline,
    this.saleId,
    this.evidenceDueBy,
    Set<int> warnedAtMinutes = const <int>{},
    this.deadlinePassed = false,
    this.payoutsHeld = false,
    this.entitlementsRevoked = false,
  })  : evidence = List<DVEvidenceItem>.unmodifiable(evidence),
        timeline = List<DVDisputeEntry>.unmodifiable(timeline),
        warnedAtMinutes = Set<int>.unmodifiable(warnedAtMinutes);

  final String id;
  final String provider;
  final String chargeReference;

  /// The sale the disputed charge paid for, or null when no sale made it.
  final String? saleId;
  final DVMoney amount;
  final String reason;
  final DVDisputeStatus status;
  final DateTime? evidenceDueBy;
  final DateTime openedAt;

  /// The provider time of the newest event applied. An older one is stale.
  final DateTime lastEventAt;
  final List<DVEvidenceItem> evidence;
  final List<DVDisputeEntry> timeline;

  /// The warning thresholds already announced, in minutes before the
  /// deadline.
  final Set<int> warnedAtMinutes;
  final bool deadlinePassed;

  /// Whether this dispute holds the sale's payout shares.
  final bool payoutsHeld;

  /// Whether this dispute took back what the sale granted.
  final bool entitlementsRevoked;

  DVDispute copyWith({
    DVDisputeStatus? status,
    DateTime? evidenceDueBy,
    DateTime? lastEventAt,
    List<DVEvidenceItem>? evidence,
    List<DVDisputeEntry>? timeline,
    Set<int>? warnedAtMinutes,
    bool? deadlinePassed,
    bool? payoutsHeld,
    bool? entitlementsRevoked,
  }) =>
      DVDispute(
        id: id,
        provider: provider,
        chargeReference: chargeReference,
        saleId: saleId,
        amount: amount,
        reason: reason,
        status: status ?? this.status,
        evidenceDueBy: evidenceDueBy ?? this.evidenceDueBy,
        openedAt: openedAt,
        lastEventAt: lastEventAt ?? this.lastEventAt,
        evidence: evidence ?? this.evidence,
        timeline: timeline ?? this.timeline,
        warnedAtMinutes: warnedAtMinutes ?? this.warnedAtMinutes,
        deadlinePassed: deadlinePassed ?? this.deadlinePassed,
        payoutsHeld: payoutsHeld ?? this.payoutsHeld,
        entitlementsRevoked: entitlementsRevoked ?? this.entitlementsRevoked,
      );

  @override
  String toString() => 'DVDispute($id, ${status.name})';
}

/// Where disputes are kept.
abstract class DVDisputeStore {
  Future<DVDispute?> find(String id);
  Future<void> put(DVDispute dispute);
  Future<void> remove(String id);

  /// Disputes not yet closed.
  Future<List<DVDispute>> open();

  /// Records that [eventId] is being applied. False when it already was.
  Future<bool> claimEvent(String eventId);

  /// Undoes a claim whose application failed, so the provider's retry
  /// applies.
  Future<void> releaseEvent(String eventId);
}

/// Disputes in memory, for tests and development.
class DVMemoryDisputeStore implements DVDisputeStore {
  final Map<String, DVDispute> _disputes = <String, DVDispute>{};
  final Set<String> _events = <String>{};

  @override
  Future<DVDispute?> find(String id) async => _disputes[id];

  @override
  Future<void> put(DVDispute dispute) async {
    _disputes[dispute.id] = dispute;
  }

  @override
  Future<void> remove(String id) async {
    _disputes.remove(id);
  }

  @override
  Future<List<DVDispute>> open() async => <DVDispute>[
        for (final DVDispute d in _disputes.values)
          if (!d.status.closed) d,
      ];

  @override
  Future<bool> claimEvent(String eventId) async => _events.add(eventId);

  @override
  Future<void> releaseEvent(String eventId) async {
    _events.remove(eventId);
  }
}

/// What applying a dispute event did.
class DVDisputeResult {
  const DVDisputeResult({
    this.handled = false,
    this.replayed = false,
    this.stale = false,
    this.dispute,
  });

  /// Whether the dispute record was written. False for an event that is not
  /// a dispute, a replay, or a stale event -- all of which are still
  /// acknowledged, because the provider retries what is not.
  final bool handled;
  final bool replayed;
  final bool stale;
  final DVDispute? dispute;
}

/// Stripe's dispute events, read.
class DVStripeDisputeEvents {
  const DVStripeDisputeEvents._();

  static const Set<String> types = <String>{
    'charge.dispute.created',
    'charge.dispute.updated',
    'charge.dispute.closed',
    'charge.dispute.funds_withdrawn',
    'charge.dispute.funds_reinstated',
  };

  /// The dispute event in a verified Stripe [event], or null when it is some
  /// other kind of event.
  static DVDisputeEvent? parse(Map<String, Object?> event) {
    final String type = '${event['type'] ?? ''}';
    if (!types.contains(type)) return null;
    final Object? data = event['data'];
    final Object? object = data is Map ? data['object'] : null;
    final Object? created = event['created'];
    if (object is! Map || created is! int) {
      throw DVBillingError('A $type event carried no dispute.');
    }
    final Object? charge = object['charge'];
    final String chargeId = charge is Map ? '${charge['id']}' : '${charge ?? ''}';
    final Object? amount = object['amount'];
    final Object? currency = object['currency'];
    final Object? id = object['id'];
    if (id is! String || chargeId.isEmpty || amount is! int || currency is! String) {
      throw DVBillingError('A $type event carried an unreadable dispute.');
    }
    final Object? details = object['evidence_details'];
    final Object? dueBy = details is Map ? details['due_by'] : null;
    return DVDisputeEvent(
      eventId: '${event['id']}',
      disputeId: id,
      chargeReference: chargeId,
      amount: DVMoney(amount: amount, currency: currency),
      reason: '${object['reason'] ?? 'general'}',
      status: _status('${object['status']}'),
      occurredAt: _seconds(created),
      evidenceDueBy: dueBy is int ? _seconds(dueBy) : null,
    );
  }

  static DateTime _seconds(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);

  static DVDisputeStatus _status(String status) => switch (status) {
        'warning_needs_response' => DVDisputeStatus.warningNeedsResponse,
        'warning_under_review' => DVDisputeStatus.warningUnderReview,
        'warning_closed' => DVDisputeStatus.warningClosed,
        'needs_response' => DVDisputeStatus.needsResponse,
        'under_review' => DVDisputeStatus.underReview,
        'won' => DVDisputeStatus.won,
        'lost' => DVDisputeStatus.lost,
        _ => DVDisputeStatus.unknown,
      };
}

/// Disputes, their consequences, and their deadlines.
class DVDisputes {
  DVDisputes({
    required this.store,
    required this.commerce,
    this.payouts,
    this.revokeEntitlements = DVDisputeRevocation.onLoss,
    List<Duration> warnBefore = const <Duration>[
      Duration(days: 3),
      Duration(days: 1),
    ],
    List<DVEvidenceItem> Function(String reason)? evidence,
    DateTime Function()? clock,
    DVLogger? logger,
  })  : warnBefore = List<Duration>.unmodifiable(warnBefore),
        _evidence = evidence ?? defaultEvidence,
        _clock = clock ?? DateTime.now,
        _logger = logger {
    if (warnBefore.any((Duration d) => d <= Duration.zero)) {
      throw ArgumentError.value(warnBefore, 'warnBefore', 'must be positive');
    }
  }

  final DVDisputeStore store;
  final DVCommerce commerce;
  final DVPayouts? payouts;
  final DVDisputeRevocation revokeEntitlements;

  /// How long before a deadline `DV-COMMERCE-005` fires, once each.
  final List<Duration> warnBefore;
  final List<DVEvidenceItem> Function(String reason) _evidence;
  final DateTime Function() _clock;
  final DVLogger? _logger;

  DVLogger get _log => _logger ?? DVObservability.logger;
  DateTime get _now => _clock().toUtc();

  /// The evidence a response to a dispute for [reason] needs, by Stripe's
  /// evidence field names.
  static List<DVEvidenceItem> defaultEvidence(String reason) =>
      <DVEvidenceItem>[
        const DVEvidenceItem('receipt', 'the receipt or invoice for the charge'),
        const DVEvidenceItem('customer_communication',
            'messages with the customer about the purchase'),
        ...switch (reason) {
          'fraudulent' => const <DVEvidenceItem>[
              DVEvidenceItem('access_activity_log',
                  'proof the customer used what they bought'),
            ],
          'product_not_received' => const <DVEvidenceItem>[
              DVEvidenceItem('shipping_documentation',
                  'proof of delivery, or of access to a digital good'),
            ],
          'duplicate' => const <DVEvidenceItem>[
              DVEvidenceItem('duplicate_charge_documentation',
                  'what distinguishes this charge from the other'),
            ],
          'subscription_canceled' => const <DVEvidenceItem>[
              DVEvidenceItem('cancellation_policy',
                  'the cancellation policy the customer agreed to'),
            ],
          'credit_not_processed' => const <DVEvidenceItem>[
              DVEvidenceItem(
                  'refund_policy', 'the refund policy the customer agreed to'),
            ],
          _ => const <DVEvidenceItem>[
              DVEvidenceItem('service_documentation',
                  'what was sold and that it was provided'),
            ],
        },
      ];

  /// Verifies a Stripe webhook and applies it when it is a dispute event.
  ///
  /// Throws [DVBillingError] for a signature that is missing, wrong or stale,
  /// having changed nothing; the route answers that with a client error.
  Future<DVDisputeResult> acceptStripeWebhook(
    DVStripeBillingProvider stripe, {
    required String payload,
    required String signatureHeader,
  }) async {
    final Map<String, Object?> event =
        stripe.verifyEvent(payload, signatureHeader);
    final DVDisputeEvent? dispute = DVStripeDisputeEvents.parse(event);
    if (dispute == null) return const DVDisputeResult();
    return accept(dispute);
  }

  /// Applies a verified dispute [event].
  ///
  /// A failure part-way rolls back what it did -- the revocation, the hold,
  /// the record -- releases the event's claim and rethrows, so the provider's
  /// retry applies.
  Future<DVDisputeResult> accept(DVDisputeEvent event) =>
      DVTransactionRunner().call<DVDisputeResult>((DVContext context) async {
        if (!await store.claimEvent(event.eventId)) {
          return DVDisputeResult(
              replayed: true, dispute: await store.find(event.disputeId));
        }
        context.compensate(() => store.releaseEvent(event.eventId));

        final DVDispute? previous = await store.find(event.disputeId);
        if (previous != null && event.occurredAt.isBefore(previous.lastEventAt)) {
          return DVDisputeResult(stale: true, dispute: previous);
        }

        final String? saleId = previous == null
            ? (await commerce.ledger.findByCharge(event.chargeReference))?.id
            : previous.saleId;
        DVDispute next = previous == null
            ? DVDispute(
                id: event.disputeId,
                provider: event.provider,
                chargeReference: event.chargeReference,
                saleId: saleId,
                amount: event.amount,
                reason: event.reason,
                status: event.status,
                evidenceDueBy: event.evidenceDueBy,
                openedAt: event.occurredAt,
                lastEventAt: event.occurredAt,
                evidence: _evidence(event.reason),
                timeline: <DVDisputeEntry>[
                  DVDisputeEntry(
                    at: event.occurredAt,
                    status: event.status,
                    message: 'The bank opened a dispute for ${event.amount} '
                        '(${event.reason}): ${event.status.name}'
                        '${event.evidenceDueBy == null ? '' : ', evidence due '
                            'by ${event.evidenceDueBy!.toIso8601String()}'}',
                  ),
                ],
              )
            : previous.copyWith(
                status: event.status,
                evidenceDueBy: event.evidenceDueBy,
                lastEventAt: event.occurredAt,
                timeline: <DVDisputeEntry>[
                  ...previous.timeline,
                  DVDisputeEntry(
                    at: event.occurredAt,
                    status: event.status,
                    message: previous.status == event.status
                        ? 'The provider updated the dispute'
                        : 'The dispute moved from ${previous.status.name} to '
                            '${event.status.name}',
                  ),
                ],
              );

        if (saleId != null) {
          next = await _consequences(context, previous, next, event, saleId);
        }

        await store.put(next);
        context.compensate(() =>
            previous == null ? store.remove(next.id) : store.put(previous));
        return DVDisputeResult(handled: true, dispute: next);
      }, isolated: true);

  Future<DVDispute> _consequences(
    DVContext context,
    DVDispute? previous,
    DVDispute next,
    DVDisputeEvent event,
    String saleId,
  ) async {
    final DVPayouts? ledger = payouts;
    final bool hasShares =
        ledger != null && await ledger.ledger.sale(saleId) != null;
    final String holdReason = 'dispute ${next.id}';

    if (!event.status.closed) {
      if (hasShares && !next.payoutsHeld) {
        await ledger.hold(saleId, reason: holdReason);
        context.compensate(() => ledger.release(saleId));
        next = next.copyWith(payoutsHeld: true);
      }
      if (revokeEntitlements == DVDisputeRevocation.onOpen &&
          !next.entitlementsRevoked) {
        await commerce.revokeSale(context, saleId);
        next = next.copyWith(entitlementsRevoked: true);
      }
      return next;
    }

    final bool newlyClosed = previous == null || !previous.status.closed;
    if (!newlyClosed) return next;

    if (event.status == DVDisputeStatus.lost) {
      if (!next.entitlementsRevoked) {
        await commerce.revokeSale(context, saleId);
        next = next.copyWith(entitlementsRevoked: true);
      }
      if (hasShares) {
        final DVPayoutSaleRecord shares = (await ledger.ledger.sale(saleId))!;
        final int left = shares.collected.amount - shares.reversed;
        final int amount =
            event.amount.amount < left ? event.amount.amount : left;
        if (amount > 0) {
          // Recorded under the dispute id, so a retry after a later failure
          // finds it already recorded rather than reversing twice.
          await ledger.recordDisputeLoss(
            saleId: saleId,
            disputeId: next.id,
            amount: DVMoney(amount: amount, currency: shares.collected.currency),
          );
        }
      }
    } else if (event.status.kept &&
        next.entitlementsRevoked &&
        revokeEntitlements == DVDisputeRevocation.onOpen) {
      await commerce.restoreSale(context, saleId);
      next = next.copyWith(entitlementsRevoked: false);
    }

    if (hasShares && next.payoutsHeld) {
      await ledger.release(saleId);
      context.compensate(() => ledger.hold(saleId, reason: holdReason));
      next = next.copyWith(payoutsHeld: false);
    }
    return next;
  }

  /// Announces every open dispute whose evidence deadline has come within a
  /// [warnBefore] threshold not yet announced, as `DV-COMMERCE-005`, and
  /// returns those disputes.
  ///
  /// A deadline that has passed is written on the timeline once. It is not a
  /// warning: there is no longer anything to act on. Run this on a schedule
  /// shorter than the smallest threshold.
  Future<List<DVDispute>> checkDeadlines() async {
    final DateTime now = _now;
    final List<DVDispute> warned = <DVDispute>[];
    for (final DVDispute dispute in await store.open()) {
      final DateTime? due = dispute.evidenceDueBy;
      if (due == null || !dispute.status.awaitingEvidence) continue;
      final Duration left = due.difference(now);
      if (left <= Duration.zero) {
        if (dispute.deadlinePassed) continue;
        _log.log(
          'The evidence deadline for dispute ${dispute.id} passed without a '
          'response',
          level: DVLogLevel.warn,
          context: <String, Object?>{'dispute': dispute.id},
        );
        await store.put(dispute.copyWith(
          deadlinePassed: true,
          timeline: <DVDisputeEntry>[
            ...dispute.timeline,
            DVDisputeEntry(
              at: now,
              source: 'deadline',
              message: 'The evidence deadline passed without a response; the '
                  'dispute is lost by default unless the provider says '
                  'otherwise',
            ),
          ],
        ));
        continue;
      }
      final Set<int> crossed = <int>{
        for (final Duration threshold in warnBefore)
          if (left <= threshold &&
              !dispute.warnedAtMinutes.contains(threshold.inMinutes))
            threshold.inMinutes,
      };
      if (crossed.isEmpty) continue;
      final List<String> missing = <String>[
        for (final DVEvidenceItem item in dispute.evidence)
          if (!item.provided) item.key,
      ];
      final String remaining = '${left.inHours}h';
      _log.log(
        'DV-COMMERCE-005: dispute ${dispute.id} for ${dispute.amount} needs '
        'evidence by ${due.toIso8601String()} ($remaining left); still '
        'missing: ${missing.isEmpty ? 'nothing' : missing.join(', ')}',
        level: DVLogLevel.warn,
        code: 'DV-COMMERCE-005',
        context: <String, Object?>{
          'dispute': dispute.id,
          'sale': dispute.saleId,
          'dueBy': due.toIso8601String(),
          'missing': missing,
        },
      );
      final DVDispute updated = dispute.copyWith(
        warnedAtMinutes: <int>{...dispute.warnedAtMinutes, ...crossed},
        timeline: <DVDisputeEntry>[
          ...dispute.timeline,
          DVDisputeEntry(
            at: now,
            source: 'deadline',
            message: 'Evidence is due in $remaining',
          ),
        ],
      );
      await store.put(updated);
      warned.add(updated);
    }
    return warned;
  }

  /// Marks the evidence item [key] of dispute [disputeId] as provided.
  Future<DVDispute> recordEvidence(String disputeId, String key) async {
    final DVDispute? dispute = await store.find(disputeId);
    if (dispute == null) {
      throw ArgumentError.value(disputeId, 'disputeId', 'is not a dispute');
    }
    if (!dispute.evidence.any((DVEvidenceItem item) => item.key == key)) {
      throw ArgumentError.value(
          key, 'key', 'is not on the evidence checklist of $disputeId');
    }
    final DVDispute updated = dispute.copyWith(
      evidence: <DVEvidenceItem>[
        for (final DVEvidenceItem item in dispute.evidence)
          item.key == key
              ? DVEvidenceItem(item.key, item.description, provided: true)
              : item,
      ],
      timeline: <DVDisputeEntry>[
        ...dispute.timeline,
        DVDisputeEntry(
            at: _now, source: 'human', message: 'Evidence recorded: $key'),
      ],
    );
    await store.put(updated);
    return updated;
  }
}
