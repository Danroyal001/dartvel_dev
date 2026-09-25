// The change capture runtime: what the generated server runs from
// `dartvel.capture` so that `@DVModel(capture: true)` and the pubspec are all
// an application writes.
//
// Every test here drives the runtime the way the generated server does --
// configure from the parsed declaration and the data models' specs, start,
// tick -- and checks what arrives at the destination, not which calls were
// made. The destination is DVMemoryRecordEngine, which runs no SQL, so
// nothing here depends on a destination speaking it.
import 'package:dartvel_core/dartvel.dart';
// The runtime and the record layer, which an application does not name and
// the framework's tests do.
import 'package:dartvel_core/framework.dart';
// The metrics registry, to read the lag gauges back.
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

const DVStudioModelSpec _orderSpec = DVStudioModelSpec(
  model: 'Order',
  table: 'orders',
  key: 'id',
  capture: true,
  fields: <DVStudioFieldSpec>[
    DVStudioFieldSpec(name: 'id', type: 'String'),
    DVStudioFieldSpec(name: 'total', type: 'int'),
    DVStudioFieldSpec(name: 'email', type: 'String', sensitive: true),
  ],
);

const DVStudioModelSpec _refundSpec = DVStudioModelSpec(
  model: 'Refund',
  table: 'refunds',
  key: 'id',
  capture: true,
  fields: <DVStudioFieldSpec>[
    DVStudioFieldSpec(name: 'id', type: 'String'),
    DVStudioFieldSpec(name: 'amount', type: 'int'),
  ],
);

/// A generated data model's own table, as its save() builds it.
DVRecordTable _modelTable(DVStudioModelSpec spec) => DVRecordTable(
      table: spec.table,
      key: spec.key,
      columns: <String>[for (final DVStudioFieldSpec f in spec.fields) f.name],
      sensitive: <String>{
        for (final DVStudioFieldSpec f in spec.fields)
          if (f.sensitive) f.name,
      },
      capture: DVCapture.configured,
    );

/// A destination that can be made to refuse, the way one that is down does.
class _Flaky extends DVMemoryRecordEngine {
  bool down = false;

  @override
  Future<void> insert(String collection, Map<String, Object?> record) {
    if (down) throw StateError('warehouse unreachable');
    return super.insert(collection, record);
  }
}

DVCaptureConfig _config(Map<String, Object?> destinations,
        {String retention = '7d'}) =>
    DVCaptureConfig.parse(<String, Object?>{
      'retention': retention,
      'destinations': destinations,
    })!;

