// Throttle: past the limit the call proceeds, and proceeds slowly.
//
// A throttle that only reports is allowAndBill without the bill: the
// customer's integration runs at full speed past its limit, nobody notices,
// and the one signal the behaviour exists to send -- "you are over, and it is
// costing you time" -- is never felt by the caller it was meant for.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late List<Duration> slept;
  late DVMeters meters;

  DVMeterDefinition throttled() => DVMeterDefinition(
        'api_calls',
        unit: 'call',
        limit: const DVLimit.fixed(1),
        atLimit: DVQuota.throttle,
      );

  setUp(() {
    slept = <Duration>[];
    meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => DateTime.utc(2026, 9, 15, 12),
      throttleDelay: const Duration(milliseconds: 750),
      sleep: (Duration delay) async => slept.add(delay),
    );
  });

  tearDown(DVTenants.reset);

  test('a recording past the limit is delayed by the throttle delay', () async {
    final DVMeterDefinition meter = throttled();
    final DVMeterOutcome under =
        await meters.record(meter, 1, idempotencyKey: 'a');
    expect(under.delayed, Duration.zero);
    expect(slept, isEmpty, reason: 'under the limit nothing waits');

    final DVMeterOutcome over =
        await meters.record(meter, 1, idempotencyKey: 'b');
    expect(over.applied, DVQuota.throttle);
    expect(over.admitted, isTrue);
    expect(over.delayed, const Duration(milliseconds: 750));
    expect(slept, <Duration>[const Duration(milliseconds: 750)]);
  });

  test('the delay does not hold up other tenants', () async {
    // The wait is the caller's, not the meter's queue: a tenant over its
    // limit must not make another tenant's recording wait behind it.
    final DVMeterDefinition meter = throttled();
    await const DVTenants().withTenant('acme', () async {
      await meters.record(meter, 1, idempotencyKey: 'a');
    });
    final List<String> order = <String>[];
    final DVMeters slow = DVMeters(
      store: meters.store,
      clock: () => DateTime.utc(2026, 9, 15, 12),
      throttleDelay: const Duration(milliseconds: 200),
    );
    await Future.wait(<Future<void>>[
      const DVTenants().withTenant('acme', () async {
        await slow.record(meter, 1, idempotencyKey: 'b');
        order.add('acme');
      }),
      const DVTenants().withTenant('globex', () async {
        await slow.record(meter, 1, idempotencyKey: 'g');
        order.add('globex');
      }),
    ]);
    expect(order, <String>['globex', 'acme']);
  });

  test('block and allowAndBill do not wait', () async {
    for (final DVQuota behaviour in <DVQuota>[
      DVQuota.block,
      DVQuota.allowAndBill,
    ]) {
      final DVMeterDefinition meter = DVMeterDefinition(
        'm_${behaviour.name}',
        unit: 'call',
        limit: const DVLimit.fixed(1),
        atLimit: behaviour,
      );
      await meters.record(meter, 1, idempotencyKey: 'a');
      final DVMeterOutcome over =
          await meters.record(meter, 1, idempotencyKey: 'b');
      expect(over.delayed, Duration.zero, reason: behaviour.name);
    }
    expect(slept, isEmpty);
  });

  test('a duplicate of a throttled recording does not wait again', () async {
    final DVMeterDefinition meter = throttled();
    await meters.record(meter, 1, idempotencyKey: 'a');
    await meters.record(meter, 1, idempotencyKey: 'b');
    final DVMeterOutcome retry =
        await meters.record(meter, 1, idempotencyKey: 'b');
    expect(retry.recorded, isFalse);
    expect(retry.delayed, Duration.zero);
    expect(slept, hasLength(1));
  });

  test('a negative throttle delay is refused', () {
    expect(
      () => DVMeters(
          store: DVMemoryMeterStore(),
          throttleDelay: const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
  });
}
