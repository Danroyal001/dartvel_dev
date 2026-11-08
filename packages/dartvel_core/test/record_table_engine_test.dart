// DVRecordTable on a document engine: step 3 of Storage-Neutral Records.
//
// Every generated data model writes through DVRecordTable, so while it spoke
// SQL a project on a document database had no data models at all. Here it
// runs on DVMemoryRecordEngine, which refuses every SQL string as MongoDB
// would: reads, writes, the version check, soft delete and restore, the
// change log, revert, retention and a tenant's scope all have to go through
// the record operations or these tests fail naming the statement.
import 'package:dartvel_core/dartvel.dart';
// The record layer, which an application does not name and a test of it
// does.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

DVRecordTable _orders(
  DVDatabaseAdapter? database, {
  bool softDelete = true,
  DVRecordScope? scope,
  Map<String, String>? types,
}) =>
    DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'reference', 'quantity', 'card', 'dv_tenant'],
      sensitive: const <String>{'card'},
      unique: const <String>{'reference'},
      history: const DVHistory(keep: Duration(days: 30)),
      softDelete: softDelete,
      scope: scope,
      types: types,
      database: database,
    );

Map<String, Object?> _order(String id,
        {String reference = 'R-1', int quantity = 1, String card = '4242'}) =>
    <String, Object?>{
      'id': id,
      'reference': reference,
      'quantity': quantity,
      'card': card,
    };

void main() {
  group('a record table on a document engine', () {
    late DVMemoryRecordEngine engine;
    late DVRecordTable orders;

    setUp(() async {
      engine = DVMemoryRecordEngine();
      orders = _orders(engine);
      await orders.ensureSchema();
    });

    test('inserts, reads and lists without a SQL statement', () async {
      final DVWriteResult first = await orders.write(_order('o1'));
      expect(first.inserted, isTrue);
      expect(first.record.version, 1);
      final DVRecord? read = await orders.read('o1');
      expect(read!.values['reference'], 'R-1');
      expect(read.version, 1);
      expect(await orders.read('missing'), isNull);
      await orders.write(_order('o2', reference: 'R-2'));
      expect((await orders.all()).map((DVRecord r) => r.key),
          unorderedEquals(<String>['o1', 'o2']));
    });

    test('checks a write against the version it read', () async {
      final DVRecord first = (await orders.write(_order('o1'))).record;
      final DVRecord second =
          (await orders.write(_order('o1', quantity: 2), base: first)).record;
      expect(second.version, 2);
      expect(
        () => orders.write(_order('o1', quantity: 3), base: first),
        throwsA(isA<DVConflictError>()
            .having((DVConflictError e) => e.actualVersion, 'actual', 2)),
      );
      expect((await orders.read('o1'))!.values['quantity'], 2);
    });

    test('soft deletes, hides, and restores unless a live record took its '
        'unique value', () async {
      final DVRecord first = (await orders.write(_order('o1'))).record;
      await orders.delete('o1', base: first);
      expect(await orders.read('o1'), isNull);
      expect((await orders.read('o1', withDeleted: true))!.deletedAt, isNotNull);
      expect(await orders.all(), isEmpty);
      expect(await orders.all(withDeleted: true), hasLength(1));

      await orders.write(_order('o2'));
      expect(() => orders.restore('o1'),
          throwsA(isA<DVRestoreConflictError>()));
      final DVRecord o2 = (await orders.read('o2'))!;
      await orders.write(_order('o2', reference: 'R-2'), base: o2);
      final DVRecord restored = await orders.restore('o1');
      expect(restored.deletedAt, isNull);
      expect((await orders.read('o1'))!.values['reference'], 'R-1');
    });

    test('hard deletes at the version it read', () async {
      final DVRecordTable hard = _orders(engine, softDelete: false);
      await hard.write(_order('o1'));
      await hard.delete('o1');
      expect(await hard.read('o1', withDeleted: true), isNull);
      final List<DVHistoryEntry> log = await hard.history('o1');
      expect(log.last.deleted, isTrue);
    });

    test('keeps a change log that redacts sensitive fields, and reverts by '
        'adding to it', () async {
      final DVRecord first = (await orders.write(_order('o1'))).record;
      await orders.write(_order('o1', quantity: 5, card: '1111'), base: first);
      final List<DVHistoryEntry> log = await orders.history('o1');
      expect(log.map((DVHistoryEntry e) => e.version), <int>[1, 2]);
      expect(log.last.changes['quantity']!.to, 5);
      expect(log.last.changes['card']!.redacted, isTrue);

      final DVRevertResult reverted = await orders.revert('o1', to: log.first);
      expect(reverted.record.values['quantity'], 1);
      expect(reverted.unrestored, <String>{'card'});
      expect(await orders.history('o1'), hasLength(3));
    });

    test('prunes entries past the declared retention', () async {
      await orders.write(_order('o1'));
      expect(
        await orders.prune(now: DateTime.now().add(const Duration(days: 60))),
        1,
      );
      expect(await orders.history('o1'), isEmpty);
      expect(await orders.read('o1'), isNotNull, reason: 'records are kept');
    });

    test('a tenant scope keeps two tenants apart', () async {
      final DVRecordTable acme =
          _orders(engine, scope: const DVRecordScope('dv_tenant', 'acme'));
      final DVRecordTable globex =
          _orders(engine, scope: const DVRecordScope('dv_tenant', 'globex'));
      await acme.write(_order('o1'));
      await globex.write(_order('o1', quantity: 9));
      expect((await acme.read('o1'))!.values['quantity'], 1);
      expect((await globex.read('o1'))!.values['quantity'], 9);
      expect(await acme.all(), hasLength(1));
      expect(await acme.history('o1'), hasLength(1));
      await acme.delete('o1');
      expect(await acme.read('o1'), isNull);
      expect(await globex.read('o1'), isNotNull);
    });

    test('ensures its collections through the engine', () async {
      final DVMemoryRecordEngine fresh = DVMemoryRecordEngine();
      final DVRecordTable typed = _orders(
        fresh,
        types: const <String, String>{
          'id': 'TEXT',
          'reference': 'TEXT',
          'quantity': 'INTEGER',
          'card': 'TEXT',
          'dv_tenant': 'TEXT',
        },
      );
      await typed.ensureSchema();
      expect(await fresh.find('orders'), isEmpty);
      expect(await fresh.find('orders__history'), isEmpty);
    });
  });

  test('a record table with no database given uses DV.Database\'s engine',
      () async {
    final DVMemoryRecordEngine engine = DVMemoryRecordEngine();
    const DVDatabase().configure(engine);
    addTearDown(() => const DVDatabase().unconfigure());
    final DVRecordTable orders = _orders(null);
    await orders.ensureSchema();
    await orders.write(_order('o1'));
    expect((await engine.find('orders')).single['reference'], 'R-1');
    expect(await engine.find('orders__history'), hasLength(1));
  });
}
