// A raw query an application writes itself reads every tenant's rows.
//
// Generated model queries carry the predicate. Everything else does not: a
// report, a dashboard count, a join the generator cannot express, a query
// somebody wrote before the model was scoped. Each returns rows, the numbers
// look plausible, and one tenant is being shown another tenant's data.
//
// The check is deliberately coarse. It knows which tables are tenant-scoped
// because the generator registers them, and it looks for the column in the
// statement. A false positive is a refusal somebody reads and fixes; a false
// negative leaves today's behaviour exactly as it is. The one thing it must
// not do is guess quietly in the direction of allowing.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    DVTenants.reset();
    const DVDatabase()
      ..unconfigure()
      ..configure(MemoryDVDatabaseAdapter());
    dvRegisterTenantScopedTables(const <String>{'orders'});
  });

  tearDown(() {
    DVTenants.reset();
    const DVDatabase().unconfigure();
    dvResetTenantScopedTables();
  });

  group('a statement naming a scoped table', () {
    test('without the tenant column is refused', () async {
      await expectLater(
        const DVDatabase().query('SELECT * FROM orders'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('orders'), contains('acrossTenants')),
          ),
        ),
      );
    });

    test('with it is allowed', () async {
      await expectLater(
        const DVDatabase()
            .query('SELECT * FROM orders WHERE dv_tenant = ?', <Object?>['a']),
        completes,
      );
    });

    test('a write is checked too', () async {
      // A write without the column is the worse half: it puts a row in the
      // table belonging to nobody, which every tenant then cannot see.
      await expectLater(
        const DVDatabase().execute("INSERT INTO orders (id) VALUES ('1')"),
        throwsStateError,
      );
    });

    test('a table nobody scoped is not checked', () async {
      await expectLater(
        const DVDatabase().query('SELECT * FROM currencies'),
        completes,
      );
    });

    test('a name that merely contains a scoped one is not that table', () async {
      // "orders" inside "workorders" is a different table, and refusing it
      // would teach people to reach for the escape hatch out of habit.
      await expectLater(
        const DVDatabase().query('SELECT * FROM workorders'),
        completes,
      );
    });
  });

  group('crossing tenants is possible and has to be written down', () {
    test('inside acrossTenants the same statement runs', () async {
      // An operator report, a migration, a support tool. The point is not
      // that it is hard; it is that it is visible in a diff and greppable.
      await expectLater(
        const DVDatabase()
            .acrossTenants(() => const DVDatabase().query('SELECT * FROM orders')),
        completes,
      );
    });

    test('the scope does not leak past the callback', () async {
      await const DVDatabase()
          .acrossTenants(() => const DVDatabase().query('SELECT * FROM orders'));

      await expectLater(
        const DVDatabase().query('SELECT * FROM orders'),
        throwsStateError,
      );
    });
  });

  group('the other isolation strategies', () {
    test('a schema per tenant does not need the column', () async {
      // The separation there is the schema, and a predicate on a column that
      // does not exist would fail every query.
      const DVTenants().configure(
        isolation: DVTenantIsolation.schemaPerTenant,
      );

      await expectLater(
        const DVDatabase().query('SELECT * FROM dartvel_acme.orders'),
        completes,
      );
    });
  });
}
