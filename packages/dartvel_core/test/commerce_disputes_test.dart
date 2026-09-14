// A dispute is not a refund.
//
// It is started by the customer's bank, it arrives as a signed webhook, and it
// has a deadline the application does not control. The silent failures: a
// webhook that nothing checks the signature of, so anybody can "win" a
// dispute; a retried delivery that reverses a seller's share twice; a late
// "created" landing behind "lost" and putting the hold back; a lost dispute
// that leaves the customer holding what the bank took the money back for;
// a deadline that passes with nobody told while there was still time
// (DV-COMMERCE-005).
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String table = '''
{
  "asOf": "2026-09-01",
  "rounding": {"mode": "halfUp", "scope": "document"},
  "jurisdictions": {
    "GB": {"discountBasis": "afterDiscount", "rates": {"digitalService": "20"}}
  }
}
''';

const Entitlement pro = Entitlement('pro');
const String secret = 'whsec_test';

DVMoney gbp(int amount) => DVMoney(amount: amount, currency: 'GBP');

class Customer implements DVBillingCustomer {
  const Customer(this.id);
  final String id;
  @override
  String get billingCustomerId => 'customer:$id';
}

class Gateway implements DVPaymentGateway {
  int charges = 0;
  final List<DVGatewayRefund> refunds = <DVGatewayRefund>[];

  @override
  Future<DVGatewayCharge> charge({
    required String orderId,
    required String customerKey,
    required DVMoney amount,
    required String idempotencyKey,
  }) async =>
      DVGatewayCharge(reference: 'ch_${++charges}', amount: amount);

  @override
  Future<DVGatewayRefund> refund({
    required String chargeReference,
    required DVMoney amount,
    required String idempotencyKey,
  }) async {
    final DVGatewayRefund refund =
        DVGatewayRefund(reference: 're_${refunds.length + 1}', amount: amount);
    refunds.add(refund);
    return refund;
  }
}

class FlakyGrants implements DVEntitlementGrants {
  FlakyGrants(this.inner);
  final DVEntitlementGrants inner;
  bool failRevoke = false;

  @override
  Future<void> grant(String customerKey, Set<Entitlement> entitlements) =>
      inner.grant(customerKey, entitlements);

  @override
  Future<void> revoke(String customerKey, Set<Entitlement> entitlements) {
    if (failRevoke) throw StateError('entitlement store is down');
    return inner.revoke(customerKey, entitlements);
  }
}

class Connect implements DVConnectedAccountProvider {
  final List<DVTransfer> transfers = <DVTransfer>[];

  @override
  Future<DVConnectedAccount> account(String accountId) async =>
      DVConnectedAccount(
          id: accountId,
          status: DVConnectedAccountStatus.verified,
          payoutsEnabled: true);

  @override
  Future<DVTransfer> transfer({
    required String accountId,
    required DVMoney amount,
    required String idempotencyKey,
  }) async {
    final DVTransfer t = DVTransfer(
        reference: 'tr_${transfers.length + 1}',
        accountId: accountId,
        amount: amount);
    transfers.add(t);
    return t;
  }
}