void main() {
  late MemoryDVDatabaseAdapter app;
  late _Flaky warehouse;
  late DateTime now;
  const DVQueues queues = DVQueues();

  setUp(() async {
    app = MemoryDVDatabaseAdapter();
    const DVDatabase().configure(app);
    warehouse = _Flaky();
    now = DateTime.now().toUtc();
    queues.useAdapter(DVInMemoryQueueAdapter());
    for (final DVStudioModelSpec spec in <DVStudioModelSpec>[
      _orderSpec,
      _refundSpec,
    ]) {
      await DVRecordTable(
        table: spec.table,
        key: spec.key,
        columns: <String>[
          for (final DVStudioFieldSpec f in spec.fields) f.name,
        ],
        database: app,
      ).ensureSchema();
    }
  });

  tearDown(() {
    DVCaptureRuntime.resetForTest();
    DVPrivacyRuntime.resetForTest();
    const DVDatabase().unconfigure();
  });

  void configure(
    DVCaptureConfig config, {
    Map<String, String> secrets = const <String, String>{
      'WAREHOUSE_URL': 'memory://warehouse',
    },
  }) {
    DVCaptureRuntime.configure(
      config: config,
      database: app,
      models: const <DVStudioModelSpec>[_orderSpec, _refundSpec],
      secret: (String name) => secrets[name],
      open: (String connection) => switch (connection) {
        'memory://warehouse' => warehouse,
        _ => throw StateError('no destination at $connection'),
      },
      clock: () => now,
    );
  }

  Future<void> tick() => DVCaptureRuntime.tick(queues: queues, work: true);

  Future<List<Map<String, Object?>>> copies(String collection) =>
      warehouse.find(collection, orderBy: const <DVSort>[DVSort('_dv_key')]);

  test('a destination added to the pubspec is backfilled, then follows every '
      'write', () async {
    // Written before the destination existed.
    const DVDatabase().configure(app);
    await _modelTable(_orderSpec)
        .write(<String, Object?>{'id': 'o1', 'total': 10, 'email': 'a@x.test'});

    configure(_config(<String, Object?>{
      'warehouse': <String, Object?>{
        'type': 'database',
        'connection': 'WAREHOUSE_URL',
      },
    }));
    expect(await DVCaptureRuntime.start(queues: queues), isTrue);
    await tick();

    expect((await copies('orders')).map((Map<String, Object?> r) => r['_dv_key']),
        <Object?>['o1'],
        reason: 'history the destination missed arrives by backfill');

    await _modelTable(_orderSpec)
        .write(<String, Object?>{'id': 'o2', 'total': 20, 'email': 'b@x.test'});
    await tick();

    final List<Map<String, Object?>> rows = await copies('orders');
    expect(rows.map((Map<String, Object?> r) => r['_dv_key']),
        <Object?>['o1', 'o2']);
    expect(rows.every((Map<String, Object?> r) => !r.containsKey('email')),
        isTrue,
        reason: 'a sensitive field is named in a change and never carried');
  });

  test('the model a data model saves through records to the declared log',
      () async {
    configure(_config(<String, Object?>{}, retention: '30d'));
    await DVCaptureRuntime.start(queues: queues);

    expect(DVCapture.configured?.retention, const Duration(days: 30));
    await _modelTable(_refundSpec)
        .write(<String, Object?>{'id': 'r1', 'amount': 5});
    expect((await DVCapture.configured!.changes()).single.model, 'refunds');
  });

  test('a destination receives only the data models it names', () async {
    configure(_config(<String, Object?>{
      'warehouse': <String, Object?>{
        'type': 'database',
        'connection': 'WAREHOUSE_URL',
        'models': <Object?>['Refund'],
      },
    }));
    await DVCaptureRuntime.start(queues: queues);
    await _modelTable(_orderSpec)
        .write(<String, Object?>{'id': 'o1', 'total': 10, 'email': 'a@x.test'});
    await _modelTable(_refundSpec)
        .write(<String, Object?>{'id': 'r1', 'amount': 5});
    await tick();

    expect(await copies('refunds'), hasLength(1));
    expect(await copies('orders'), isEmpty);
  });

  test('a destination whose secret is not set is skipped, and the others are '
      'still delivered to', () async {
    configure(
      _config(<String, Object?>{
        'warehouse': <String, Object?>{
          'type': 'database',
          'connection': 'WAREHOUSE_URL',
        },
        'lake': <String, Object?>{
          'type': 'database',
          'connection': 'LAKE_URL',
        },
      }),
    );
    expect(DVCaptureRuntime.skipped, <String, String>{
      'lake': 'DV-CDC-009',
    });
    await DVCaptureRuntime.start(queues: queues);
    await _modelTable(_refundSpec)
        .write(<String, Object?>{'id': 'r1', 'amount': 5});
    await tick();

    expect(await copies('refunds'), hasLength(1));
  });

  test('a destination that refuses is retried on the queue and loses nothing',
      () async {
    configure(_config(<String, Object?>{
      'warehouse': <String, Object?>{
        'type': 'database',
        'connection': 'WAREHOUSE_URL',
      },
    }));
    await DVCaptureRuntime.start(queues: queues);
    await tick();
    warehouse.down = true;
    await _modelTable(_refundSpec)
        .write(<String, Object?>{'id': 'r1', 'amount': 5});
    await tick();
    expect(await copies('refunds'), isEmpty);

    warehouse.down = false;
    await tick();
    expect(await copies('refunds'), hasLength(1),
        reason: 'the refused batch is delivered once the destination is back');
  });

  test('lag is a metric, and past the threshold it is DV-CDC-003', () async {
    configure(_config(<String, Object?>{
      'warehouse': <String, Object?>{
        'type': 'database',
        'connection': 'WAREHOUSE_URL',
        'lagThreshold': '10m',
      },
    }));
    await DVCaptureRuntime.start(queues: queues);
    await tick();
    warehouse.down = true;
    await _modelTable(_refundSpec)
        .write(<String, Object?>{'id': 'r1', 'amount': 5});
    now = now.add(const Duration(minutes: 11));
    await tick();

    final DVCaptureLag lag = DVCaptureRuntime.lag['warehouse']!;
    expect(lag.changes, 1);
    expect(lag.codes, contains('DV-CDC-003'));
    expect(DVObservability.metrics.render(),
        contains('dv_capture_lag_changes{consumer="warehouse"} 1'));
  });

  test('an erasure reaches every destination at once', () async {
    configure(_config(<String, Object?>{
      'warehouse': <String, Object?>{
        'type': 'database',
        'connection': 'WAREHOUSE_URL',
      },
    }));
    await DVCaptureRuntime.start(queues: queues);
    final DVRecordTable orders = _modelTable(_orderSpec);
    await orders
        .write(<String, Object?>{'id': 'o1', 'total': 10, 'email': 'a@x.test'});
    await tick();
    expect(await copies('orders'), hasLength(1));

    DVPrivacyRuntime.configure(
      models: <DVPrivacyModel>[
        DVPrivacyModel(
          name: 'Order',
          table: orders,
          subject: DVSubject.self,
          retention: DVRetention.indefinite,
        ),
      ],
      database: app,
      signingKey: List<int>.filled(32, 7),
    );
    await DVPrivacyRuntime.current.ensureSchema();
    final DVErasureResult erased = await DVPrivacyRuntime.current
        .erase(subject: 'o1', reason: 'request');

    expect(erased.complete, isTrue, reason: '${erased.unreached}');
    expect(await copies('orders'), isEmpty,
        reason: 'the copy goes with the erasure, not at the next delivery');
  });
}
