// Record history and optimistic concurrency, against the adapters Dartvel runs
// on without a network: the in-memory adapter and SQLite. Postgres and MySQL
// take the same statements and run in CI.
//
// The failures worth the effort here are the silent ones. A lost update looks
// like success to both writers. A sensitive value copied into a change log is
// found by nobody until somebody reads the change log. A revert that rewrites
// the past rather than adding to it loses exactly the entries an audit needs.
// Each has a test below that fails if the behaviour quietly regresses.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Wraps an adapter and refuses writes to one table, so a history insert can
/// be made to fail mid-write the way a full disk or a dropped connection
/// would.
class _FailingHistory implements DVDatabaseAdapter {
  _FailingHistory(this.inner);

  final DVDatabaseAdapter inner;
  bool failHistory = false;

  @override
  Future<List<Map<String, Object?>>> query(String sql,
          [List<Object?>? params]) =>
      inner.query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) {
    if (failHistory && sql.toLowerCase().contains('insert into orders__history')) {
      throw StateError('disk full');
    }
    return inner.execute(sql, params);
  }
}

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

DVRecordTable _orders(
  DVDatabaseAdapter database, {
  bool versioned = true,
  bool softDelete = true,
  DVHistory? history = const DVHistory(keep: Duration(days: 365)),
}) =>
    DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'reference', 'quantity', 'card'],
      sensitive: const <String>{'card'},
      unique: const <String>{'reference'},
      history: history,
      versioned: versioned,
      softDelete: softDelete,
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
  group('declared column types', () {
    // PostgreSQL and MySQL refuse a column with no type, so a table the
    // framework makes for itself says what each column holds.
    DVRecordTable typed(DVDatabaseAdapter database,
            {Map<String, String>? types}) =>
        DVRecordTable(
          table: 'orders',
          key: 'id',
          columns: const <String>['id', 'quantity', 'note'],
          history: const DVHistory(),
          types: types ??
              const <String, String>{
                'id': 'TEXT',
                'quantity': 'INTEGER',
                'note': 'TEXT',
              },
          database: database,
        );

    test('are written into the table and its history', () async {
      final List<String> statements = <String>[];
      final _RacingAdapter recording =
          _RacingAdapter(SqliteDVDatabaseAdapter.memory())
            ..before = (String sql) async => statements.add(sql);
      await typed(recording).ensureSchema();
      expect(statements, <String>[
        'CREATE TABLE IF NOT EXISTS orders (id TEXT, quantity INTEGER, '
            'note TEXT, _dv_version INTEGER NOT NULL DEFAULT 1, '
            '_dv_deleted_at TEXT)',
        'CREATE TABLE IF NOT EXISTS orders__history (entry_id TEXT, '
            'record_key TEXT, record_version INTEGER, actor TEXT, tenant TEXT, '
            'transaction_id TEXT, occurred_at TEXT, changes TEXT, '
            'deleted INTEGER, restored INTEGER)',
      ]);
    });

    test('hand back on SQLite exactly what was written', () async {
      final DVRecordTable orders = typed(SqliteDVDatabaseAdapter.memory());
      await orders.ensureSchema();
      final DVRecord first = (await orders.write(
        <String, Object?>{'id': 'o1', 'quantity': 2, 'note': '10'},
      )).record;
      final DVRecord second = (await orders.write(
        <String, Object?>{'id': 'o1', 'quantity': 2, 'note': '10'},
        base: first,
      )).record;
      expect(second.version, 1, reason: 'nothing changed');
      expect((await orders.read('o1'))!.values,
          <String, Object?>{'id': 'o1', 'quantity': 2, 'note': '10'});
      expect(await orders.history('o1'), hasLength(1));
    });

    test('must name every column, and only columns', () {
      final MemoryDVDatabaseAdapter memory = MemoryDVDatabaseAdapter();
      expect(
        () => typed(memory,
            types: const <String, String>{'id': 'TEXT', 'quantity': 'INTEGER'}),
        throwsArgumentError,
      );
      expect(
        () => typed(memory, types: const <String, String>{
          'id': 'TEXT',
          'quantity': 'INTEGER',
          'note': 'TEXT',
          'extra': 'TEXT',
        }),
        throwsArgumentError,
      );
    });

    test('are refused when they are not a type', () {
      expect(
        () => typed(MemoryDVDatabaseAdapter(), types: const <String, String>{
          'id': 'TEXT',
          'quantity': 'INTEGER); DROP TABLE users; --',
          'note': 'TEXT',
        }),
        throwsArgumentError,
      );
    });
  });

  for (final _Adapter adapter in _adapters) {
    group('on ${adapter.$1}', () {
      late DVDatabaseAdapter database;
      late DVRecordTable orders;

      setUp(() async {
        database = adapter.$2();
        orders = _orders(database);
        await orders.ensureSchema();
      });

      group('versions', () {
        test('a new record starts at version one', () async {
          final DVWriteResult result =
              await orders.write(_order('o1'), actor: 'ann');
          expect(result.record.version, 1);
          expect((await orders.read('o1'))!.version, 1);
        });

        test('each write moves the version on', () async {
          final DVRecord first = (await orders.write(_order('o1'))).record;
          final DVRecord second = (await orders.write(
            _order('o1', quantity: 2),
            base: first,
          ))
              .record;
          expect(second.version, 2);
          expect(second.values['quantity'], 2);
        });

        test('a stale write is refused and the row keeps the later write',
            () async {
          // Two people read version one. Ann saves first. Bob's save carries
          // the version he read, which is no longer the row's.
          final DVRecord read = (await orders.write(_order('o1'))).record;
          await orders.write(_order('o1', quantity: 2), base: read);

          late DVConflictError conflict;
          try {
            await orders.write(_order('o1', quantity: 3), base: read);
            fail('a stale write succeeded -- that is the lost update');
          } on DVConflictError catch (error) {
            conflict = error;
          }

          expect(conflict.code, 'DV-HISTORY-001');
          expect(conflict.mine['quantity'], 3, reason: 'what this session wrote');
          expect(conflict.theirs['quantity'], 2, reason: 'what the row holds');
          expect(conflict.base!['quantity'], 1, reason: 'what this session read');
          expect((await orders.read('o1'))!.values['quantity'], 2,
              reason: 'the refused write must not have landed');
        });

        test('a write to an existing row with no version read is refused',
            () async {
          // A writer that never read the row cannot know what it is
          // overwriting, which is the lost update with extra steps.
          await orders.write(_order('o1'));
          expect(
            () => orders.write(_order('o1', quantity: 9)),
            throwsA(isA<DVConflictError>()
                .having((DVConflictError e) => e.base, 'base', isNull)),
          );
          expect((await orders.read('o1'))!.values['quantity'], 1);
        });

        test('serverWins discards the local change and reports it', () async {
          final DVRecord read = (await orders.write(_order('o1'))).record;
          await orders.write(_order('o1', quantity: 2), base: read);

          final DVWriteResult result = await orders.write(
            _order('o1', quantity: 3),
            base: read,
            onConflict: DVConflict.serverWins,
          );
          expect(result.discarded, isTrue);
          expect(result.conflict, isNotNull);
          expect(result.record.values['quantity'], 2);
          expect((await orders.read('o1'))!.values['quantity'], 2);
        });

        test('lastWriteWins writes the whole model over the row', () async {
          final DVRecord read = (await orders.write(_order('o1'))).record;
          await orders.write(_order('o1', quantity: 2, reference: 'R-2'),
              base: read);

          final DVWriteResult result = await orders.write(
            _order('o1', quantity: 3),
            base: read,
            onConflict: DVConflict.lastWriteWins,
          );
          expect(result.discarded, isFalse);
          expect(result.record.values['quantity'], 3);
          expect(result.record.values['reference'], 'R-1',
              reason: 'whole model: the other writer\'s reference is replaced');
          expect(result.record.version, 3);
        });

        test('fieldMerge keeps both writers\' changes to different fields',
            () async {
          final DVRecord read = (await orders.write(_order('o1'))).record;
          // Ann changes the reference; Bob, from the same read, the quantity.
          await orders.write(_order('o1', reference: 'R-2'), base: read);
          final DVWriteResult result = await orders.write(
            _order('o1', quantity: 5),
            base: read,
            onConflict: DVConflict.fieldMerge,
          );
          expect(result.record.values['reference'], 'R-2');
          expect(result.record.values['quantity'], 5);
        });

        test('a resolver decides from both versions', () async {
          final DVRecord read = (await orders.write(_order('o1'))).record;
          await orders.write(_order('o1', quantity: 2), base: read);
          final DVWriteResult result = await orders.write(
            _order('o1', quantity: 3),
            base: read,
            onConflict: DVConflict.resolver((DVConflictError c) =>
                <String, Object?>{
                  ...c.theirs,
                  'quantity': (c.theirs['quantity']! as int) +
                      (c.mine['quantity']! as int),
                }),
          );
          expect(result.record.values['quantity'], 5);
        });

        test('versioned: false lets the later write win, as declared',
            () async {
          final DVRecordTable log = _orders(database, versioned: false);
          await log.ensureSchema();
          final DVRecord read = (await log.write(_order('o1'))).record;
          await log.write(_order('o1', quantity: 2), base: read);
          await log.write(_order('o1', quantity: 3), base: read);
          expect((await log.read('o1'))!.values['quantity'], 3);
        });

        test('ask is not an offline strategy; the others are', () {
          expect(DVConflict.ask.allowedOffline, isFalse);
          expect(DVConflict.lastWriteWins.allowedOffline, isTrue);
          expect(DVConflict.serverWins.allowedOffline, isTrue);
          expect(DVConflict.fieldMerge.allowedOffline, isTrue);
        });
      });

      group('history', () {
        test('records who changed which fields, oldest first', () async {
          final DVRecord read =
              (await orders.write(_order('o1'), actor: 'ann')).record;
          await orders.write(_order('o1', quantity: 2),
              base: read, actor: 'bob', tenant: 'acme');

          final List<DVHistoryEntry> entries = await orders.history('o1');
          expect(entries, hasLength(2));
          expect(entries[0].actor, 'ann');
          expect(entries[0].version, 1);
          expect(entries[1].actor, 'bob');
          expect(entries[1].tenant, 'acme');
          expect(entries[1].version, 2);
          expect(entries[1].changes.keys, <String>['quantity'],
              reason: 'only what changed');
          expect(entries[1].changes['quantity']!.from, 1);
          expect(entries[1].changes['quantity']!.to, 2);
        });

        test('a sensitive field is recorded as changed, never as a value',
            () async {
          final DVRecord read =
              (await orders.write(_order('o1', card: '4242'))).record;
          await orders.write(_order('o1', card: '5555'), base: read);

          final List<DVHistoryEntry> entries = await orders.history('o1');
          final DVFieldChange change = entries[1].changes['card']!;
          expect(change.redacted, isTrue);
          expect(change.from, isNull);
          expect(change.to, isNull);

          // Not just absent from the object -- absent from the table, which is
          // where somebody with database access would look.
          final List<Map<String, Object?>> raw =
              await database.query('SELECT * FROM orders__history');
          final String stored = jsonEncode(raw);
          expect(stored, isNot(contains('4242')));
          expect(stored, isNot(contains('5555')));
        });

        test('an entry carries the transaction it was written in', () async {
          late String transactionId;
          await DVTransactionRunner()<void>((DVContext context) async {
            transactionId = context.transactionId;
            await orders.write(_order('o1'));
          });
          final List<DVHistoryEntry> entries = await orders.history('o1');
          expect(entries.single.transactionId, transactionId);
        });

        test('a history entry that cannot be written takes the change with it',
            () async {
          final _FailingHistory failing = _FailingHistory(database);
          final DVRecordTable table = _orders(failing);
          final DVRecord read = (await table.write(_order('o1'))).record;

          failing.failHistory = true;
          await expectLater(
            table.write(_order('o1', quantity: 2), base: read),
            throwsA(isA<DVHistoryWriteError>().having(
                (DVHistoryWriteError e) => e.code, 'code', 'DV-HISTORY-005')),
          );
          failing.failHistory = false;

          final DVRecord after = (await table.read('o1'))!;
          expect(after.values['quantity'], 1,
              reason: 'a change with no history entry is not a record of it');
          expect(after.version, 1);
          expect(await table.history('o1'), hasLength(1));
        });

        test('a new record whose history fails is not left behind', () async {
          final _FailingHistory failing = _FailingHistory(database)
            ..failHistory = true;
          final DVRecordTable table = _orders(failing);
          await expectLater(
              table.write(_order('o1')), throwsA(isA<DVHistoryWriteError>()));
          failing.failHistory = false;
          expect(await table.read('o1', withDeleted: true), isNull);
        });

        test('retention removes entries older than declared', () async {
          final DVRecord read = (await orders.write(_order('o1'))).record;
          await orders.write(_order('o1', quantity: 2), base: read);

          final int removed = await orders.prune(
            now: DateTime.now().toUtc().add(const Duration(days: 400)),
          );
          expect(removed, 2);
          expect(await orders.history('o1'), isEmpty);
          expect((await orders.read('o1'))!.values['quantity'], 2,
              reason: 'retention removes the log, never the record');
        });

        test('a table without history writes no entries', () async {
          final DVRecordTable plain = _orders(database, history: null);
          await plain.ensureSchema();
          await plain.write(_order('p1'));
          expect(await plain.history('p1'), isEmpty);
        });
      });

      group('revert', () {
        test('restores an earlier state as a new change, keeping the history',
            () async {
          DVRecord record = (await orders.write(_order('o1'))).record;
          record = (await orders.write(_order('o1', quantity: 2), base: record))
              .record;
          record = (await orders.write(_order('o1', quantity: 3), base: record))
              .record;

          final List<DVHistoryEntry> before = await orders.history('o1');
          final DVRevertResult result =
              await orders.revert('o1', to: before.first, actor: 'ann');

          expect(result.record.values['quantity'], 1);
          expect(result.record.version, 4,
              reason: 'a revert is a write, not a rewind');
          final List<DVHistoryEntry> after = await orders.history('o1');
          expect(after, hasLength(4),
              reason: 'the entries in between are the audit; losing them is '
                  'the silent failure');
          expect(after.last.actor, 'ann');
        });

        test('reports the sensitive fields it could not put back', () async {
          DVRecord record = (await orders.write(_order('o1'))).record;
          final List<DVHistoryEntry> first = await orders.history('o1');
          record = (await orders.write(_order('o1', card: '9999', quantity: 2),
                  base: record))
              .record;

          final DVRevertResult result =
              await orders.revert('o1', to: first.first);
          expect(result.record.values['quantity'], 1);
          expect(result.unrestored, <String>{'card'});
          expect(result.code, 'DV-HISTORY-003');
          expect(result.record.values['card'], '9999',
              reason: 'left as it is, to be set deliberately');
        });

        test('takes the same version check as any other write', () async {
          final DVRecord record = (await orders.write(_order('o1'))).record;
          final List<DVHistoryEntry> entries = await orders.history('o1');
          await orders.write(_order('o1', quantity: 2), base: record);

          expect(
            () => orders.revert('o1', to: entries.first, base: record),
            throwsA(isA<DVConflictError>()),
          );
        });

        test('rolls back with the transaction it ran in', () async {
          DVRecord record = (await orders.write(_order('o1'))).record;
          final List<DVHistoryEntry> entries = await orders.history('o1');
          record = (await orders.write(_order('o1', quantity: 2), base: record))
              .record;

          await expectLater(
            DVTransactionRunner()<void>((DVContext context) async {
              await orders.revert('o1', to: entries.first);
              throw StateError('something later in the unit of work failed');
            }),
            throwsStateError,
          );

          final DVRecord after = (await orders.read('o1'))!;
          expect(after.values['quantity'], 2);
          expect(after.version, 2);
          expect(await orders.history('o1'), hasLength(2),
              reason: 'the rolled-back revert leaves no entry behind');
        });
      });

      group('soft delete', () {
        test('deleting marks the row and hides it from ordinary reads',
            () async {
          await orders.write(_order('o1'));
          await orders.delete('o1', actor: 'ann');

          expect(await orders.read('o1'), isNull);
          expect(await orders.all(), isEmpty);
          final DVRecord? kept = await orders.read('o1', withDeleted: true);
          expect(kept, isNotNull);
          expect(kept!.deletedAt, isNotNull);
          expect(await orders.all(withDeleted: true), hasLength(1));
          expect((await orders.history('o1')).last.deleted, isTrue);
        });

        test('restore brings it back', () async {
          await orders.write(_order('o1'));
          await orders.delete('o1');
          final DVRecord restored = await orders.restore('o1');
          expect(restored.deletedAt, isNull);
          expect(await orders.read('o1'), isNotNull);
        });

        test('restore is refused when a live record holds a unique field',
            () async {
          await orders.write(_order('o1', reference: 'R-1'));
          await orders.delete('o1');
          await orders.write(_order('o2', reference: 'R-1'));

          await expectLater(
            orders.restore('o1'),
            throwsA(isA<DVRestoreConflictError>()
                .having((DVRestoreConflictError e) => e.code, 'code',
                    'DV-HISTORY-006')
                .having((DVRestoreConflictError e) => e.fields, 'fields',
                    <String>{'reference'})),
          );
          expect(await orders.read('o1'), isNull,
              reason: 'two live rows claiming one reference is the outcome '
                  'the refusal exists to prevent');
        });

        test('without softDelete, delete removes the row', () async {
          final DVRecordTable hard = _orders(database, softDelete: false);
          await hard.ensureSchema();
          await hard.write(_order('h1'));
          await hard.delete('h1');
          expect(await hard.read('h1', withDeleted: true), isNull);
        });
      });

      // A generated model's save and destroy go through the record table, so
      // the delete has to hold to the same rule as the write: it applies to
      // the row as it was read, or it does not apply.
      group('deletes checked against the version read', () {
        test('a delete carrying a stale read is refused', () async {
          final DVRecord read = (await orders.write(_order('o1'))).record;
          await orders.write(_order('o1', quantity: 2), base: read);

          await expectLater(
            orders.delete('o1', base: read),
            throwsA(isA<DVConflictError>()
                .having((DVConflictError e) => e.expectedVersion,
                    'expectedVersion', 1)
                .having(
                    (DVConflictError e) => e.actualVersion, 'actualVersion', 2)),
          );
          expect((await orders.read('o1'))!.values['quantity'], 2,
              reason: 'the row somebody rewrote is still there');
        });

        test('a delete carrying the current read applies', () async {
          final DVRecord read = (await orders.write(_order('o1'))).record;
          await orders.delete('o1', base: read);
          expect(await orders.read('o1'), isNull);
        });

        test(
            'a hard delete that loses a race says so, and logs no deletion '
            'that did not happen', () async {
          final _RacingAdapter racing = _RacingAdapter(database);
          final DVRecordTable hard =
              _orders(racing, softDelete: false);
          await hard.ensureSchema();
          await hard.write(_order('h1'));
          // Another writer moves the row between the delete's read and its
          // DELETE, which then matches nothing.
          racing.before = (String sql) async {
            if (!sql.startsWith('DELETE FROM orders ')) return;
            racing.before = null;
            final DVRecord now = (await hard.read('h1'))!;
            await hard.write(_order('h1', quantity: 9), base: now);
          };

          await expectLater(hard.delete('h1'), throwsA(isA<DVConflictError>()));
          expect((await hard.read('h1'))!.values['quantity'], 9);
          final List<DVHistoryEntry> log = await hard.history('h1');
          expect(log.where((DVHistoryEntry e) => e.deleted), isEmpty,
              reason: 'a change log recording a delete that matched no row '
                  'is a record of something that never happened');
        });
      });

      group('the write result', () {
        test('says whether it inserted, including for an update that '
            'changed nothing', () async {
          expect((await orders.write(_order('o1'))).inserted, isTrue);
          final DVRecord read = (await orders.read('o1'))!;
          final DVWriteResult again =
              await orders.write(_order('o1'), base: read);
          expect(again.inserted, isFalse);
          expect(again.record.version, 1);
        });
      });

      // A tenant-scoped model keeps every tenant's rows in one table, keyed
      // per tenant. A record table reading by key alone would hand one
      // tenant's row to another, or overwrite it, and both look like a save
      // that worked.
      group('scoped to a tenant', () {
        late DVRecordTable acme;
        late DVRecordTable globex;

        DVRecordTable scoped(String tenant) => DVRecordTable(
              table: 'tenant_orders',
              key: 'id',
              columns: const <String>[
                'dv_tenant', 'id', 'reference', 'quantity', 'card',
              ],
              sensitive: const <String>{'card'},
              history: const DVHistory(),
              scope: DVRecordScope('dv_tenant', tenant),
              database: database,
            );

        setUp(() async {
          acme = scoped('acme');
          globex = scoped('globex');
          // One table for both tenants, with the tenant column, and its log.
          await acme.ensureSchema();
        });

        test('a key reused by another tenant is another row', () async {
          await acme.write(_order('o1', quantity: 1));
          final DVWriteResult theirs =
              await globex.write(_order('o1', quantity: 5));

          expect(theirs.inserted, isTrue,
              reason: "acme's o1 is not globex's to update");
          expect((await acme.read('o1'))!.values['quantity'], 1);
          expect((await globex.read('o1'))!.values['quantity'], 5);
          expect((await acme.read('o1'))!.values['dv_tenant'], 'acme');
          expect((await acme.all()).length, 1);
        });

        test("an update or delete never reaches another tenant's row",
            () async {
          await acme.write(_order('o1', quantity: 1));
          await globex.write(_order('o1', quantity: 5));

          final DVRecord read = (await acme.read('o1'))!;
          await acme.write(_order('o1', quantity: 2), base: read);
          expect((await globex.read('o1'))!.values['quantity'], 5);
          expect((await globex.read('o1'))!.version, 1);

          await acme.delete('o1');
          expect(await acme.read('o1'), isNull);
          expect(await globex.read('o1'), isNotNull);
        });

        test('a write naming another tenant is refused', () async {
          await expectLater(
            acme.write(<String, Object?>{
              ..._order('o1'),
              'dv_tenant': 'globex',
            }),
            throwsArgumentError,
          );
          expect(await globex.read('o1'), isNull);
        });

        test("history is the tenant's own", () async {
          await acme.write(_order('o1'));
          await globex.write(_order('o1'));
          final List<DVHistoryEntry> log = await acme.history('o1');
          expect(log, hasLength(1));
          expect(log.single.tenant, 'acme');
        });
      });
    });
  }

  group('table names', () {
    test('a schema-qualified name reads and writes that schema', () async {
      // schemaPerTenant resolves a model's table to `tenant.orders`.
      final SqliteDVDatabaseAdapter database = SqliteDVDatabaseAdapter.memory();
      addTearDown(database.close);
      await database.execute("ATTACH DATABASE ':memory:' AS acme");
      final DVRecordTable orders = DVRecordTable(
        table: 'acme.orders',
        key: 'id',
        columns: const <String>['id', 'reference', 'quantity', 'card'],
        history: const DVHistory(),
        database: database,
      );
      await orders.ensureSchema();
      await orders.write(_order('o1'));
      expect((await orders.read('o1'))!.version, 1);
      expect(await database.query('SELECT id FROM acme.orders'), hasLength(1));
      expect(await orders.history('o1'), hasLength(1));
    });

    test('anything else that is not an identifier is still refused', () {
      for (final String name in <String>[
        'a.b.c',
        '.orders',
        'orders; DROP TABLE users',
      ]) {
        expect(
          () => DVRecordTable(
            table: name,
            key: 'id',
            columns: const <String>['id'],
          ),
          throwsArgumentError,
          reason: name,
        );
      }
    });
  });
}

/// Runs [before] ahead of each statement, so a test can put another writer
/// between a read and the write that follows it.
class _RacingAdapter implements DVDatabaseAdapter {
  _RacingAdapter(this.inner);

  final DVDatabaseAdapter inner;
  Future<void> Function(String sql)? before;

  @override
  Future<List<Map<String, Object?>>> query(String sql,
          [List<Object?>? params]) =>
      inner.query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    await before?.call(sql);
    return inner.execute(sql, params);
  }
}
