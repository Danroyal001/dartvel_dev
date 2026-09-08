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

/// Records what reached the adapter.
///
/// Not MemoryDVDatabaseAdapter: that one understands `select 1` and
/// `select * from <table>` and refuses anything with a WHERE clause, so a
/// test using it could not tell a statement the check allowed from one the
/// adapter could not parse.
class _Recorder implements DVDatabaseAdapter {
  final List<String> statements = <String>[];

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    statements.add(sql);
    return const <Map<String, Object?>>[];
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    statements.add(sql);
    return 0;
  }
}

late _Recorder adapter;

void main() {
  setUp(() {
    DVTenants.reset();
    adapter = _Recorder();
    const DVDatabase()
      ..unconfigure()
      ..configure(adapter);
    dvRegisterTenantScopedTables(const <String>{'orders'});
  });

  tearDown(() {
    DVTenants.reset();
    const DVDatabase().unconfigure();
  });

  group('a statement naming a scoped table', () {
    // The refusal is synchronous -- it happens while the call is being made,
    // before there is a Future to await -- which is what a caller wants: the
    // statement never reaches the adapter.
    test('without the tenant column is refused', () {
      expect(
        () => const DVDatabase().query('SELECT * FROM orders'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('orders'), contains('acrossTenants')),
          ),
        ),
      );
      expect(adapter.statements, isEmpty);
    });

    test('with it is allowed', () async {
      await const DVDatabase()
          .query('SELECT * FROM orders WHERE dv_tenant = ?', <Object?>['a']);

      expect(adapter.statements, hasLength(1));
    });

    test('a write is checked too', () {
      // The worse half: a write without the column puts a row in the table
      // belonging to nobody, which every tenant then cannot see.
      expect(
        () => const DVDatabase().execute("INSERT INTO orders (id) VALUES ('1')"),
        throwsStateError,
      );
      expect(adapter.statements, isEmpty);
    });

    test('a table nobody scoped is not checked', () async {
      await const DVDatabase().query('SELECT * FROM currencies');

      expect(adapter.statements, hasLength(1));
    });

    test('a name that merely contains a scoped one is not that table', () async {
      // "orders" inside "workorders" is a different table, and refusing it
      // would teach people to reach for the escape hatch out of habit.
      await const DVDatabase().query('SELECT * FROM workorders');

      expect(adapter.statements, hasLength(1));
    });
  });

  group('crossing tenants is possible and has to be written down', () {
    test('inside acrossTenants the same statement runs', () async {
      // An operator report, a migration, a support tool. The point is not
      // that it is hard; it is that it is visible in a diff and greppable.
      await const DVDatabase()
          .acrossTenants(() => const DVDatabase().query('SELECT * FROM orders'));

      expect(adapter.statements, hasLength(1));
    });

    test('the scope does not leak past the callback', () async {
      await const DVDatabase()
          .acrossTenants(() => const DVDatabase().query('SELECT * FROM orders'));

      expect(
        () => const DVDatabase().query('SELECT * FROM orders'),
        throwsStateError,
      );
      expect(adapter.statements, hasLength(1));
    });
  });

  group('the other isolation strategies', () {
    test('a schema per tenant does not need the column', () async {
      // The separation there is the schema, and a predicate on a column that
      // does not exist would fail every query.
      const DVTenants().configure(
        isolation: DVTenantIsolation.schemaPerTenant,
      );

      await const DVDatabase().query('SELECT * FROM dartvel_acme.orders');

      expect(adapter.statements, hasLength(1));
    });
  });
}