void main() {
  final DateTime start = DateTime.utc(2026, 9, 14, 12);
  final DateTime due = start.add(const Duration(days: 5));
  late DateTime clock;
  late DVMemoryLogSink logs;
  late DVLocalBillingProvider billing;
  late FlakyGrants grants;
  late DVCommerce commerce;
  late DVPayouts payouts;
  late DVStripeBillingProvider stripe;
  late DVDisputeStore store;
  late DVSale sale;

  List<String> codes() =>
      logs.records.map((DVLogRecord r) => r.code).whereType<String>().toList();

  String event({
    required String id,
    required String type,
    required String status,
    DateTime? created,
    DateTime? dueBy,
    String charge = 'ch_1',
    String reason = 'fraudulent',
  }) =>
      jsonEncode(<String, Object?>{
        'id': id,
        'type': type,
        'created': (created ?? clock).millisecondsSinceEpoch ~/ 1000,
        'data': <String, Object?>{
          'object': <String, Object?>{
            'id': 'dp_1',
            'object': 'dispute',
            'charge': charge,
            'amount': 1200,
            'currency': 'gbp',
            'reason': reason,
            'status': status,
            'evidence_details': <String, Object?>{
              'due_by':
                  dueBy == null ? null : dueBy.millisecondsSinceEpoch ~/ 1000,
              'has_evidence': false,
              'submission_count': 0,
            },
          },
        },
      });

  String sign(String payload) {
    final int t = clock.millisecondsSinceEpoch ~/ 1000;
    final String v1 = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('$t.$payload'))
        .toString();
    return 't=$t,v1=$v1';
  }

  DVDisputes disputes({
    DVDisputeRevocation revoke = DVDisputeRevocation.onLoss,
  }) =>
      DVDisputes(
        store: store,
        commerce: commerce,
        payouts: payouts,
        revokeEntitlements: revoke,
        clock: () => clock,
        logger: DVLogger(sinks: <DVLogSink>[logs]),
      );

  Future<DVDisputeResult> deliver(DVDisputes subject, String payload) =>
      subject.acceptStripeWebhook(stripe,
          payload: payload, signatureHeader: sign(payload));

  String opened() => event(
      id: 'evt_open',
      type: 'charge.dispute.created',
      status: 'needs_response',
      dueBy: due);

  String lost() => event(
      id: 'evt_lost',
      type: 'charge.dispute.closed',
      status: 'lost',
      dueBy: due);

  String won() => event(
      id: 'evt_won',
      type: 'charge.dispute.closed',
      status: 'won',
      dueBy: due);

  setUp(() async {
    clock = start;
    logs = DVMemoryLogSink();
    final DVLogger logger = DVLogger(sinks: <DVLogSink>[logs]);
    billing = DVLocalBillingProvider();
    grants = FlakyGrants(DVLocalBillingGrants(billing));
    commerce = DVCommerce(
      tax: DVTax(
        provider: DVTableTaxProvider(DVTaxTable.fromJson(table)),
        clock: () => clock,
        logger: logger,
      ),
      gateway: Gateway(),
      ledger: DVMemoryCommerceLedger(),
      grants: grants,
      clock: () => clock,
      logger: logger,
    );
    sale = await commerce.charge(
      orderId: 'o1',
      customer: const Customer('alice'),
      lines: <DVOrderLine>[
        DVOrderLine(
          reference: 'a',
          productId: 'course',
          unitPrice: gbp(1000),
          category: DVTaxCategory.digitalService,
        ),
      ],
      to: const DVTaxAddress(country: 'GB'),
      entitlements: const <Entitlement>{pro},
    );
    payouts = DVPayouts(
      ledger: DVMemoryPayoutLedger(),
      provider: Connect(),
      clock: () => clock,
      logger: logger,
    );
    await payouts.recordSale(
      saleId: sale.id,
      collected: sale.total,
      split: DVPayoutSplit(
          recipients: const <String, int>{'acct_seller': 1},
          platformFeeBasisPoints: 1000),
    );
    stripe = DVStripeBillingProvider(
      secretKey: 'sk_test_x',
      webhookSecret: secret,
      prices: const <String, String>{},
      entitlements: const <String, Set<Entitlement>>{},
      successUrl: Uri.parse('https://example.test/ok'),
      cancelUrl: Uri.parse('https://example.test/cancel'),
      clock: () => clock,
    );
    store = DVMemoryDisputeStore();
  });

  Future<bool> entitled() => billing.hasEntitlement('customer:alice', pro);

  Future<DVPayoutStatus> payoutNow(String key) async => (await payouts.payout(
          accountId: 'acct_seller', currency: 'GBP', key: key))
      .status;

  test('an opened dispute has a deadline, a checklist and a timeline, and '
      'holds the payout', () async {
    final DVDisputeResult result = await deliver(disputes(), opened());
    expect(result.handled, isTrue);
    final DVDispute dispute = result.dispute!;
    expect(dispute.id, 'dp_1');
    expect(dispute.saleId, 'o1');
    expect(dispute.amount, gbp(1200));
    expect(dispute.status, DVDisputeStatus.needsResponse);
    expect(dispute.evidenceDueBy, due);
    expect(dispute.evidence.map((DVEvidenceItem e) => e.key),
        containsAll(<String>['receipt', 'customer_communication']));
    expect(dispute.evidence.every((DVEvidenceItem e) => !e.provided), isTrue);
    expect(dispute.timeline, hasLength(1));
    expect(await payoutNow('k1'), DVPayoutStatus.nothingDue);
    // Not lost yet, so nothing is taken back yet.
    expect(await entitled(), isTrue);
    expect((await commerce.ledger.find('o1'))!.refunded, gbp(0));
  });

  test('a webhook with a wrong signature changes nothing', () async {
    final String payload = opened();
    await expectLater(
      disputes().acceptStripeWebhook(stripe,
          payload: payload,
          signatureHeader: sign(payload).replaceFirst('v1=', 'v1=0')),
      throwsA(isA<DVBillingError>()),
    );
    expect(await store.find('dp_1'), isNull);
    expect(await payoutNow('k1'), DVPayoutStatus.paid);
  });

  test('an event that is not a dispute is not handled here', () async {
    final String payload = jsonEncode(<String, Object?>{
      'id': 'evt_x',
      'type': 'customer.subscription.updated',
      'created': clock.millisecondsSinceEpoch ~/ 1000,
      'data': <String, Object?>{'object': <String, Object?>{}},
    });
    final DVDisputeResult result = await deliver(disputes(), payload);
    expect(result.handled, isFalse);
    expect(result.dispute, isNull);
  });

  test('a lost dispute takes back what was sold and reverses the shares, once',
      () async {
    final DVDisputes subject = disputes();
    await deliver(subject, opened());
    clock = start.add(const Duration(days: 6));
    await deliver(subject, lost());
    expect(await entitled(), isFalse);
    expect(await payouts.balance('acct_seller', 'GBP'), 0);
    expect(await payouts.balance(DVPayouts.platform, 'GBP'), 0);
    expect((await store.find('dp_1'))!.status, DVDisputeStatus.lost);

    final DVDisputeResult again = await deliver(subject, lost());
    expect(again.replayed, isTrue);
    expect(await payouts.balance('acct_seller', 'GBP'), 0);
    expect((await store.find('dp_1'))!.timeline, hasLength(2));
    // A dispute is not a refund: nothing was refunded through the gateway.
    expect((await commerce.ledger.find('o1'))!.refunded, gbp(0));
  });

  test('a won dispute releases the payout and keeps the sale', () async {
    final DVDisputes subject = disputes();
    await deliver(subject, opened());
    clock = start.add(const Duration(days: 6));
    await deliver(subject, won());
    expect(await entitled(), isTrue);
    expect(await payoutNow('k1'), DVPayoutStatus.paid);
  });

  test('revoking on open restores what was revoked when the dispute is won',
      () async {
    final DVDisputes subject = disputes(revoke: DVDisputeRevocation.onOpen);
    await deliver(subject, opened());
    expect(await entitled(), isFalse);
    clock = start.add(const Duration(days: 6));
    await deliver(subject, won());
    expect(await entitled(), isTrue);
  });

  test('a late event older than one applied is stale and changes nothing',
      () async {
    final DVDisputes subject = disputes();
    clock = start.add(const Duration(days: 6));
    await deliver(subject, lost());
    final DVDisputeResult late = await deliver(
        subject,
        event(
            id: 'evt_open',
            type: 'charge.dispute.created',
            status: 'needs_response',
            created: start,
            dueBy: due));
    expect(late.stale, isTrue);
    expect((await store.find('dp_1'))!.status, DVDisputeStatus.lost);
    expect(await payouts.balance('acct_seller', 'GBP'), 0);
    expect(await payoutNow('k1'), DVPayoutStatus.nothingDue);
    expect(await entitled(), isFalse);
  });

  test('a delivery that fails part-way is applied by the retry', () async {
    final DVDisputes subject = disputes();
    await deliver(subject, opened());
    clock = start.add(const Duration(days: 6));
    grants.failRevoke = true;
    await expectLater(deliver(subject, lost()), throwsStateError);
    expect((await store.find('dp_1'))!.status, DVDisputeStatus.needsResponse);
    expect(await payouts.balance('acct_seller', 'GBP'), 1080);
    expect(await entitled(), isTrue);

    grants.failRevoke = false;
    final DVDisputeResult retried = await deliver(subject, lost());
    expect(retried.handled, isTrue);
    expect(await entitled(), isFalse);
    expect(await payouts.balance('acct_seller', 'GBP'), 0);
  });

  test('a dispute for a charge no sale made is recorded and touches nothing',
      () async {
    final DVDisputeResult result = await deliver(
        disputes(),
        event(
            id: 'evt_open',
            type: 'charge.dispute.created',
            status: 'needs_response',
            charge: 'ch_unknown',
            dueBy: due));
    expect(result.handled, isTrue);
    expect(result.dispute!.saleId, isNull);
    expect(await payoutNow('k1'), DVPayoutStatus.paid);
  });

  group('the deadline', () {
    test('warns while there is time to act, once per threshold', () async {
      final DVDisputes subject = disputes();
      await deliver(subject, opened());

      expect(await subject.checkDeadlines(), isEmpty);

      clock = start.add(const Duration(days: 2, hours: 12)); // 2.5 days left
      expect((await subject.checkDeadlines()).map((DVDispute d) => d.id),
          <String>['dp_1']);
      expect(await subject.checkDeadlines(), isEmpty);
      expect(codes(), <String>['DV-COMMERCE-005']);
      expect(logs.records.last.level, DVLogLevel.warn);

      clock = start.add(const Duration(days: 4, hours: 12)); // half a day
      expect(await subject.checkDeadlines(), hasLength(1));
      expect(codes(), <String>['DV-COMMERCE-005', 'DV-COMMERCE-005']);
    });

    test('stops warning once evidence is under review', () async {
      final DVDisputes subject = disputes();
      await deliver(subject, opened());
      clock = start.add(const Duration(days: 4));
      await deliver(
          subject,
          event(
              id: 'evt_review',
              type: 'charge.dispute.updated',
              status: 'under_review',
              dueBy: due));
      clock = start.add(const Duration(days: 4, hours: 20));
      expect(await subject.checkDeadlines(), isEmpty);
      expect(codes(), isEmpty);
    });

    test('that has passed is on the timeline, and is not a warning', () async {
      final DVDisputes subject = disputes();
      await deliver(subject, opened());
      clock = due.add(const Duration(minutes: 1));
      expect(await subject.checkDeadlines(), isEmpty);
      expect(codes(), isEmpty);
      final DVDispute dispute = (await store.find('dp_1'))!;
      expect(dispute.timeline.last.message, contains('deadline passed'));
      await subject.checkDeadlines();
      expect((await store.find('dp_1'))!.timeline, hasLength(2));
    });
  });

  test('evidence is checked off the list, and only what is on it', () async {
    final DVDisputes subject = disputes();
    await deliver(subject, opened());
    final DVDispute dispute = await subject.recordEvidence('dp_1', 'receipt');
    expect(
        dispute.evidence
            .firstWhere((DVEvidenceItem e) => e.key == 'receipt')
            .provided,
        isTrue);
    expect(dispute.timeline, hasLength(2));
    await expectLater(
        subject.recordEvidence('dp_1', 'a_poem'), throwsArgumentError);
  });
}
