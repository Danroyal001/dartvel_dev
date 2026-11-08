// Closing a period: every tenant's usage reported once the period can no
// longer change, without anybody remembering to run it.
//
// A report nobody triggers is an invoice with no usage on it. A report sent
// before the grace has passed under-bills by whatever arrives late. A close
// that runs every hour and resends everything is a provider call per tenant
// per meter per hour, forever.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Provider implements DVBillingProvider {
  final List<String> reported = <String>[];
  bool failing = false;

  @override
  Future<void> recordUsage({
    required Object customer,
    required DVUsageMeter meter,
    required int quantity,
    required String idempotencyKey,
    DateTime? at,
  }) async {
    if (failing) throw StateError('provider unavailable');
    reported.add('$customer ${meter.id} $quantity');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final DVMeterDefinition calls = DVMeterDefinition('api_calls',
      unit: 'call', grace: const Duration(hours: 6));
  late DateTime now;
  late DVMeters meters;
  late _Provider provider;
  late DVMeterReporter reporter;

  Future<void> use(String tenant, num amount, String key, DateTime at) async {
    final DateTime saved = now;
    now = at;
    await const DVTenants().withTenant(tenant, () async {
      await meters.record(calls, amount, idempotencyKey: key);
    });
    now = saved;
  }

  setUp(() async {
    now = DateTime.utc(2026, 9, 20);
    meters = DVMeters(store: DVMemoryMeterStore(), clock: () => now);
    provider = _Provider();
    reporter = DVMeterReporter(
      meters: meters,
      provider: provider,
      customerFor: (String tenant) => 'cus_$tenant',
      isPriced: (String tenant, DVMeterDefinition meter) => true,
    );
    await use('acme', 3, 'a', DateTime.utc(2026, 9, 5));
    await use('globex', 5, 'g', DateTime.utc(2026, 9, 6));
  });

  tearDown(DVTenants.reset);

  test('nothing is closed while the period is open or inside its grace',
      () async {
    now = DateTime.utc(2026, 9, 29);
    expect(await reporter.closePeriods(tenants: <String>['acme'], meters: <DVMeterDefinition>[calls]),
        isEmpty);
    now = DateTime.utc(2026, 10, 1, 5);
    expect(await reporter.closePeriods(tenants: <String>['acme'], meters: <DVMeterDefinition>[calls]),
        isEmpty);
    expect(provider.reported, isEmpty);
  });

  test('after the grace every tenant\'s last period is reported, once',
      () async {
    now = DateTime.utc(2026, 10, 1, 7);
    final List<DVMeterReport> reports = await reporter.closePeriods(
        tenants: <String>['acme', 'globex'], meters: <DVMeterDefinition>[calls]);
    expect(reports.map((DVMeterReport r) => r.status),
        everyElement(DVMeterReportStatus.reported));
    expect(provider.reported,
        unorderedEquals(<String>['cus_acme api_calls 3', 'cus_globex api_calls 5']));

    now = DateTime.utc(2026, 10, 1, 8);
    expect(
        await reporter.closePeriods(
            tenants: <String>['acme', 'globex'], meters: <DVMeterDefinition>[calls]),
        isEmpty,
        reason: 'the next run has nothing new to send');
    expect(provider.reported, hasLength(2));
  });

  test('a report that failed is sent again by the next close', () async {
    provider.failing = true;
    now = DateTime.utc(2026, 10, 1, 7);
    final List<DVMeterReport> first = await reporter.closePeriods(
        tenants: <String>['acme'], meters: <DVMeterDefinition>[calls]);
    expect(first.single.status, DVMeterReportStatus.queued);

    provider.failing = false;
    now = DateTime.utc(2026, 10, 1, 8);
    await reporter.closePeriods(
        tenants: <String>['acme'], meters: <DVMeterDefinition>[calls]);
    expect(provider.reported, <String>['cus_acme api_calls 3']);
  });

  test('one tenant that cannot be reported does not stop the others',
      () async {
    final DVMeterReporter picky = DVMeterReporter(
      meters: meters,
      provider: provider,
      customerFor: (String tenant) => 'cus_$tenant',
      isPriced: (String tenant, DVMeterDefinition meter) =>
          tenant == 'acme' ? throw StateError('plan lookup failed') : true,
    );
    now = DateTime.utc(2026, 10, 1, 7);
    await picky.closePeriods(
        tenants: <String>['acme', 'globex'], meters: <DVMeterDefinition>[calls]);
    expect(provider.reported, <String>['cus_globex api_calls 5']);
  });

  test('the close is a scheduled task', () async {
    final DVScheduler scheduler = DVScheduler(clock: () => now);
    reporter.scheduleClose(
      scheduler,
      tenants: () => <String>['acme', 'globex'],
      meters: <DVMeterDefinition>[calls],
    );
    expect(scheduler.names, contains('dartvel.meters.close'));
    now = DateTime.utc(2026, 10, 1, 7, 15);
    await scheduler.tick();
    expect(provider.reported, hasLength(2));
  });
}
