// Change data capture: the ordered, replayable log of a model's own writes,
// and its delivery to destinations that are not databases.
//
// Every failure worth a test here is a silent one. A change captured from a
// transaction that rolled back puts a row in a warehouse that the application
// never kept. A crash between a delivery and its checkpoint either drops the
// batch (a gap nobody sees) or sends it twice (which a destination has to be
// told about). Two updates to one row committed in the opposite order to the
// one they were written in leave the older value standing. A sensitive field
// or an erased subject that reaches a destination has left the system for
// good. Each has a test below that fails if the behaviour quietly regresses.
import 'package:dartvel_core/src/observability/observability.dart';
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
// The record layer, which an application does not name and a test of it
// does.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

/// A destination that keeps what it was sent, in order.
class _RecordingSink implements DVCaptureSink {
  _RecordingSink({this.deduplicates = true, this.name = 'recording'});

  @override
  final String name;

  @override
  final bool deduplicates;

  final List<DVCaptureBatch> batches = <DVCaptureBatch>[];
  final List<DVCaptureSchemaChange> schema = <DVCaptureSchemaChange>[];
  final List<DVCapturedChange> erased = <DVCapturedChange>[];
  final List<(String, int)> backfills = <(String, int)>[];

  /// Everything delivered, in delivery order, schema changes included.
  final List<Object> timeline = <Object>[];

  bool refuseWrites = false;
  bool refuseSchema = false;

  List<DVCapturedChange> get changes => <DVCapturedChange>[
        for (final DVCaptureBatch batch in batches) ...batch.changes,
      ];

  @override
  Future<void> write(DVCaptureBatch batch) async {
    if (refuseWrites) throw StateError('warehouse is read-only');
    batches.add(batch);
    timeline.addAll(batch.changes);
  }

  @override
  Future<void> evolve(DVCaptureSchemaChange change) async {
    if (refuseSchema) throw StateError('ALTER refused');
    schema.add(change);
    timeline.add(change);
  }

  @override
  Future<void> erase(List<DVCapturedChange> changes) async {
    erased.addAll(changes);
  }

  @override
  Future<void> backfillComplete(String model, int throughSequence,
      {String? tenant}) async {
    backfills.add((model, throughSequence));
  }
}

/// Wraps an adapter and fails the statements a test names, the way a dropped
/// connection or a killed process would between two writes.
class _Faulty implements DVDatabaseAdapter {
  _Faulty(this.inner);

  final DVDatabaseAdapter inner;
  bool Function(String sql)? failWhen;

  @override
  Future<List<Map<String, Object?>>> query(String sql,
          [List<Object?>? params]) =>
      inner.query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) {
    final bool Function(String sql)? fail = failWhen;
    if (fail != null && fail(sql)) throw StateError('connection lost');
    return inner.execute(sql, params);
  }
}

DVRecordTable _orders(DVDatabaseAdapter database, DVCapture capture,
        {List<String> columns = const <String>[
          'id',
          'reference',
          'quantity',
          'customer_email',
        ],
        bool softDelete = false}) =>
    DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: columns,
      sensitive: const <String>{'customer_email'},
      softDelete: softDelete,
      capture: capture,
      database: database,
    );

Map<String, Object?> _order(String id,
        {String reference = 'R-1',
        int quantity = 1,
        String email = 'ada@example.com'}) =>
    <String, Object?>{
      'id': id,
      'reference': reference,
      'quantity': quantity,
      'customer_email': email,
    };

