// The idempotency key a scope supplies: one per request or job, and still
// one key per recording.
//
// A request that calls an AI provider twice records tokens twice. If both
// recordings took the bare request id, the second would be discarded as a
// duplicate of the first and the invoice would carry half the tokens --
// plausible, and wrong in the customer's favour every time. A retry of the
// whole request, on the other hand, must count once.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVMeters meters;
  final DVMeterDefinition tokens = DVMeterDefinition('ai_tokens', unit: 'token');
  final DVMeterDefinition calls = DVMeterDefinition('api_calls', unit: 'call');

  setUp(() {
    meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => DateTime.utc(2026, 9, 15, 12),
    );
  });

  tearDown(DVTenants.reset);

  Future<void> handle() => DVMeters.withIdempotencyKey('req-1', () async {
        await meters.record(tokens, 120);
        await meters.record(tokens, 80);
        await meters.record(calls, 1);
      });

  test('two recordings of one meter in one scope both count', () async {
    await handle();
    expect(await meters.usage(tokens, tenant: DVTenants.defaultTenant), 200);
    expect(await meters.usage(calls, tenant: DVTenants.defaultTenant), 1);
  });

  test('a retry of the whole scope still counts once', () async {
    await handle();
    await handle();
    await handle();
    expect(await meters.usage(tokens, tenant: DVTenants.defaultTenant), 200);
    expect(await meters.usage(calls, tenant: DVTenants.defaultTenant), 1);
  });

  test('a nested scope starts its own sequence', () async {
    await DVMeters.withIdempotencyKey('req-1', () async {
      await meters.record(tokens, 5);
      await DVMeters.withIdempotencyKey('job-9', () async {
        await meters.record(tokens, 7);
      });
      await meters.record(tokens, 11);
    });
    expect(await meters.usage(tokens, tenant: DVTenants.defaultTenant), 23);
  });

  test('an explicit key is used as given and does not advance the scope',
      () async {
    await DVMeters.withIdempotencyKey('req-1', () async {
      await meters.record(tokens, 3, idempotencyKey: 'explicit');
      await meters.record(tokens, 3, idempotencyKey: 'explicit');
      await meters.record(tokens, 4);
    });
    await DVMeters.withIdempotencyKey('req-1', () async {
      await meters.record(tokens, 4);
    });
    expect(await meters.usage(tokens, tenant: DVTenants.defaultTenant), 7);
  });

  test('the scope key is still readable', () {
    expect(DVMeters.currentIdempotencyKey, isNull);
    DVMeters.withIdempotencyKey('req-1', () {
      expect(DVMeters.currentIdempotencyKey, 'req-1');
    });
  });
}
