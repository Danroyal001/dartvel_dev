// Reporting usage to the billing provider, and what happens when that fails.
//
// This is the step where a counting mistake becomes money. A report sent twice
// bills twice unless the provider can tell it is the same report. A report
// sent before late usage has arrived under-bills, quietly, every month. A
// report that failed and was dropped is revenue that silently did not exist.
// And a difference between Dartvel's figure and the provider's, resolved
// automatically, hides the class of bug reconciliation exists to find.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// The local provider, with a switch that makes usage reports fail.
class _FlakyProvider implements DVBillingProvider {
  final DVLocalBillingProvider inner = DVLocalBillingProvider();
  bool failing = false;
  int calls = 0;

  @override
  Future<void> recordUsage({
    required Object customer,
    required DVUsageMeter meter,
    required int quantity,
    required String idempotencyKey,
    DateTime? at,
  }) async {
    calls++;
    if (failing) throw StateError('provider unavailable');
    await inner.recordUsage(
      customer: customer,
      meter: meter,
      quantity: quantity,
      idempotencyKey: idempotencyKey,
      at: at,
    );
  }

  @override
  Future<DVBillingCheckoutSession> checkout(
          {required BillingPlan plan, required Object customer}) =>
      inner.checkout(plan: plan, customer: customer);

  @override
  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) =>
      inner.hasEntitlement(customer, entitlement);

  @override
  Future<List<DVInvoice>> invoices(Object customer, {int limit = 20}) =>
      inner.invoices(customer, limit: limit);
}

