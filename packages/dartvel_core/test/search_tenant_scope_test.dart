// Search over a tenant-scoped table asks only for that tenant's rows.
//
// The Postgres provider builds its own SQL and hands it to the adapter
// directly, so it went past DV.Database and past the check that refuses a
// statement naming a scoped table without the tenant column. Nothing else
// added a predicate: the tenant filter the spec calls automatic was a hook
// called `filter` that every application had to write for itself, and an
// application that did not write it got a search box returning other
// tenants' rows -- with their titles and descriptions in the results,
// because that is what search results are.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _RecordingAdapter implements DVDatabaseAdapter {
  final List<({String sql, List<Object?> params})> statements =
      <({String sql, List<Object?> params})>[];

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    statements.add((sql: sql, params: params ?? const <Object?>[]));
    // A count for the first statement, rows for the second.
    return statements.length == 1
        ? <Map<String, Object?>>[
            <String, Object?>{'total': 0},
          ]
        : <Map<String, Object?>>[];
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    statements.add((sql: sql, params: params ?? const <Object?>[]));
    return 0;
  }
}

DVPostgresSearchProvider<Map<String, Object?>, Object> _provider(
  DVDatabaseAdapter database, {
  String table = 'orders',
}) =>
    DVPostgresSearchProvider<Map<String, Object?>, Object>(
      database: database,
      table: table,
      columns: const <String>['title'],
      fromRow: (Map<String, Object?> row) => row,
    );

void main() {
  tearDown(DVTenants.reset);

  test('a scoped table is searched for the current tenant only', () async {
    dvRegisterTenantScopedTables(<String>{'orders'});
    final _RecordingAdapter database = _RecordingAdapter();

    await const DVTenants().withTenant(
      'acme',
      () => _provider(database).query('lamp'),
    );

    expect(database.statements, isNotEmpty);
    for (final ({String sql, List<Object?> params}) statement
        in database.statements) {
      expect(statement.sql, contains('dv_tenant = ?'));
      expect(statement.params, contains('acme'));
    }
  });

  test('a table nobody scoped is searched as it always was', () async {
    // A currency list is deliberately shared. A predicate on a column that is
    // not there fails every search over it.
    final _RecordingAdapter database = _RecordingAdapter();

    await _provider(database, table: 'currencies').query('euro');

    for (final ({String sql, List<Object?> params}) statement
        in database.statements) {
      expect(statement.sql, isNot(contains('dv_tenant')));
    }
  });

  test('under a schema per tenant the name is qualified, not the column',
      () async {
    // There the separation is the schema, and a predicate on a column no
    // table has would fail every search.
    dvRegisterTenantScopedTables(<String>{'orders'});
    const DVTenants().configure(isolation: DVTenantIsolation.schemaPerTenant);
    final _RecordingAdapter database = _RecordingAdapter();

    await const DVTenants().withTenant(
      'acme',
      () => _provider(database).query('lamp'),
    );

    for (final ({String sql, List<Object?> params}) statement
        in database.statements) {
      expect(statement.sql, contains('dartvel_acme.orders'));
      expect(statement.sql, isNot(contains('dv_tenant')));
    }
  });

  test('the index is created on the tenant table too', () async {
    // An index built on the unqualified name under a schema per tenant is an
    // index on somebody else's table, or on nothing.
    dvRegisterTenantScopedTables(<String>{'orders'});
    const DVTenants().configure(isolation: DVTenantIsolation.schemaPerTenant);
    final _RecordingAdapter database = _RecordingAdapter();

    await const DVTenants()
        .withTenant('acme', () => _provider(database).createIndex());

    expect(database.statements.single.sql, contains('dartvel_acme.orders'));
  });
}
