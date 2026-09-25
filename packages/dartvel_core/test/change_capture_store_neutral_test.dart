// Change capture on a store that runs no SQL.
//
// Dartvel is storage-neutral: a data model's rows may sit in a SQL table or a
// document collection, and only the engine underneath knows which. The
// capture log, a destination's copies, and the erasure that reaches both are
// the framework's own records, so they go through the record operations
// every engine implements (Storage-Neutral Records) rather than through SQL
// strings a document store cannot run.
//
// DVMemoryRecordEngine refuses every SQL statement, so any part of capture
// still written as SQL fails here naming the statement.
import 'package:dartvel_core/dartvel.dart';
// The record layer and the capture machinery, which an application does not
// name and a test of them does.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

DVRecordTable _orders(DVDatabaseAdapter database, DVCapture capture) =>
    DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'reference', 'quantity', 'customer_email'],
      sensitive: const <String>{'customer_email'},
      capture: capture,
      database: database,
    );

void main() {
  late MemoryDVDatabaseAdapter source;
  late DVMemoryRecordEngine logStore;
  late DVMemoryRecordEngine destination;
  late DVCapture capture;
  late DVRecordTable orders;

  setUp(() async {
    // The model's own rows, where DVRecordTable keeps them today.
    source = MemoryDVDatabaseAdapter();
    // The log and the destination on engines that answer no SQL at all.
    logStore = DVMemoryRecordEngine();
    destination = DVMemoryRecordEngine();
    capture = DVCapture(database: logStore, retention: const Duration(days: 7));
    await capture.ensureSchema();
    orders = _orders(source, capture);
    await orders.ensureSchema();
  });

  test('the log records, publishes and reads without a SQL statement',
      () async {
    await orders.write(<String, Object?>{
      'id': 'o1',
      'reference': 'R-1',
      'quantity': 2,
      'customer_email': 'ada@example.com',
    });
    await orders.delete('o1');

    final List<DVCapturedChange> changes = await capture.changes();
    expect(
      changes.map((DVCapturedChange c) => c.operation),
      <DVCaptureOp>[DVCaptureOp.insert, DVCaptureOp.delete],
    );
    expect(changes.first.values, isNot(contains('customer_email')),
        reason: 'a sensitive field is named in a change and never carried');
    expect(await capture.head(), greaterThanOrEqualTo(2));
  });

  test('a store destination holds the newest copy of each record', () async {
    final DVCaptureConsumer consumer = capture.consumer(
      'warehouse',
      sink: DVWarehouseSink(database: destination),
    );
    final DVRecord first = (await orders.write(<String, Object?>{
      'id': 'o1',
      'reference': 'R-1',
      'quantity': 2,
      'customer_email': 'ada@example.com',
    }))
        .record;
    await orders.write(<String, Object?>{
      'id': 'o1',
      'reference': 'R-1',
      'quantity': 5,
      'customer_email': 'ada@example.com',
    }, base: first);
    await orders.write(<String, Object?>{
      'id': 'o2',
      'reference': 'R-2',
      'quantity': 1,
      'customer_email': 'bo@example.com',
    });
    await consumer.deliverAll();

    final List<Map<String, Object?>> rows = await destination.find(
      'orders',
      orderBy: const <DVSort>[DVSort('_dv_key')],
    );
    expect(rows.map((Map<String, Object?> r) => r['_dv_key']),
        <Object?>['o1', 'o2']);
    expect(rows.first['quantity'], 5);
    expect(rows.first['_dv_version'], 2);
    expect(rows.first.containsKey('customer_email'), isFalse);

    await orders.delete('o2');
    await consumer.deliverAll();
    expect(
      (await destination.find('orders'))
          .map((Map<String, Object?> r) => r['_dv_key']),
      <Object?>['o1'],
      reason: 'a delete is an event, and the copy goes with it',
    );
  });

  test('a new destination is backfilled from the model rows already stored',
      () async {
    await orders.write(<String, Object?>{
      'id': 'o1',
      'reference': 'R-1',
      'quantity': 2,
      'customer_email': 'ada@example.com',
    });
    // A destination added after the write: the copy comes from the rows the
    // model already holds, read through the record operations.
    final DVCaptureConsumer late = capture.consumer(
      'late',
      sink: DVWarehouseSink(database: destination),
    );
    final DVCaptureBackfillProgress progress = await late.backfill(orders);

    expect(progress.done, isTrue);
    expect(
      (await destination.find('orders')).single['reference'],
      'R-1',
    );
  });

  test('a field the source contracts is emptied at the destination', () async {
    final DVCaptureConsumer consumer = capture.consumer(
      'warehouse',
      sink: DVWarehouseSink(database: destination),
    );
    await orders.write(<String, Object?>{
      'id': 'o1',
      'reference': 'R-1',
      'quantity': 2,
      'customer_email': 'ada@example.com',
    });
    await consumer.deliverAll();
    expect((await destination.find('orders')).single['reference'], 'R-1');

    // The model no longer declares reference.
    await DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'quantity', 'customer_email'],
      sensitive: const <String>{'customer_email'},
      capture: capture,
      database: source,
    ).write(<String, Object?>{
      'id': 'o2',
      'quantity': 1,
      'customer_email': 'bo@example.com',
    });
    await consumer.deliverAll();

    for (final Map<String, Object?> row in await destination.find('orders')) {
      expect(row['reference'], isNull,
          reason: 'a store has no column to drop, so what the source no '
              'longer declares is removed from every copy instead');
    }
  });

  test('an erasure reaches the log and a store destination', () async {
    final DVWarehouseSink sink = DVWarehouseSink(database: destination);
    final DVCaptureConsumer consumer =
        capture.consumer('warehouse', sink: sink);
    final DVRecordTable users = DVRecordTable(
      table: 'users',
      key: 'id',
      columns: const <String>['id', 'email'],
      capture: capture,
      database: source,
    );
    await users.ensureSchema();
    await users.write(<String, Object?>{'id': 'u1', 'email': 'ada@x.test'});
    await consumer.deliverAll();
    expect(await destination.find('users'), hasLength(1));

    final DVPrivacy privacy = DVPrivacy(
      models: <DVPrivacyModel>[
        DVPrivacyModel(
          name: 'users',
          table: users,
          subject: DVSubject.self,
          personal: const <String>{'email'},
          retention: DVRetention.indefinite,
        ),
      ],
      database: source,
      signingKey: List<int>.filled(32, 7),
      adapters: <DVPrivacyAdapter>[
        DVCapturePrivacyAdapter(
          capture: capture,
          sinks: <DVCaptureSink>[sink],
        ),
      ],
    );
    await privacy.ensureSchema();
    await privacy.erase(subject: 'u1', reason: 'request');

    expect(await destination.find('users'), isEmpty);
    final List<DVCapturedChange> log = await capture.changes();
    expect(
      log.where((DVCapturedChange c) => c.values.containsValue('ada@x.test')),
      isEmpty,
      reason: 'the log keeps no value an erasure removed',
    );
  });
}
