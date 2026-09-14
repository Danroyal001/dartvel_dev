// Asking a meter whether an amount would be admitted, without recording it.
//
// A caller that must decide before spending -- an AI feature about to call a
// provider -- cannot use record(), which counts the amount as it checks it.
// Recording the worst case up front bills a customer for tokens nobody used;
// recording afterwards checks the budget once it has already been spent.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late DVMemoryMeterStore store;
  late DVMeters meters;

  setUp(() {
    now = DateTime.utc(2026, 9, 15, 12);
    store = DVMemoryMeterStore();
    meters = DVMeters(store: store, clock: () => now);
  });

  tearDown(DVTenants.reset);

  test('an amount that fits is admitted and nothing is stored', () async {
    final DVMeterDefinition meter = DVMeterDefinition('aiTokens',
        unit: 'token', limit: const DVLimit.fixed(100), atLimit: DVQuota.block);
    await const DVTenants().withTenant('acme', () async {
      await meters.record(meter, 60, idempotencyKey: 'a');
      final DVMeterOutcome outcome = await meters.admits(meter, 40);
      expect(outcome.admitted, isTrue);
      expect(outcome.recorded, isFalse);
      expect(outcome.applied, isNull);
      expect(outcome.total, 60);
    });
    expect(store.recordCount, 1);
  });

  test('an amount past a block limit is not admitted', () async {
    final DVMeterDefinition meter = DVMeterDefinition('aiTokens',
        unit: 'token', limit: const DVLimit.fixed(100), atLimit: DVQuota.block);
    await const DVTenants().withTenant('acme', () async {
      await meters.record(meter, 60, idempotencyKey: 'a');
      final DVMeterOutcome outcome = await meters.admits(meter, 41);
      expect(outcome.admitted, isFalse);
      expect(outcome.applied, DVQuota.block);
      expect(outcome.limit, 100);
    });
    expect(store.recordCount, 1);
  });

  test('past a throttle limit it is admitted with the behaviour named',
      () async {
    final DVMeterDefinition meter = DVMeterDefinition('aiTokens',
        unit: 'token',
        limit: const DVLimit.fixed(100),
        atLimit: DVQuota.throttle);
    await const DVTenants().withTenant('acme', () async {
      final DVMeterOutcome outcome = await meters.admits(meter, 101);
      expect(outcome.admitted, isTrue);
      expect(outcome.applied, DVQuota.throttle);
    });
  });

  test('the tenant is the current one', () async {
    final DVMeterDefinition meter = DVMeterDefinition('aiTokens',
        unit: 'token', limit: const DVLimit.fixed(100), atLimit: DVQuota.block);
    await const DVTenants().withTenant('acme',
        () => meters.record(meter, 100, idempotencyKey: 'a'));
    await const DVTenants().withTenant('globex', () async {
      expect((await meters.admits(meter, 100)).admitted, isTrue);
    });
  });
}
