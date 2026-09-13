// Meters stored in the application's own database.
//
// The in-memory store proves the arithmetic. This proves the part that makes
// a meter a meter rather than a variable: two instances of the application
// pointed at one database see one total per tenant, and a retry that lands on
// the other instance is still recognised as a retry.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 9, 15, 12);
  final DVMeterDefinition meter =
      DVMeterDefinition('api_calls', unit: 'call', kind: DVMeterKind.counter);

  for (final (String name, DVDatabaseAdapter Function() open)
      in <(String, DVDatabaseAdapter Function())>[
    ('in-memory', MemoryDVDatabaseAdapter.new),
    ('sqlite', SqliteDVDatabaseAdapter.memory),
  ]) {
    group('on the $name adapter', () {
      setUp(() => const DVDatabase().configure(open()));

      tearDown(() {
        const DVDatabase().unconfigure();
        DVTenants.reset();
      });

      test('two instances on one database share each tenant\'s total',
          () async {
        final DVMeters first =
            DVMeters(store: DVDatabaseMeterStore(), clock: () => now);
        final DVMeters second =
            DVMeters(store: DVDatabaseMeterStore(), clock: () => now);

        await const DVTenants().withTenant('acme', () async {
          await first.record(meter, 2, idempotencyKey: 'a');
          await second.record(meter, 3, idempotencyKey: 'b');
        });
        await const DVTenants().withTenant('globex', () async {
          await second.record(meter, 7, idempotencyKey: 'c');
        });

        expect(await first.usage(meter, tenant: 'acme'), 5);
        expect(await first.usage(meter, tenant: 'globex'), 7);
      });

      test('a retry that lands on the other instance counts once', () async {
        final DVMeters first =
            DVMeters(store: DVDatabaseMeterStore(), clock: () => now);
        final DVMeters second =
            DVMeters(store: DVDatabaseMeterStore(), clock: () => now);

        await first.record(meter, 1, idempotencyKey: 'req-1');
        final DVMeterOutcome retry =
            await second.record(meter, 1, idempotencyKey: 'req-1');

        expect(retry.recorded, isFalse);
        expect(await first.usage(meter, tenant: DVTenants.defaultTenant), 1);
      });

      test('records survive in the period they were placed in', () async {
        final DVMeters meters =
            DVMeters(store: DVDatabaseMeterStore(), clock: () => now);
        await meters.record(meter, 4, idempotencyKey: 'a');

        expect(
          await meters.usage(meter,
              tenant: DVTenants.defaultTenant,
              period:
                  DVMeterPeriod(DateTime.utc(2026, 8), DateTime.utc(2026, 9))),
          0,
        );
        expect(await meters.usage(meter, tenant: DVTenants.defaultTenant), 4);
      });
    });
  }
}