void main() {
  for (final _Adapter adapter in _adapters) {
    group('on ${adapter.$1}', () {
      late DVDatabaseAdapter database;
      late DVCapture capture;
      late DVRecordTable orders;
      late DateTime now;

      setUp(() async {
        database = adapter.$2();
        now = DateTime.utc(2026, 9, 14, 12);
        capture = DVCapture(
          database: database,
          retention: const Duration(days: 7),
          clock: () => now,
        );
        await capture.ensureSchema();
        orders = _orders(database, capture);
        await orders.ensureSchema();
      });

      group('the stream is the model\'s own writes', () {
        test('inserts, updates and deletes arrive in order, each an event',
            () async {
          final DVRecord first = (await orders.write(_order('o1'))).record;
          await orders.write(_order('o1', quantity: 2), base: first);
          await orders.delete('o1');

          final _RecordingSink sink = _RecordingSink();
          final DVCaptureDelivery result =
              await capture.consumer('wh', sink: sink).deliverOnce();

          final List<DVCapturedChange> got = sink.changes;
          expect(got.map((DVCapturedChange c) => c.operation), <DVCaptureOp>[
            DVCaptureOp.insert,
            DVCaptureOp.update,
            DVCaptureOp.delete,
          ]);
          expect(got.map((DVCapturedChange c) => c.version), <int>[1, 2, 3]);
          expect(got.map((DVCapturedChange c) => c.key), everyElement('o1'));
          final List<int> sequences =
              got.map((DVCapturedChange c) => c.sequence).toList();
          expect(sequences, orderedEquals(List<int>.of(sequences)..sort()));
          expect(sequences.toSet(), hasLength(3));
          expect(got.map((DVCapturedChange c) => c.id).toSet(), hasLength(3),
              reason: 'every change carries its own id for deduplication');
          expect(got[1].values['quantity'], 2);
          expect(got[2].values, isEmpty,
              reason: 'a delete carries the key, not the row');
          expect(result.checkpoint, sequences.last);
        });

        test('a soft delete is a delete event and a restore brings it back',
            () async {
          final DVRecordTable soft = _orders(database, capture, softDelete: true);
          await soft.write(_order('o1'));
          await soft.delete('o1');
          await soft.restore('o1');

          final _RecordingSink sink = _RecordingSink();
          await capture.consumer('wh', sink: sink).deliverOnce();
          expect(sink.changes.map((DVCapturedChange c) => c.operation),
              <DVCaptureOp>[
                DVCaptureOp.insert,
                DVCaptureOp.delete,
                DVCaptureOp.restore,
              ]);
        });

        test('a sensitive field is redacted in the log itself, not on the way '
            'out', () async {
          await orders.write(_order('o1', email: 'ada@example.com'));

          final List<Map<String, Object?>> raw = await database.query(
            'SELECT * FROM ${DVCapture.logTable}',
          );
          expect(jsonEncode(raw), isNot(contains('ada@example.com')),
              reason: 'the log\'s own storage must never hold the value');

          final _RecordingSink sink = _RecordingSink();
          await capture.consumer('wh', sink: sink).deliverOnce();
          final DVCapturedChange change = sink.changes.single;
          expect(change.values.containsKey('customer_email'), isFalse);
          expect(change.redacted, contains('customer_email'));
          expect(sink.schema.single.columns, isNot(contains('customer_email')),
              reason: 'a destination is never given a column for it either');
        });

        test('tenant scope travels with the row and a tenant destination is '
            'filtered at the source', () async {
          await orders.write(_order('a1'), tenant: 'acme');
          await const DVTenants()
              .withTenant('globex', () => orders.write(_order('g1')));
          await orders.write(_order('n1'));

          final _RecordingSink acme = _RecordingSink();
          final _RecordingSink all = _RecordingSink();
          await capture.consumer('acme', sink: acme, tenant: 'acme').deliverOnce();
          await capture.consumer('all', sink: all).deliverOnce();

          expect(acme.changes.map((DVCapturedChange c) => c.key), <Object>['a1'],
              reason: 'a row with another tenant, or none, must not reach a '
                  'tenant destination');
          expect(
            <Object?, String?>{
              for (final DVCapturedChange c in all.changes) c.key: c.tenant,
            },
            <Object?, String?>{'a1': 'acme', 'g1': 'globex', 'n1': null},
          );
        });
      });

      group('transactions', () {
        test('a rolled-back transaction delivers nothing, even to a delivery '
            'that runs while it is still open', () async {
          final _RecordingSink sink = _RecordingSink();
          final DVCaptureConsumer consumer = capture.consumer('wh', sink: sink);

          await expectLater(
            DVTransactionRunner()<void>((DVContext context) async {
              await orders.write(_order('o1'));
              await consumer.deliverOnce();
              expect(sink.changes, isEmpty,
                  reason: 'an uncommitted change is not in the stream');
              throw StateError('payment declined');
            }),
            throwsA(isA<StateError>()),
          );

          await consumer.deliverOnce();
          expect(sink.changes, isEmpty,
              reason: 'the write was compensated; its change must be too');
          expect(await orders.read('o1'), isNull);
          final List<Map<String, Object?>> raw = await database.query(
            'SELECT * FROM ${DVCapture.logTable}',
          );
          expect(raw, isEmpty);
        });

        test('a committed transaction is delivered after commit, with its id',
            () async {
          late String id;
          await DVTransactionRunner()<void>((DVContext context) async {
            id = context.transactionId;
            await orders.write(_order('o1'));
            await orders.write(_order('o2'));
          });
          final _RecordingSink sink = _RecordingSink();
          await capture.consumer('wh', sink: sink).deliverOnce();
          expect(sink.changes.map((DVCapturedChange c) => c.key),
              <Object>['o1', 'o2']);
          expect(sink.changes.map((DVCapturedChange c) => c.transactionId),
              everyElement(id));
        });

        test('a change stranded by a crash after commit is published by '
            'recovery rather than lost', () async {
          final _Faulty faulty = _Faulty(database);
          final DVCapture crashing = DVCapture(
            database: faulty,
            retention: const Duration(days: 7),
            clock: () => now,
          );
          final DVRecordTable table = _orders(faulty, crashing);
          // The publish after commit dies: the row is written, its change is
          // staged, and nothing gives it a sequence.
          faulty.failWhen = (String sql) =>
              sql.contains('UPDATE ${DVCapture.stateTable}');
          await DVTransactionRunner()<void>((DVContext context) async {
            await table.write(_order('o1'));
          }).catchError((Object _) {});
          faulty.failWhen = null;

          final _RecordingSink sink = _RecordingSink();
          await capture.consumer('wh', sink: sink).deliverOnce();
          expect(sink.changes, isEmpty);

          now = now.add(const Duration(minutes: 10));
          expect(await capture.publishStranded(), 1);
          await capture.consumer('wh', sink: sink).deliverOnce();
          expect(sink.changes.map((DVCapturedChange c) => c.key), <Object>['o1']);
        });
      });

      group('delivery', () {
        test('a crash between delivery and checkpoint redelivers the batch: '
            'no gap, and the duplicate carries the same change ids', () async {
          final _Faulty faulty = _Faulty(database);
          final DVCapture crashing = DVCapture(
            database: faulty,
            retention: const Duration(days: 7),
            clock: () => now,
          );
          final DVRecordTable table = _orders(faulty, crashing);
          await table.write(_order('o1'));
          await table.write(_order('o2'));

          final _RecordingSink sink = _RecordingSink();
          faulty.failWhen =
              (String sql) => sql.contains(DVCapture.checkpointTable);
          await expectLater(
            crashing.consumer('wh', sink: sink).deliverOnce(),
            throwsA(isA<StateError>()),
          );
          expect(sink.changes, hasLength(2), reason: 'the batch did land');
          faulty.failWhen = null;

          await crashing.consumer('wh', sink: sink).deliverOnce();
          final List<String> ids =
              sink.changes.map((DVCapturedChange c) => c.id).toList();
          expect(ids, hasLength(4));
          expect(ids.sublist(2), ids.sublist(0, 2),
              reason: 'the redelivery is the same changes, in the same order');

          await table.write(_order('o3'));
          await crashing.consumer('wh', sink: sink).deliverOnce();
          expect(sink.changes.last.key, 'o3');
          expect(sink.changes, hasLength(5));
        });

        test('a refused batch is DV-CDC-001 and the checkpoint stays put',
            () async {
          await orders.write(_order('o1'));
          final _RecordingSink sink = _RecordingSink()..refuseWrites = true;
          final DVCaptureConsumer consumer = capture.consumer('wh', sink: sink);

          final DVCaptureDeliveryError error = await consumer
              .deliverOnce()
              .then<DVCaptureDeliveryError>(
                  (_) => fail('a refused batch must not report success'),
                  onError: (Object e) => e as DVCaptureDeliveryError);
          expect(error.code, 'DV-CDC-001');
          expect(await consumer.checkpoint(), 0);

          sink.refuseWrites = false;
          await consumer.deliverOnce();
          expect(sink.changes.map((DVCapturedChange c) => c.key), <Object>['o1']);
        });

        test('a destination that cannot deduplicate is told: DV-CDC-004',
            () async {
          await orders.write(_order('o1'));
          final _RecordingSink plain = _RecordingSink(deduplicates: false);
          final DVCaptureDelivery result =
              await capture.consumer('plain', sink: plain).deliverOnce();
          expect(result.codes, contains('DV-CDC-004'));
          expect(plain.batches.single.atLeastOnce, isTrue);

          final _RecordingSink dedup = _RecordingSink();
          final DVCaptureDelivery quiet =
              await capture.consumer('dedup', sink: dedup).deliverOnce();
          expect(quiet.codes, isNot(contains('DV-CDC-004')));
        });

        test('batches are bounded and a consumer resumes where it stopped',
            () async {
          for (int i = 0; i < 5; i++) {
            await orders.write(_order('o$i'));
          }
          final _RecordingSink sink = _RecordingSink();
          final DVCaptureConsumer consumer =
              capture.consumer('wh', sink: sink, batchSize: 2);
          // The bound is on log entries read, schema changes included, so a
          // run past rows the consumer filters out still ends.
          final DVCaptureDelivery first = await consumer.deliverOnce();
          expect(first.read, 2);
          expect(first.delivered, lessThanOrEqualTo(2));
          expect((await consumer.deliverAll()).delivered, 5 - first.delivered);
          expect(sink.changes.map((DVCapturedChange c) => c.key),
              <Object>['o0', 'o1', 'o2', 'o3', 'o4']);
        });

        test('a model filter delivers only its models and still advances',
            () async {
          final DVRecordTable notes = DVRecordTable(
            table: 'notes',
            key: 'id',
            columns: const <String>['id', 'body'],
            capture: capture,
            database: database,
          );
          await notes.ensureSchema();
          await notes.write(<String, Object?>{'id': 'n1', 'body': 'x'});
          await orders.write(_order('o1'));
          await notes.write(<String, Object?>{'id': 'n2', 'body': 'y'});

          final _RecordingSink sink = _RecordingSink();
          final DVCaptureConsumer consumer = capture.consumer('wh',
              sink: sink, models: const <String>{'orders'});
          final DVCaptureDelivery result = await consumer.deliverOnce();
          expect(sink.changes.map((DVCapturedChange c) => c.key), <Object>['o1']);
          expect(result.checkpoint, await capture.head());
          expect(sink.schema.map((DVCaptureSchemaChange c) => c.model),
              everyElement('orders'));
        });
      });

      group('retention and lag', () {
        test('a consumer behind the retention window is told to backfill: '
            'DV-CDC-002, never handed a gap', () async {
          await orders.write(_order('o1'));
          final _RecordingSink early = _RecordingSink();
          final DVCaptureConsumer ahead = capture.consumer('ahead', sink: early);
          await ahead.deliverOnce();

          now = now.add(const Duration(days: 8));
          await orders.write(_order('o2'));
          expect(await capture.prune(), greaterThan(0));

          await expectLater(
            capture.consumer('late', sink: _RecordingSink()).deliverOnce(),
            throwsA(isA<DVCaptureBehindRetentionError>()
                .having((DVCaptureBehindRetentionError e) => e.code, 'code',
                    'DV-CDC-002')),
          );
          await ahead.deliverOnce();
          expect(early.changes.map((DVCapturedChange c) => c.key),
              <Object>['o1', 'o2'],
              reason: 'a consumer inside the window is unaffected');
        });

        test('lag is measured and past its threshold is DV-CDC-003', () async {
          await orders.write(_order('o1'));
          final _RecordingSink sink = _RecordingSink()..refuseWrites = true;
          final DVCaptureConsumer consumer = capture.consumer('wh',
              sink: sink, lagThreshold: const Duration(minutes: 5));

          now = now.add(const Duration(hours: 4));
          final DVCaptureLag lag = await consumer.lag();
          expect(lag.changes, 1);
          expect(lag.age, const Duration(hours: 4));
          expect(lag.codes, contains('DV-CDC-003'));
          expect(
            DVObservability.metrics.valueOf('dv_capture_lag_seconds',
                const <String, String>{'consumer': 'wh'}),
            const Duration(hours: 4).inSeconds.toDouble(),
          );

          sink.refuseWrites = false;
          await consumer.deliverOnce();
          final DVCaptureLag caughtUp = await consumer.lag();
          expect(caughtUp.changes, 0);
          expect(caughtUp.age, Duration.zero);
          expect(caughtUp.codes, isEmpty);
        });
      });

      group('schema', () {
        test('a column is added before the first row carrying it, and removed '
            'after the last', () async {
          await orders.write(_order('o1'));
          await _addChannel(adapter.$1, database);
          final DVRecordTable wider = _orders(database, capture, columns: const <String>[
            'id',
            'reference',
            'quantity',
            'customer_email',
            'channel',
          ]);
          await wider.write(<String, Object?>{..._order('o2'), 'channel': 'web'});
          final DVRecordTable narrower = _orders(database, capture,
              columns: const <String>['id', 'quantity', 'customer_email', 'channel']);
          await narrower.write(<String, Object?>{
            'id': 'o3',
            'quantity': 1,
            'customer_email': 'x@example.com',
            'channel': 'app',
          });

          final _RecordingSink sink = _RecordingSink();
          await capture.consumer('wh', sink: sink).deliverOnce();
          final List<String> timeline = <String>[
            for (final Object event in sink.timeline)
              event is DVCaptureSchemaChange
                  ? '${event.phase.name}:${event.columns.join(',')}'
                  : 'row:${(event as DVCapturedChange).key}',
          ];
          expect(timeline, <String>[
            'expand:id,reference,quantity',
            'row:o1',
            'expand:channel',
            'row:o2',
            'contract:reference',
            'row:o3',
          ]);
        });

        test('a destination that cannot evolve stops delivery at the schema '
            'change: DV-CDC-005', () async {
          await orders.write(_order('o1'));
          final _RecordingSink sink = _RecordingSink();
          final DVCaptureConsumer consumer = capture.consumer('wh', sink: sink);
          await consumer.deliverOnce();
          final int before = await consumer.checkpoint();

          await _addChannel(adapter.$1, database);
          final DVRecordTable wider = _orders(database, capture,
              columns: const <String>['id', 'reference', 'quantity', 'customer_email', 'channel']);
          await wider.write(<String, Object?>{..._order('o2'), 'channel': 'web'});
          sink.refuseSchema = true;
          await expectLater(
            consumer.deliverOnce(),
            throwsA(isA<DVCaptureSchemaError>()
                .having((DVCaptureSchemaError e) => e.code, 'code', 'DV-CDC-005')),
          );
          expect(sink.changes.map((DVCapturedChange c) => c.key), <Object>['o1'],
              reason: 'a row carrying a column the destination lacks must not '
                  'be sent past the failed change');
          expect(await consumer.checkpoint(), before);
        });
      });

      group('erasure', () {
        late DVRecordTable users;
        late DVPrivacy privacy;
        late _RecordingSink sink;

        setUp(() async {
          users = DVRecordTable(
            table: 'users',
            key: 'id',
            columns: const <String>['id', 'email', 'plan'],
            capture: capture,
            database: database,
          );
          await users.ensureSchema();
          final DVRecordTable invoices = DVRecordTable(
            table: 'invoices',
            key: 'id',
            columns: const <String>['id', 'user_id', 'billing_name', 'total'],
            capture: capture,
            database: database,
          );
          await invoices.ensureSchema();
          sink = _RecordingSink();
          privacy = DVPrivacy(
            models: <DVPrivacyModel>[
              DVPrivacyModel(
                name: 'users',
                table: users,
                subject: DVSubject.self,
                personal: const <String>{'email'},
                retention: DVRetention.indefinite,
              ),
              DVPrivacyModel(
                name: 'invoices',
                table: invoices,
                subject: const DVSubject.field('user_id'),
                personal: const <String>{'billing_name'},
                retain: const DVRetain(years: 7, because: 'tax'),
                retention: DVRetention.indefinite,
              ),
            ],
            database: database,
            signingKey: List<int>.filled(32, 7),
            adapters: <DVPrivacyAdapter>[
              DVCapturePrivacyAdapter(capture: capture, sinks: <DVCaptureSink>[sink]),
            ],
          );
          await privacy.ensureSchema();
          await users.write(<String, Object?>{
            'id': 'u1',
            'email': 'ada@example.com',
            'plan': 'pro',
          });
          await invoices.write(<String, Object?>{
            'id': 'i1',
            'user_id': 'u1',
            'billing_name': 'Ada Lovelace',
            'total': 10,
          });
          await users.write(<String, Object?>{
            'id': 'u2',
            'email': 'bob@example.com',
            'plan': 'free',
          });
        });

        test('the log keeps no earlier value, a behind consumer never '
            'receives one, and the destination is erased directly', () async {
          final DVErasureResult result =
              await privacy.erase(subject: 'u1', reason: 'request');
          expect(result.complete, isTrue);

          final String raw = jsonEncode(await database.query(
            'SELECT * FROM ${DVCapture.logTable}',
          ));
          expect(raw, isNot(contains('ada@example.com')));
          expect(raw, isNot(contains('Ada Lovelace')));
          expect(raw, contains('bob@example.com'),
              reason: 'another subject\'s changes are untouched');

          final Map<Object?, DVCapturedChange> direct = <Object?, DVCapturedChange>{
            for (final DVCapturedChange c in sink.erased) c.key: c,
          };
          expect(direct['u1']!.operation, DVCaptureOp.delete);
          expect(direct['u1']!.erased, isTrue);
          expect(direct['i1']!.operation, DVCaptureOp.update,
              reason: 'a row kept under retention is overwritten, not removed');
          expect(direct['i1']!.values['billing_name'], DVPrivacy.tombstone);

          final _RecordingSink behind = _RecordingSink(name: 'behind');
          await capture.consumer('behind', sink: behind).deliverOnce();
          final String delivered = jsonEncode(<Object?>[
            for (final DVCapturedChange c in behind.changes)
              <String, Object?>{'key': c.key, 'values': c.values},
          ]);
          expect(delivered, isNot(contains('ada@example.com')));
          expect(delivered, isNot(contains('Ada Lovelace')));
          expect(behind.changes.where((DVCapturedChange c) => c.key == 'u1').last.operation,
              DVCaptureOp.delete);
          expect(behind.changes.where((DVCapturedChange c) => c.key == 'u2'),
              isNotEmpty);
        });

        test('an unreachable destination makes the erasure incomplete',
            () async {
          final DVPrivacy failing = DVPrivacy(
            models: privacy.models,
            database: database,
            signingKey: List<int>.filled(32, 7),
            adapters: <DVPrivacyAdapter>[
              DVCapturePrivacyAdapter(
                capture: capture,
                sinks: <DVCaptureSink>[_UnreachableSink()],
              ),
            ],
          );
          final DVErasureResult result =
              await failing.erase(subject: 'u1', reason: 'request');
          expect(result.complete, isFalse);
          expect(result.codes, contains('DV-PRIVACY-009'));
        });
      });

      group('backfill', () {
        test('a destination added later backfills history as a resumable job',
            () async {
          for (int i = 0; i < 5; i++) {
            await orders.write(_order('o$i', quantity: i));
          }
          now = now.add(const Duration(days: 8));
          await capture.prune();

          final _RecordingSink sink = _RecordingSink();
          final DVCaptureConsumer consumer = capture.consumer('new', sink: sink);
          await expectLater(
              consumer.deliverOnce(), throwsA(isA<DVCaptureBehindRetentionError>()));

          final DVCaptureBackfillProgress first =
              await consumer.backfill(orders, chunkSize: 2, maxChunks: 1);
          expect(first.rows, 2);
          expect(first.done, isFalse);
          await orders.write(_order('o9'));
          final DVCaptureBackfillProgress rest =
              await consumer.backfill(orders, chunkSize: 2);
          expect(rest.done, isTrue);
          expect(rest.rows, 6);

          final Iterable<DVCapturedChange> snapshot = sink.changes
              .where((DVCapturedChange c) => c.operation == DVCaptureOp.snapshot);
          expect(snapshot.map((DVCapturedChange c) => c.key).toSet(),
              <Object>{'o0', 'o1', 'o2', 'o3', 'o4', 'o9'});
          expect(snapshot.every((DVCapturedChange c) => !c.values.containsKey('customer_email')),
              isTrue);
          expect(sink.backfills.single.$1, 'orders');

          await consumer.deliverOnce();
          expect(sink.changes.last.key, 'o9',
              reason: 'the stream resumes from where the backfill began');
        });

        // A new destination is backfilled model by model, and each model's
        // copy moves the checkpoint to the head it began at. A change to a
        // model whose copy had already finished, made before the next
        // model's copy began, was skipped by that move: the stream was all
        // the first copy had for it, and the destination never saw it.
        test('a second model\'s backfill does not skip the first model\'s '
            'later changes', () async {
          final DVRecordTable notes = DVRecordTable(
            table: 'notes',
            key: 'id',
            columns: const <String>['id', 'body'],
            capture: capture,
            database: database,
          );
          await notes.ensureSchema();
          await orders.write(_order('o1'));
          await notes.write(<String, Object?>{'id': 'n1', 'body': 'first'});

          final _RecordingSink sink = _RecordingSink();
          final DVCaptureConsumer consumer = capture.consumer('new', sink: sink);
          expect((await consumer.backfill(orders)).done, isTrue);

          // After the orders copy, before the notes copy begins.
          await orders.write(_order('o2', quantity: 9));

          expect((await consumer.backfill(notes)).done, isTrue);
          await consumer.deliverAll();

          expect(
            sink.changes.map((DVCapturedChange c) => c.key),
            contains('o2'),
            reason: 'the write to orders after its copy has to arrive',
          );
        });

        test('a tenant destination cannot backfill a table with no tenant '
            'column', () async {
          await orders.write(_order('o1'), tenant: 'acme');
          await expectLater(
            capture
                .consumer('acme', sink: _RecordingSink(), tenant: 'acme')
                .backfill(orders),
            throwsA(isA<ArgumentError>()),
          );
        });
      });

      // A removal the privacy walk makes -- a retention sweep, an erasure, a
      // replayed erasure, a device's offline copy -- is the one change the law
      // requires to reach every copy. Made beside the record table rather than
      // through it, it reached none of them: the warehouse kept exactly the
      // rows the source removed for retention.
      group('removals the privacy walk makes reach the log', () {
        late DVDatabaseAdapter warehouseDb;
        late DVCaptureConsumer consumer;
        late DVRecordTable sessions;

        Future<List<String>> warehoused([String model = 'sessions']) async =>
            <String>[
              for (final Map<String, Object?> r in await warehouseDb
                  .query('SELECT * FROM $model ORDER BY _dv_key'))
                '${r['_dv_key']}',
            ];

        Future<String> logText() async => jsonEncode(
            await database.query('SELECT * FROM ${DVCapture.logTable}'));

        Future<void> session(String id, String user, String ip) =>
            sessions.write(<String, Object?>{
              'id': id,
              'user_id': user,
              'ip': ip,
              'created_at': now.toIso8601String(),
            });

        DVPrivacy privacyOver(
          DVRetention retention, {
          List<DVPrivacyAdapter> adapters = const <DVPrivacyAdapter>[],
        }) =>
            DVPrivacy(
              models: <DVPrivacyModel>[
                DVPrivacyModel(
                  name: 'sessions',
                  table: sessions,
                  subject: const DVSubject.field('user_id'),
                  personal: const <String>{'ip'},
                  retention: retention,
                ),
              ],
              database: database,
              signingKey: List<int>.filled(32, 7),
              adapters: adapters,
              now: () => now,
            );

        setUp(() async {
          warehouseDb = SqliteDVDatabaseAdapter.memory();
          consumer = capture.consumer('warehouse',
              sink: DVWarehouseSink(database: warehouseDb));
          sessions = DVRecordTable(
            table: 'sessions',
            key: 'id',
            columns: const <String>['id', 'user_id', 'ip', 'created_at'],
            history: const DVHistory(),
            softDelete: true,
            capture: capture,
            database: database,
          );
          await sessions.ensureSchema();
        });

        test("a retention sweep's deletes reach the warehouse, one captured "
            'delete per swept row, in resumable batches', () async {
          await session('old0', 'u1', '10.1.0.0');
          await session('old1', 'u1', '10.1.0.1');
          await session('old2', 'u1', '10.1.0.2');
          // Soft-deleted: gone from the warehouse, still held at the source,
          // and its values still in the log.
          await sessions.delete('old2');
          now = now.add(const Duration(days: 20));
          await session('fresh', 'u1', '10.9.9.9');
          await consumer.deliverAll();
          expect(await warehoused(), <String>['fresh', 'old0', 'old1']);

          now = now.add(const Duration(days: 15));
          final DVPrivacy privacy = privacyOver(
              const DVRetention.days(30, from: 'created_at'));
          await privacy.ensureSchema();

          final int head = await capture.head();
          final DVRetentionPlan plan = await privacy.planRetention();
          expect(plan.deletions['sessions'], 3);
          expect(await capture.head(), head,
              reason: 'a plan is a preview and captures nothing');
          expect(await warehoused(), <String>['fresh', 'old0', 'old1']);

          final DVRetentionSweep first =
              await privacy.sweepRetention(batchSize: 2, maxBatches: 1);
          expect(first.remaining, 1);
          await consumer.deliverAll();
          final DVRetentionSweep second =
              await privacy.sweepRetention(batchSize: 2);
          expect(second.remaining, 0);
          await consumer.deliverAll();

          expect(await warehoused(), <String>['fresh'],
              reason: 'a warehouse must not keep what retention removed');
          final List<DVCapturedChange> erasures = <DVCapturedChange>[
            for (final DVCapturedChange c in await capture.changes())
              if (c.erased) c,
          ];
          expect(erasures.map((DVCapturedChange c) => c.operation),
              everyElement(DVCaptureOp.delete));
          expect(
              erasures.map((DVCapturedChange c) => '${c.key}').toList()..sort(),
              <String>['old0', 'old1', 'old2']);
          final String log = await logText();
          for (int i = 0; i < 3; i++) {
            expect(log, isNot(contains('10.1.0.$i')),
                reason: 'the log is a copy retention applies to');
          }
          expect(log, contains('10.9.9.9'));
          expect(await sessions.history('old0'), isEmpty);
        });

        test('a sweep that anonymizes sends the anonymized row, and no copy '
            'keeps the earlier value', () async {
          await session('s1', 'u1', '10.1.0.1');
          await consumer.deliverAll();
          now = now.add(const Duration(days: 31));
          final DVRetentionSweep sweep = await privacyOver(const DVRetention.days(
                  30,
                  from: 'created_at',
                  then: DVRetentionAction.anonymize))
              .sweepRetention();
          expect(sweep.anonymized['sessions'], 1);
          await consumer.deliverAll();

          final List<Map<String, Object?>> stored =
              await warehouseDb.query('SELECT * FROM sessions');
          expect(stored.single['ip'], DVPrivacy.tombstone);
          expect(jsonEncode(stored), isNot(contains('10.1.0.1')));
          expect(await logText(), isNot(contains('10.1.0.1')));
        });

        test('an erasure with no capture adapter still purges the log and '
            'reaches a warehouse fed by delivery', () async {
          await session('s1', 'u1', '10.1.0.1');
          await session('s2', 'u2', '10.2.0.2');
          await consumer.deliverAll();
          final DVPrivacy privacy = privacyOver(DVRetention.indefinite);
          await privacy.ensureSchema();

          final DVErasureResult result =
              await privacy.erase(subject: 'u1', reason: 'request');
          expect(result.deleted['sessions'], 1);
          await consumer.deliverAll();

          expect(await warehoused(), <String>['s2']);
          final String log = await logText();
          expect(log, isNot(contains('10.1.0.1')));
          expect(log, contains('10.2.0.2'));
        });

        test('an erasure through the capture adapter captures each record '
            'once, at a version a warehouse fed by delivery applies', () async {
          await session('s1', 'u1', '10.1.0.1');
          await session('s2', 'u2', '10.2.0.2');
          await consumer.deliverAll();
          // The adapter erases this destination directly; the warehouse is
          // not among its sinks and hears of the erasure only by delivery.
          final _RecordingSink direct = _RecordingSink(name: 'direct');
          final DVPrivacy privacy = privacyOver(
            DVRetention.indefinite,
            adapters: <DVPrivacyAdapter>[
              DVCapturePrivacyAdapter(
                  capture: capture, sinks: <DVCaptureSink>[direct]),
            ],
          );
          await privacy.ensureSchema();

          final DVErasureResult result =
              await privacy.erase(subject: 'u1', reason: 'request');
          expect(result.complete, isTrue);
          expect(direct.erased.map((DVCapturedChange c) => c.key), <Object?>['s1']);
          await consumer.deliverAll();

          expect(await warehoused(), <String>['s2']);
          expect(<Object?>[
            for (final DVCapturedChange c in await capture.changes())
              if (c.erased) c.key,
          ], <Object?>['s1'],
              reason: 'the walk and the adapter must not both capture it');
        });

        test('a replayed erasure purges the values a restore put back in the '
            'log', () async {
          await session('s1', 'u1', '10.1.0.1');
          await consumer.deliverAll();
          final List<Map<String, Object?>> rowBackup = await database.query(
              'SELECT * FROM sessions WHERE id = ?', <Object?>['s1']);
          final List<Map<String, Object?>> logBackup = await database.query(
              'SELECT * FROM ${DVCapture.logTable} WHERE record_key = ?',
              <Object?>[jsonEncode('s1')]);
          final DVPrivacy privacy = privacyOver(DVRetention.indefinite);
          await privacy.ensureSchema();
          await privacy.erase(subject: 'u1', reason: 'request');

          // The restore: the row and the log entries it had come back.
          for (final Map<String, Object?> row in rowBackup) {
            final List<String> cols = <String>[
              for (final String c in row.keys)
                if (sessions.columns.contains(c) ||
                    c == DVRecordTable.versionColumn ||
                    c == DVRecordTable.deletedColumn)
                  c,
            ];
            await database.execute(
              'INSERT INTO sessions (${cols.join(', ')}) '
              'VALUES (${List<String>.filled(cols.length, '?').join(', ')})',
              <Object?>[for (final String c in cols) row[c]],
            );
          }
          for (final Map<String, Object?> entry in logBackup) {
            await database.execute(
              'UPDATE ${DVCapture.logTable} SET row_values = ?, purged = ? '
              'WHERE change_id = ?',
              <Object?>[entry['row_values'], entry['purged'], entry['change_id']],
            );
          }
          expect(await logText(), contains('10.1.0.1'),
              reason: 'precondition: the restore put the value back');

          await privacy.replayErasures();

          expect(await sessions.read('s1', withDeleted: true), isNull);
          expect(await logText(), isNot(contains('10.1.0.1')));
          await consumer.deliverAll();
          expect(await warehoused(), isEmpty);
        });

        test("erasing a device's offline copy over a captured table purges "
            'the log', () async {
          // A table of its own, outside the walk, so only the adapter reaches it.
          final DVRecordTable notes = DVRecordTable(
            table: 'notes',
            key: 'id',
            columns: const <String>['id', 'user_id', 'ip', 'created_at'],
            capture: capture,
            database: database,
          );
          final DVOfflineStore store = DVOfflineStore(
            table: notes,
            policy: const DVOffline(strategy: DVConflict.lastWriteWins),
            persistent: true,
          );
          await store.ensureSchema();
          await store.write(<String, Object?>{
            'id': 'n1',
            'user_id': 'u1',
            'ip': '10.1.0.1',
            'created_at': now.toIso8601String(),
          });
          await consumer.deliverAll();
          expect(await logText(), contains('10.1.0.1'),
              reason: 'precondition: the local write was captured');
          final DVPrivacy privacy = privacyOver(
            DVRetention.indefinite,
            adapters: <DVPrivacyAdapter>[
              DVOfflineStorePrivacyAdapter(
                  store: store, subject: const DVSubject.field('user_id')),
            ],
          );
          await privacy.ensureSchema();

          final DVErasureResult result =
              await privacy.erase(subject: 'u1', reason: 'request');
          expect(result.complete, isTrue);

          expect(await notes.read('n1', withDeleted: true), isNull);
          expect(await logText(), isNot(contains('10.1.0.1')));
          await consumer.deliverAll();
          expect(await warehoused('notes'), isEmpty);
        });
      });

      test('delivery runs on the job layer and a refused batch is retried',
          () async {
        final DVInMemoryQueueAdapter queue = DVInMemoryQueueAdapter();
        const DVQueues queues = DVQueues();
        queues.useAdapter(queue);
        final _RecordingSink sink = _RecordingSink()..refuseWrites = true;
        final DVCaptureConsumer consumer = capture.consumer('wh', sink: sink);
        capture.registerJobs(queues);
        await orders.write(_order('o1'));

        await capture.dispatchDelivery('wh', queues: queues);
        expect(await queues.work(), 0);
        expect(await queues.pending(), hasLength(1),
            reason: 'the refused batch goes back on the queue');
        sink.refuseWrites = false;
        expect(await queues.work(), 1);
        expect(sink.changes.single.key, 'o1');
        expect(await consumer.checkpoint(), await capture.head());
      });
    });
  }

  group('the reference warehouse sink, on sqlite', () {
    late DVDatabaseAdapter database;
    late DVDatabaseAdapter warehouseDb;
    late DVCapture capture;
    late DVRecordTable orders;
    late DVWarehouseSink warehouse;
    late DVCaptureConsumer consumer;

    Future<List<Map<String, Object?>>> rows() => warehouseDb.query(
          'SELECT * FROM orders ORDER BY _dv_key',
        );

    setUp(() async {
      database = SqliteDVDatabaseAdapter.memory();
      warehouseDb = SqliteDVDatabaseAdapter.memory();
      capture = DVCapture(database: database, retention: const Duration(days: 7));
      await capture.ensureSchema();
      orders = _orders(database, capture);
      await orders.ensureSchema();
      warehouse = DVWarehouseSink(database: warehouseDb);
      consumer = capture.consumer('wh', sink: warehouse);
    });

    test('updates to one row committed out of order leave the newest version',
        () async {
      final DVRecord v1 = (await orders.write(_order('o1'))).record;
      await consumer.deliverOnce();

      final Completer<void> firstWritten = Completer<void>();
      final Completer<void> secondCommitted = Completer<void>();
      final Future<void> slow = DVTransactionRunner()<void>((DVContext _) async {
        await orders.write(_order('o1', quantity: 2), base: v1);
        firstWritten.complete();
        await secondCommitted.future;
      }, isolated: true);
      await firstWritten.future;
      final DVRecord v2 = (await orders.read('o1'))!;
      await DVTransactionRunner()<void>((DVContext _) async {
        await orders.write(_order('o1', quantity: 3), base: v2);
      }, isolated: true);
      secondCommitted.complete();
      await slow;

      final List<DVCapturedChange> log = await capture.changes();
      expect(log.where((DVCapturedChange c) => c.key == 'o1').map((DVCapturedChange c) => c.version),
          <int>[1, 3, 2],
          reason: 'the fixture must really commit the newer write first');

      await consumer.deliverOnce();
      final List<Map<String, Object?>> stored = await rows();
      expect(stored.single['quantity'], 3);
      expect(stored.single['_dv_version'], 3);
    });

    test('redelivery is idempotent, deletes remove rows, and a key reused '
        'after a delete is a new row', () async {
      await orders.write(_order('o1'));
      await orders.write(_order('o2'));
      await consumer.deliverOnce();
      await capture.consumer('again', sink: warehouse).deliverOnce();
      expect(await rows(), hasLength(2));

      await orders.delete('o1');
      await consumer.deliverOnce();
      expect((await rows()).map((Map<String, Object?> r) => r['_dv_key']),
          <Object?>['o2']);

      await orders.write(_order('o1', quantity: 7));
      await consumer.deliverOnce();
      expect(await rows(), hasLength(2));
      expect(
          (await rows()).firstWhere((Map<String, Object?> r) => r['_dv_key'] == 'o1')['quantity'],
          7);

      // A worker still holding the old delete delivers it on its own, after
      // the key was used again. It belongs to the earlier record.
      final DVCapturedChange oldDelete = (await capture.changes()).firstWhere(
          (DVCapturedChange c) =>
              c.key == 'o1' && c.operation == DVCaptureOp.delete);
      await warehouse.write(DVCaptureBatch(
        consumer: 'stale',
        changes: <DVCapturedChange>[oldDelete],
        atLeastOnce: false,
      ));
      expect(
          (await rows()).firstWhere((Map<String, Object?> r) => r['_dv_key'] == 'o1')['quantity'],
          7,
          reason: 'a delete of the earlier record must not remove the new one');

      // A consumer replaying from the start would re-send the first insert and
      // the delete after the reinsertion; neither may win.
      await capture.consumer('replay', sink: warehouse).deliverOnce();
      expect(
          (await rows()).firstWhere((Map<String, Object?> r) => r['_dv_key'] == 'o1')['quantity'],
          7);
    });

    test('the sensitive column never exists at the destination', () async {
      await orders.write(_order('o1', email: 'ada@example.com'));
      await consumer.deliverOnce();
      final String stored = jsonEncode(await rows());
      expect(stored, isNot(contains('ada@example.com')));
      expect((await rows()).single.containsKey('customer_email'), isFalse);
    });

    test('schema follows the source: a field is added, then emptied',
        () async {
      await orders.write(_order('o1'));
      await consumer.deliverOnce();
      await _addChannel('sqlite', database);
      await _orders(database, capture, columns: const <String>[
        'id', 'reference', 'quantity', 'customer_email', 'channel',
      ]).write(<String, Object?>{..._order('o2'), 'channel': 'web'});
      await consumer.deliverOnce();
      expect((await rows()).last['channel'], 'web');

      await _orders(database, capture,
              columns: const <String>['id', 'quantity', 'customer_email', 'channel'])
          .write(<String, Object?>{
        'id': 'o3',
        'quantity': 1,
        'customer_email': 'x@example.com',
        'channel': 'app',
      });
      await consumer.deliverOnce();
      // The destination is written through the record operations, which a
      // document store implements too and which have no column to drop: the
      // contracted field's values leave every copy instead.
      expect(
        (await rows()).map((Map<String, Object?> r) => r['reference']),
        everyElement(isNull),
      );

      // Redelivering the schema changes after a crash must not wedge delivery.
      await capture.consumer('replay', sink: warehouse).deliverOnce();
    });

    test('an erasure removes the row and an in-flight batch cannot bring it '
        'back', () async {
      final DVRecordTable users = DVRecordTable(
        table: 'users',
        key: 'id',
        columns: const <String>['id', 'email'],
        capture: capture,
        database: database,
      );
      await users.ensureSchema();
      final DVRecord u1 = (await users
              .write(<String, Object?>{'id': 'u1', 'email': 'ada@example.com'}))
          .record;
      await users.write(<String, Object?>{'id': 'u1', 'email': 'ada@new.example'},
          base: u1);
      final List<DVCapturedChange> inFlight = await capture.changes();

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
        database: database,
        signingKey: List<int>.filled(32, 7),
        adapters: <DVPrivacyAdapter>[
          DVCapturePrivacyAdapter(capture: capture, sinks: <DVCaptureSink>[warehouse]),
        ],
      );
      await privacy.ensureSchema();
      await consumer.deliverOnce();
      expect(await warehouseDb.query('SELECT * FROM users'), hasLength(1));

      await privacy.erase(subject: 'u1', reason: 'request');
      expect(await warehouseDb.query('SELECT * FROM users'), isEmpty);

      // A worker that read the batch before the erasure delivers it after.
      await warehouse.write(DVCaptureBatch(
        consumer: 'stale',
        changes: inFlight.where((DVCapturedChange c) => c.model == 'users').toList(),
        atLeastOnce: false,
      ));
      expect(await warehouseDb.query('SELECT * FROM users'), isEmpty);
    });

    test('a completed backfill sweeps rows the source no longer holds',
        () async {
      await orders.write(_order('o1'));
      await orders.write(_order('o2'));
      await consumer.deliverOnce();
      // The warehouse misses a delete: it happens through a table with no capture.
      await DVRecordTable(
        table: 'orders',
        key: 'id',
        columns: const <String>['id', 'reference', 'quantity', 'customer_email'],
        sensitive: const <String>{'customer_email'},
        database: database,
      ).delete('o1');

      await consumer.backfill(orders);
      expect((await rows()).map((Map<String, Object?> r) => r['_dv_key']),
          <Object?>['o2']);
    });
  });
}

/// The source table gains the column a wider model declares. The in-memory
/// adapter holds rows as maps and needs nothing; SQLite needs the column.
Future<void> _addChannel(String adapter, DVDatabaseAdapter database) async {
  if (adapter == 'sqlite') {
    await database.execute('ALTER TABLE orders ADD COLUMN channel');
  }
}

class _UnreachableSink implements DVCaptureSink {
  @override
  String get name => 'unreachable';
  @override
  bool get deduplicates => true;
  @override
  Future<void> write(DVCaptureBatch batch) async {}
  @override
  Future<void> evolve(DVCaptureSchemaChange change) async {}
  @override
  Future<void> erase(List<DVCapturedChange> changes) async =>
      throw StateError('warehouse unreachable');
  @override
  Future<void> backfillComplete(String model, int throughSequence,
          {String? tenant}) async {}
}
