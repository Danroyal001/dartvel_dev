// The period is the tenant's billing period, taken from the provider.
//
// An invoice cut on the eleventh and usage counted from the first is a
// reconciliation argument every month. The provider knows when each
// subscription's period starts and ends; this reads it, remembers it so a
// recording does not cost a provider call, and falls back to the calendar
// month -- saying so -- only when there is no period to read.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class FakeSubscriptions implements DVSubscriptionLifecycle {
  final Map<String, DVSubscriptionStatus> byCustomer =
      <String, DVSubscriptionStatus>{};
  int calls = 0;
  Object? failWith;

  @override
  Future<DVSubscriptionStatus> subscriptionStatus(
      {required Object customer}) async {
    calls++;
    if (failWith != null) throw failWith!;
    return byCustomer['$customer'] ??
        const DVSubscriptionStatus(status: 'none');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSubscriptions provider;
  late DateTime now;
  late DVProviderBillingPeriods periods;
  final DVMeterDefinition calls = DVMeterDefinition('api_calls', unit: 'call');

  setUp(() {
    provider = FakeSubscriptions();
    now = DateTime.utc(2026, 9, 15, 12);
    periods = DVProviderBillingPeriods(
      provider,
      customerFor: (String tenant) => 'cus_$tenant',
      clock: () => now,
    );
    provider.byCustomer['cus_acme'] = DVSubscriptionStatus(
      status: 'active',
      currentPeriodStart: DateTime.utc(2026, 9, 11),
      currentPeriodEnd: DateTime.utc(2026, 10, 11),
    );
  });

  tearDown(DVTenants.reset);

  test("usage is counted in the provider's period for the tenant", () async {
    final DVMeters meters = DVMeters(
        store: DVMemoryMeterStore(), clock: () => now, periods: periods.call);
    late DVMeterOutcome outcome;
    await const DVTenants().withTenant('acme', () async {
      outcome = await meters.record(calls, 1, idempotencyKey: 'a');
    });
    expect(outcome.period,
        DVMeterPeriod(DateTime.utc(2026, 9, 11), DateTime.utc(2026, 10, 11)));
    expect(outcome.codes, isNot(contains('DV-METER-010')));
  });

  test('the period is remembered, not asked for on every recording', () async {
    for (int i = 0; i < 5; i++) {
      await periods('acme', now);
    }
    expect(provider.calls, 1);
  });

  test('a new period is read once the remembered one has ended', () async {
    await periods('acme', now);
    provider.byCustomer['cus_acme'] = DVSubscriptionStatus(
      status: 'active',
      currentPeriodStart: DateTime.utc(2026, 10, 11),
      currentPeriodEnd: DateTime.utc(2026, 11, 11),
    );
    now = DateTime.utc(2026, 10, 12);
    expect(await periods('acme', now),
        DVMeterPeriod(DateTime.utc(2026, 10, 11), DateTime.utc(2026, 11, 11)));
    // A late record from the period before still finds the one it belongs to.
    expect(await periods('acme', DateTime.utc(2026, 10, 10)),
        DVMeterPeriod(DateTime.utc(2026, 9, 11), DateTime.utc(2026, 10, 11)));
    expect(provider.calls, 2);
  });

  test('a tenant with no subscription has no billing period', () async {
    expect(await periods('globex', now), isNull);
    // Asked again a moment later, the answer is still remembered.
    expect(await periods('globex', now), isNull);
    expect(provider.calls, 1);
  });

  test('so its usage falls back to the calendar month, and says so', () async {
    final DVMeters meters = DVMeters(
        store: DVMemoryMeterStore(), clock: () => now, periods: periods.call);
    late DVMeterOutcome outcome;
    await const DVTenants().withTenant('globex', () async {
      outcome = await meters.record(calls, 1, idempotencyKey: 'a');
    });
    expect(outcome.period, DVMeterPeriod.calendarMonth(now));
    expect(outcome.codes, contains('DV-METER-010'));
  });

  test('a provider that cannot be reached does not stop the recording',
      () async {
    provider.failWith = StateError('Stripe is down');
    final DVMeters meters = DVMeters(
        store: DVMemoryMeterStore(), clock: () => now, periods: periods.call);
    late DVMeterOutcome outcome;
    await const DVTenants().withTenant('acme', () async {
      outcome = await meters.record(calls, 1, idempotencyKey: 'a');
    });
    expect(outcome.recorded, isTrue);
    expect(outcome.codes, contains('DV-METER-010'));
  });

  test('a period that does not contain the instant asked about is not used',
      () async {
    // A provider answering a stale period must not place today's usage in it.
    provider.byCustomer['cus_acme'] = DVSubscriptionStatus(
      status: 'active',
      currentPeriodStart: DateTime.utc(2026, 8, 11),
      currentPeriodEnd: DateTime.utc(2026, 9, 11),
    );
    expect(await periods('acme', now), isNull);
    // And a stale answer is not asked for again on every recording.
    expect(await periods('acme', now), isNull);
    expect(provider.calls, 1);
  });

}
