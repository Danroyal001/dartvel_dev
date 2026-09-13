// Usage metering: what is counted, whose it is, and what happens at a limit.
//
// Every test here is about a number that looks right and is not. A meter that
// counts per process instead of per tenant gives each customer a plausible
// total that is really everyone's. A retried request counted twice is a bill
// that is too high by exactly one retry. Two requests admitted past a hard
// limit at the same moment is a limit that holds only when traffic is quiet.
// A record on the boundary between two periods, counted in both, is an
// invoice that adds up to more than happened.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A period of [days] starting at [start], half-open.
DVMeterPeriod period(DateTime start, int days) =>
    DVMeterPeriod(start, start.add(Duration(days: days)));

void main() {
  late DateTime now;
  late DVMeters meters;

  DVMeterDefinition counter({
    DVLimit? limit,
    DVQuota? atLimit,
    List<double> notifyAt = const <double>[],
    Duration? grace,
  }) =>
      DVMeterDefinition(
        'api_calls',
        unit: 'call',
        kind: DVMeterKind.counter,
        limit: limit,
        atLimit: atLimit,
        notifyAt: notifyAt,
        grace: grace,
      );

  setUp(() {
    now = DateTime.utc(2026, 9, 15, 12);
    meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => now,
    );
  });

  tearDown(DVTenants.reset);

  group('recording', () {
    test('usage belongs to the tenant it was recorded under', () async {
      final DVMeterDefinition meter = counter();
      await const DVTenants().withTenant('acme', () async {
        await meters.record(meter, 2, idempotencyKey: 'a1');
      });
      await const DVTenants().withTenant('globex', () async {
        await meters.record(meter, 5, idempotencyKey: 'g1');
      });

      expect(await meters.usage(meter, tenant: 'acme'), 2);
      expect(await meters.usage(meter, tenant: 'globex'), 5,
          reason: 'a total counted per process would give both tenants 7');
    });

    test('a retried recording under the same key counts once', () async {
      final DVMeterDefinition meter = counter();
      final DVMeterOutcome first =
          await meters.record(meter, 1, idempotencyKey: 'req-1');
      final DVMeterOutcome retry =
          await meters.record(meter, 1, idempotencyKey: 'req-1');

      expect(first.recorded, isTrue);
      expect(retry.recorded, isFalse);
      expect(retry.codes, contains('DV-METER-002'));
      expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 1);
    });

    test('the same key in another tenant is not a duplicate', () async {
      final DVMeterDefinition meter = counter();
      await const DVTenants().withTenant('acme', () async {
        await meters.record(meter, 1, idempotencyKey: 'req-1');
      });
      final DVMeterOutcome other =
          await const DVTenants().withTenant('globex', () async {
        return meters.record(meter, 1, idempotencyKey: 'req-1');
      });

      expect(other.recorded, isTrue,
          reason: 'two tenants can each have a request with the same id');
      expect(await meters.usage(meter, tenant: 'globex'), 1);
    });

    test('a recording with no key to deduplicate by is refused', () async {
      // Generating one would make every retry look new, which is exactly the
      // double count the key exists to prevent -- and it would look fine.
      expect(
        () => meters.record(counter(), 1),
        throwsA(isA<StateError>().having(
            (StateError e) => e.message, 'message', contains('idempotency'))),
      );
    });

    test('a scope supplies the key, so a retried job counts once', () async {
      final DVMeterDefinition meter = counter();
      for (int attempt = 0; attempt < 3; attempt++) {
        await DVMeters.withIdempotencyKey('job-7', () async {
          await meters.record(meter, 4);
        });
      }
      expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 4);
    });

    test('an amount that is not a positive number is refused', () async {
      expect(() => meters.record(counter(), -1, idempotencyKey: 'k'),
          throwsArgumentError);
      expect(() => meters.record(counter(), double.nan, idempotencyKey: 'k'),
          throwsArgumentError);
    });
  });

  group('limits', () {
    test('a limit with no behaviour at the limit is refused', () {
      expect(
        () => counter(limit: const DVLimit.fixed(3)),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}', 'message',
            contains('DV-METER-005'))),
      );
    });

    test('block refuses the recording that would pass the limit', () async {
      final DVMeterDefinition meter =
          counter(limit: const DVLimit.fixed(3), atLimit: DVQuota.block);
      for (int i = 0; i < 3; i++) {
        final DVMeterOutcome ok =
            await meters.record(meter, 1, idempotencyKey: 'r$i');
        expect(ok.admitted, isTrue);
      }
      final DVMeterOutcome over =
          await meters.record(meter, 1, idempotencyKey: 'r3');

      expect(over.admitted, isFalse);
      expect(over.recorded, isFalse);
      expect(over.applied, DVQuota.block);
      expect(over.codes, contains('DV-METER-004'));
      expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 3);
    });

    test('concurrent recordings are not all admitted past a hard limit',
        () async {
      // Check-then-record without holding anything between the two lets every
      // request in the same instant read "2 of 3" and proceed.
      final DVMeterDefinition meter =
          counter(limit: const DVLimit.fixed(3), atLimit: DVQuota.block);
      final List<DVMeterOutcome> outcomes = await Future.wait(
        <Future<DVMeterOutcome>>[
          for (int i = 0; i < 10; i++)
            meters.record(meter, 1, idempotencyKey: 'c$i'),
        ],
      );

      expect(outcomes.where((DVMeterOutcome o) => o.admitted), hasLength(3));
      expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 3);
    });

    test('each tenant is held to its own limit', () async {
      final DVMeterDefinition meter =
          counter(limit: const DVLimit.fixed(1), atLimit: DVQuota.block);
      final DVMeterOutcome acme =
          await const DVTenants().withTenant('acme', () async {
        return meters.record(meter, 1, idempotencyKey: 'x');
      });
      final DVMeterOutcome globex =
          await const DVTenants().withTenant('globex', () async {
        return meters.record(meter, 1, idempotencyKey: 'y');
      });

      expect(acme.admitted, isTrue);
      expect(globex.admitted, isTrue,
          reason: "one tenant reaching a limit is not another tenant's limit");
    });

    test('throttle admits and records, and says the limit was reached',
        () async {
      final DVMeterDefinition meter =
          counter(limit: const DVLimit.fixed(1), atLimit: DVQuota.throttle);
      await meters.record(meter, 1, idempotencyKey: 'a');
      final DVMeterOutcome over =
          await meters.record(meter, 1, idempotencyKey: 'b');

      expect(over.admitted, isTrue);
      expect(over.recorded, isTrue);
      expect(over.applied, DVQuota.throttle);
      expect(over.codes, contains('DV-METER-004'));
    });

    test('allowAndBill records the overage and reports how much', () async {
      final DVMeterDefinition meter =
          counter(limit: const DVLimit.fixed(10), atLimit: DVQuota.allowAndBill);
      await meters.record(meter, 8, idempotencyKey: 'a');
      final DVMeterOutcome over =
          await meters.record(meter, 5, idempotencyKey: 'b');

      expect(over.admitted, isTrue);
      expect(over.recorded, isTrue);
      expect(over.applied, DVQuota.allowAndBill);
      expect(over.overage, 3);
      expect(over.total, 13);
    });

    test('reaching the limit exactly is still under it', () async {
      final DVMeterDefinition meter =
          counter(limit: const DVLimit.fixed(3), atLimit: DVQuota.block);
      final DVMeterOutcome exact =
          await meters.record(meter, 3, idempotencyKey: 'a');
      expect(exact.admitted, isTrue);
      expect(exact.applied, isNull);
    });

    test('an entitlement limit is read for the tenant it applies to',
        () async {
      final DVMeters withPlans = DVMeters(
        store: DVMemoryMeterStore(),
        clock: () => now,
        limits: (String tenant, DVMeterDefinition meter) =>
            tenant == 'acme' ? 2 : 100,
      );
      final DVMeterDefinition meter =
          counter(limit: DVLimit.entitlement, atLimit: DVQuota.block);

      final List<DVMeterOutcome> acme =
          await const DVTenants().withTenant('acme', () async {
        return <DVMeterOutcome>[
          for (int i = 0; i < 3; i++)
            await withPlans.record(meter, 1, idempotencyKey: 'a$i'),
        ];
      });
      expect(acme.map((DVMeterOutcome o) => o.admitted),
          <bool>[true, true, false]);
    });

    test('an entitlement limit with nothing to read it from is refused',
        () async {
      // Treating a missing plan lookup as "unlimited" is the quiet direction
      // to fail in: every tenant would be admitted forever and nothing would
      // look wrong until the invoice.
      final DVMeterDefinition meter =
          counter(limit: DVLimit.entitlement, atLimit: DVQuota.block);
      expect(() => meters.record(meter, 1, idempotencyKey: 'a'),
          throwsStateError);
    });
  });

  group('notification thresholds', () {
    test('a threshold is announced once, when it is crossed', () async {
      final List<DVMeterThreshold> seen = <DVMeterThreshold>[];
      final DVMeters notifying = DVMeters(
        store: DVMemoryMeterStore(),
        clock: () => now,
        onThreshold: seen.add,
      );
      final DVMeterDefinition meter = counter(
        limit: const DVLimit.fixed(10),
        atLimit: DVQuota.block,
        notifyAt: const <double>[0.8, 1.0],
      );

      await notifying.record(meter, 7, idempotencyKey: 'a');
      expect(seen, isEmpty);

      final DVMeterOutcome crossed =
          await notifying.record(meter, 1, idempotencyKey: 'b');
      expect(seen.map((DVMeterThreshold t) => t.fraction), <double>[0.8]);
      expect(crossed.codes, contains('DV-METER-003'));

      await notifying.record(meter, 1, idempotencyKey: 'c');
      expect(seen, hasLength(1), reason: 'still past 0.8; not crossed again');

      await notifying.record(meter, 1, idempotencyKey: 'd');
      expect(seen.map((DVMeterThreshold t) => t.fraction),
          <double>[0.8, 1.0]);
      expect(seen.last.tenant, DVTenants.defaultTenant);
      expect(seen.last.total, 10);
    });

    test('a refused recording announces nothing', () async {
      final List<DVMeterThreshold> seen = <DVMeterThreshold>[];
      final DVMeters notifying = DVMeters(
        store: DVMemoryMeterStore(),
        clock: () => now,
        onThreshold: seen.add,
      );
      final DVMeterDefinition meter = counter(
        limit: const DVLimit.fixed(10),
        atLimit: DVQuota.block,
        notifyAt: const <double>[0.5],
      );
      await notifying.record(meter, 20, idempotencyKey: 'a');
      expect(seen, isEmpty,
          reason: 'nothing was counted, so no threshold was reached');
    });
  });

  group('periods', () {
    test("usage is counted in the tenant's billing period", () async {
      final DVMeters billed = DVMeters(
        store: DVMemoryMeterStore(),
        clock: () => now,
        periods: (String tenant, DateTime at) {
          // Invoices cut on the 11th.
          final DateTime start = at.day >= 11
              ? DateTime.utc(at.year, at.month, 11)
              : DateTime.utc(at.year, at.month - 1, 11);
          return DVMeterPeriod(
              start, DateTime.utc(start.year, start.month + 1, 11));
        },
      );
      final DVMeterDefinition meter = counter(grace: const Duration(days: 30));

      await billed.record(meter, 1,
          idempotencyKey: 'before', at: DateTime.utc(2026, 9, 10, 23));
      await billed.record(meter, 1,
          idempotencyKey: 'after', at: DateTime.utc(2026, 9, 11, 1));

      expect(await billed.usage(meter, tenant: DVTenants.defaultTenant), 1,
          reason: 'the current period starts on the 11th, not the 1st');
    });

    test('with no billing period the calendar month is used, and said',
        () async {
      final DVMeterOutcome outcome =
          await meters.record(counter(), 1, idempotencyKey: 'a');
      expect(outcome.period.start, DateTime.utc(2026, 9));
      expect(outcome.period.end, DateTime.utc(2026, 10));
      expect(outcome.codes, contains('DV-METER-010'));
    });

    test('a record on the boundary belongs to the period that starts there',
        () async {
      final DVMeterDefinition meter = counter(grace: const Duration(days: 40));
      now = DateTime.utc(2026, 10, 2);
      final DVMeterOutcome edge = await meters.record(meter, 1,
          idempotencyKey: 'edge', at: DateTime.utc(2026, 10));

      expect(edge.period.start, DateTime.utc(2026, 10));
      expect(
        await meters.usage(meter,
            tenant: DVTenants.defaultTenant,
            period: DVMeterPeriod(DateTime.utc(2026, 9), DateTime.utc(2026, 10))),
        0,
        reason: 'a half-open period: the end instant is the next period',
      );
      expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 1);
    });

    test('a billing period that ends at an instant is not where it belongs',
        () async {
      // A resolver that answers the period ending at the boundary puts the
      // record in two periods' reach at once; half-open periods refuse it
      // rather than let an invoice count one call in both.
      final DVMeters wrong = DVMeters(
        store: DVMemoryMeterStore(),
        clock: () => DateTime.utc(2026, 10, 1),
        periods: (String tenant, DateTime at) =>
            DVMeterPeriod(DateTime.utc(2026, 9), DateTime.utc(2026, 10)),
      );
      expect(
        () => wrong.record(counter(), 1, idempotencyKey: 'edge'),
        throwsStateError,
      );
    });

    test('a late record inside the grace goes into the period it belongs to',
        () async {
      now = DateTime.utc(2026, 10, 1, 1);
      final DVMeterDefinition meter = counter(grace: const Duration(hours: 2));
      final DVMeterOutcome late = await meters.record(meter, 1,
          idempotencyKey: 'late', at: DateTime.utc(2026, 9, 30, 23));

      expect(late.period.start, DateTime.utc(2026, 9));
      expect(late.codes, contains('DV-METER-007'));
    });

    test('a late record after the grace counts in the open period', () async {
      now = DateTime.utc(2026, 10, 1, 3);
      final DVMeterDefinition meter = counter(grace: const Duration(hours: 2));
      final DVMeterOutcome late = await meters.record(meter, 1,
          idempotencyKey: 'late', at: DateTime.utc(2026, 9, 30, 23));

      expect(late.period.start, DateTime.utc(2026, 10));
      expect(late.codes, contains('DV-METER-008'));
      expect(late.recorded, isTrue, reason: 'usage that happened is not dropped');
    });

    test('a retry of a late record is still one record', () async {
      now = DateTime.utc(2026, 10, 1, 1);
      final DVMeterDefinition meter = counter(grace: const Duration(hours: 2));
      await meters.record(meter, 1,
          idempotencyKey: 'late', at: DateTime.utc(2026, 9, 30, 23));
      now = DateTime.utc(2026, 10, 1, 5); // the retry arrives after the grace
      final DVMeterOutcome retry = await meters.record(meter, 1,
          idempotencyKey: 'late', at: DateTime.utc(2026, 9, 30, 23));

      expect(retry.recorded, isFalse,
          reason: 'a retry moving to the open period would bill it twice');
    });
  });

  group('gauges', () {
    DVMeterDefinition gauge(DVGaugeBilling billing) => DVMeterDefinition(
          'stored_bytes',
          unit: 'GB-month',
          kind: DVMeterKind.gauge,
          gaugeBilling: billing,
        );

    test('a gauge is billed on its average, not its sum', () async {
      final DVMeterDefinition meter = gauge(DVGaugeBilling.average);
      for (final (String key, num value) sample in <(String, num)>[
        ('s1', 10),
        ('s2', 30),
        ('s3', 20),
      ]) {
        await meters.record(meter, sample.$2, idempotencyKey: sample.$1);
      }
      expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 20);
    });

    test('or on its peak, when that is what was declared', () async {
      final DVMeterDefinition meter = gauge(DVGaugeBilling.peak);
      await meters.record(meter, 10, idempotencyKey: 's1');
      await meters.record(meter, 30, idempotencyKey: 's2');
      await meters.record(meter, 20, idempotencyKey: 's3');
      expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 30);
    });

    test('a gauge with no samples reads zero', () async {
      expect(
          await meters.usage(gauge(DVGaugeBilling.average),
              tenant: DVTenants.defaultTenant),
          0);
    });
  });

  group('levels', () {
    test('a level limit is a query, and admitting against it writes nothing',
        () async {
      final DVMemoryMeterStore store = DVMemoryMeterStore();
      final DVMeters levels = DVMeters(store: store, clock: () => now);
      int seats = 4;
      final DVLevelLimit seatLimit = DVLevelLimit(
        'seats',
        count: (String tenant) => seats,
        limit: (String tenant) => 5,
        atLimit: DVQuota.block,
      );

      expect((await levels.admitLevel(seatLimit)).admitted, isTrue);
      seats = 5;
      final DVMeterOutcome full = await levels.admitLevel(seatLimit);
      expect(full.admitted, isFalse);
      expect(full.codes, contains('DV-METER-004'));
      expect(store.recordCount, 0,
          reason: 'a level has an authoritative answer; recording it would '
              'store a second counter beside the truth');
    });
  });

  group('the default recorder', () {
    test('a definition records through the configured meters', () async {
      DVMeters.configure(meters);
      addTearDown(DVMeters.unconfigure);
      final DVMeterDefinition meter = counter();

      await meter.record(3, idempotencyKey: 'a');
      expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 3);
    });

    test('recording with nothing configured says so', () async {
      DVMeters.unconfigure();
      expect(() => counter().record(1, idempotencyKey: 'a'), throwsStateError);
    });
  });
}
