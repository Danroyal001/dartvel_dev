// Schema-per-tenant and database-per-tenant, which resolved a tenant and then
// did nothing different with it.
//
// The specification lists three isolation strategies. Two of them were an
// enum value and a name-building function -- DVTenants.qualifierFor, correct,
// unit tested, and called by nothing anywhere in the repository. Configuring
// either one produced exactly the queries sharedDatabase produces, against
// exactly the same database, which is every tenant reading every tenant's
// rows on the two strategies chosen specifically to prevent that.
//
// The failure mode is the one worth naming: it looks like it works. Every
// query returns rows, the application behaves, and the separation somebody
// selected is simply not there.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    DVTenants.reset();
    const DVDatabase().unconfigure();
  });

  tearDown(() {
    DVTenants.reset();
    const DVDatabase().unconfigure();
  });

  group('what a query names', () {
    test('shared database leaves the table alone', () {
      // The column is the separation here, and a qualified name would be a
      // schema nobody created.
      expect(dvTenantTable('orders'), 'orders');
    });

    test('a schema per tenant qualifies it', () {
      const DVTenants().configure(
        isolation: DVTenantIsolation.schemaPerTenant,
      );
      const DVTenants().currentTenant = 'acme';

      expect(dvTenantTable('orders'), 'dartvel_acme.orders');
    });

    test('a database per tenant does not, because the connection differs', () {
      // Qualifying the name as well would look for a schema inside the
      // tenant's own database, which is not where its tables are.
      const DVTenants().configure(
        isolation: DVTenantIsolation.databasePerTenant,
      );
      const DVTenants().currentTenant = 'acme';

      expect(dvTenantTable('orders'), 'orders');
    });

    test('the tenant is followed, not read once', () {
      // A scope wins over the process-wide tenant, and the table name has to
      // follow it: two requests are in flight at once and each is inside its
      // own scope.
      const DVTenants().configure(
        isolation: DVTenantIsolation.schemaPerTenant,
      );
      const DVTenants().currentTenant = 'acme';

      final String inside = const DVTenants().withTenant<String>(
        'globex',
        () => dvTenantTable('orders'),
      );

      expect(inside, 'dartvel_globex.orders');
      expect(dvTenantTable('orders'), 'dartvel_acme.orders');
    });
  });

  group('which database a query reaches', () {
    test('a database per tenant with none configured is refused', () async {
      // Falling back to the one adapter would give every tenant the same
      // database, which is the leak this mode exists to prevent, and every
      // query would still return rows.
      const DVTenants().configure(
        isolation: DVTenantIsolation.databasePerTenant,
      );
      const DVDatabase().configure(MemoryDVDatabaseAdapter());

      expect(
        () => const DVDatabase().query('SELECT 1'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('databasePerTenant'),
              contains('configureTenantDatabases'),
            ),
          ),
        ),
      );
    });

    test('each tenant reaches its own', () async {
      final Map<String, MemoryDVDatabaseAdapter> opened =
          <String, MemoryDVDatabaseAdapter>{};
      const DVTenants().configure(
        isolation: DVTenantIsolation.databasePerTenant,
      );
      const DVDatabase().configureTenantDatabases((String tenant) {
        return opened.putIfAbsent(tenant, MemoryDVDatabaseAdapter.new);
      });

      const DVTenants().currentTenant = 'acme';
      expect(identical(const DVDatabase().adapter, opened['acme']), isTrue);

      const DVTenants().currentTenant = 'globex';
      expect(identical(const DVDatabase().adapter, opened['globex']), isTrue);
      expect(identical(opened['acme'], opened['globex']), isFalse);
    });

    test('a tenant is opened once, not per query', () async {
      // A connection per query is a connection pool nobody wrote, and on
      // SQLite it is a second write lock over the same file.
      int opens = 0;
      const DVTenants().configure(
        isolation: DVTenantIsolation.databasePerTenant,
      );
      const DVDatabase().configureTenantDatabases((String tenant) {
        opens++;
        return MemoryDVDatabaseAdapter();
      });

      const DVTenants().currentTenant = 'acme';
      const DVDatabase().adapter;
      const DVDatabase().adapter;

      expect(opens, 1);
    });

    test('the other two strategies use the configured adapter', () {
      final MemoryDVDatabaseAdapter one = MemoryDVDatabaseAdapter();
      const DVDatabase().configure(one);

      for (final DVTenantIsolation isolation in <DVTenantIsolation>[
        DVTenantIsolation.sharedDatabase,
        DVTenantIsolation.schemaPerTenant,
      ]) {
        const DVTenants().configure(isolation: isolation);
        expect(identical(const DVDatabase().adapter, one), isTrue);
      }
    });
  });
}