void main() {
  final DVMeterPeriod september =
      DVMeterPeriod(DateTime.utc(2026, 9), DateTime.utc(2026, 10));
  final DVMeterDefinition apiCalls = DVMeterDefinition('api_calls',
      unit: 'call', kind: DVMeterKind.counter, grace: const Duration(hours: 6));
  final DVMeterDefinition storage = DVMeterDefinition('stored_gb',
      unit: 'GB-month',
      kind: DVMeterKind.gauge,
      grace: const Duration(hours: 6));

  late DateTime now;
  late DVMeters meters;
  late _FlakyProvider provider;
  late DVMeterReporter reporter;

  DVMeterReporter reporterWith({
    DVMeterReportQueue? queue,
    bool Function(String tenant, DVMeterDefinition meter)? priced,
    Object? Function(String tenant)? customer,
  }) =>
      DVMeterReporter(
        meters: meters,
        provider: provider,
        customerFor: customer ?? (String tenant) => 'cus_$tenant',
        isPriced: priced ?? (String tenant, DVMeterDefinition meter) => true,
        queue: queue,
      );

  Future<void> recordIn(String tenant, DVMeterDefinition meter, num amount,
      String key, DateTime at) async {
    final DateTime saved = now;
    now = at;
    await const DVTenants().withTenant(tenant, () async {
      await meters.record(meter, amount, idempotencyKey: key, at: at);
    });
    now = saved;
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 2);
    meters = DVMeters(store: DVMemoryMeterStore(), clock: () => now);
    provider = _FlakyProvider();
    reporter = reporterWith();
  });

  tearDown(DVTenants.reset);

  test('a closed period is reported once, however many times it is sent',
      () async {
    await recordIn('acme', apiCalls, 3, 'a', DateTime.utc(2026, 9, 5));
    await recordIn('acme', apiCalls, 4, 'b', DateTime.utc(2026, 9, 20));

    final DVMeterReport first =
        await reporter.report(apiCalls, tenant: 'acme', period: september);
    final DVMeterReport again =
        await reporter.report(apiCalls, tenant: 'acme', period: september);

    expect(first.status, DVMeterReportStatus.reported);
    expect(first.quantity, 7);
    expect(again.idempotencyKey, first.idempotencyKey,
        reason: 'the key is the period, not the attempt');
    expect(provider.inner.usage('cus_acme', const DVUsageMeter('api_calls')), 7,
        reason: 'sending the same report twice must not bill twice');
  });

  test('a period is not reported while usage can still arrive for it',
      () async {
    await recordIn('acme', apiCalls, 1, 'a', DateTime.utc(2026, 9, 5));

    now = DateTime.utc(2026, 9, 25);
    expect(() => reporter.report(apiCalls, tenant: 'acme', period: september),
        throwsStateError,
        reason: 'the period is still open');

    now = DateTime.utc(2026, 10, 1, 3);
    expect(() => reporter.report(apiCalls, tenant: 'acme', period: september),
        throwsStateError,
        reason: 'closed, but a late record could still be accepted into it');
    expect(provider.calls, 0);
  });

  test('a late record accepted under the grace is in the report', () async {
    await recordIn('acme', apiCalls, 2, 'on-time', DateTime.utc(2026, 9, 29));
    // Arrives an hour after the period closed, inside the six-hour grace.
    now = DateTime.utc(2026, 10, 1, 1);
    await const DVTenants().withTenant('acme', () async {
      await meters.record(apiCalls, 5,
          idempotencyKey: 'late', at: DateTime.utc(2026, 9, 30, 23));
    });

    now = DateTime.utc(2026, 10, 2);
    final DVMeterReport report =
        await reporter.report(apiCalls, tenant: 'acme', period: september);
    expect(report.quantity, 7);
  });

  test('a period with no usage reports nothing and calls nobody', () async {
    final DVMeterReport report =
        await reporter.report(apiCalls, tenant: 'acme', period: september);
    expect(report.status, DVMeterReportStatus.nothingToReport);
    expect(provider.calls, 0,
        reason: 'the provider refuses a zero quantity as a measurement');
  });

  test('a meter with no price is counted, not billed, and says so', () async {
    final DVMeterReporter unpriced = reporterWith(
        priced: (String tenant, DVMeterDefinition meter) => false);
    await recordIn('acme', apiCalls, 9, 'a', DateTime.utc(2026, 9, 5));

    final DVMeterReport report =
        await unpriced.report(apiCalls, tenant: 'acme', period: september);

    expect(report.status, DVMeterReportStatus.notBilled);
    expect(report.codes, contains('DV-METER-009'));
    expect(provider.calls, 0);
    expect(await meters.usage(apiCalls, tenant: 'acme', period: september), 9,
        reason: 'not billing it does not mean not counting it');
  });

  test('a report that fails is queued, and a retry sends it', () async {
    await recordIn('acme', apiCalls, 6, 'a', DateTime.utc(2026, 9, 5));
    provider.failing = true;

    final DVMeterReport failed =
        await reporter.report(apiCalls, tenant: 'acme', period: september);
    expect(failed.status, DVMeterReportStatus.queued);
    expect(failed.codes, contains('DV-METER-006'));
    expect(await reporter.queue.pending(), hasLength(1),
        reason: 'a dropped report is revenue that silently did not exist');

    provider.failing = false;
    final List<DVMeterReport> sent = await reporter.retryPending();
    expect(sent.map((DVMeterReport r) => r.status),
        <DVMeterReportStatus>[DVMeterReportStatus.reported]);
    expect(await reporter.queue.pending(), isEmpty);
    expect(provider.inner.usage('cus_acme', const DVUsageMeter('api_calls')), 6);
  });

  test('a retry that fails again stays queued', () async {
    await recordIn('acme', apiCalls, 6, 'a', DateTime.utc(2026, 9, 5));
    provider.failing = true;
    await reporter.report(apiCalls, tenant: 'acme', period: september);

    final List<DVMeterReport> sent = await reporter.retryPending();
    expect(sent, isEmpty);
    expect(await reporter.queue.pending(), hasLength(1));
  });

  test('a tenant with no billing customer is queued, not dropped', () async {
    final DVMeterReporter orphaned =
        reporterWith(customer: (String tenant) => null);
    await recordIn('acme', apiCalls, 2, 'a', DateTime.utc(2026, 9, 5));

    final DVMeterReport report =
        await orphaned.report(apiCalls, tenant: 'acme', period: september);
    expect(report.status, DVMeterReportStatus.queued);
    expect(report.codes, contains('DV-METER-006'));
    expect(provider.calls, 0);
  });

  test('a gauge is reported as a whole number, rounded up', () async {
    await recordIn('acme', storage, 20, 's1', DateTime.utc(2026, 9, 5));
    await recordIn('acme', storage, 21, 's2', DateTime.utc(2026, 9, 20));

    final DVMeterReport report =
        await reporter.report(storage, tenant: 'acme', period: september);
    expect(report.quantity, 21,
        reason: 'an average of 20.5 GB is billed as 21, never as 20');
  });

  test('reconciliation lists every difference and resolves none', () async {
    await recordIn('acme', apiCalls, 7, 'a', DateTime.utc(2026, 9, 5));
    await recordIn('globex', apiCalls, 4, 'g', DateTime.utc(2026, 9, 5));

    final List<DVMeterDifference> differences = await reporter.reconcile(
      period: september,
      tenants: <String>['acme', 'globex', 'initech'],
      meters: <DVMeterDefinition>[apiCalls],
      providerFigure: (String tenant, DVMeterDefinition meter) =>
          <String, num>{'acme': 7, 'globex': 3}[tenant] ?? 0,
    );

    expect(differences, hasLength(1));
    expect(differences.single.tenant, 'globex');
    expect(differences.single.ours, 4);
    expect(differences.single.theirs, 3);
    expect(provider.calls, 0, reason: 'reconciling reports nothing');
    expect(await meters.usage(apiCalls, tenant: 'globex', period: september), 4,
        reason: 'and changes nothing');
  });

  for (final (String name, DVDatabaseAdapter Function() open)
      in <(String, DVDatabaseAdapter Function())>[
    ('in-memory', MemoryDVDatabaseAdapter.new),
    ('sqlite', SqliteDVDatabaseAdapter.memory),
  ]) {
    test('a queued report on the $name database outlives the reporter',
        () async {
      const DVDatabase().configure(open());
      addTearDown(const DVDatabase().unconfigure);

      await recordIn('acme', apiCalls, 5, 'a', DateTime.utc(2026, 9, 5));
      provider.failing = true;
      await reporterWith(queue: DVDatabaseMeterReportQueue())
          .report(apiCalls, tenant: 'acme', period: september);

      // A new reporter -- a restart, another instance -- finds the report.
      provider.failing = false;
      final DVMeterReporter restarted =
          reporterWith(queue: DVDatabaseMeterReportQueue());
      final List<DVMeterReport> sent = await restarted.retryPending();

      expect(sent, hasLength(1));
      expect(await restarted.queue.pending(), isEmpty);
      expect(
          provider.inner.usage('cus_acme', const DVUsageMeter('api_calls')), 5);
    });
  }
}
