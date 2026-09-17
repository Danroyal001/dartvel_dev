import '../dartvel_client/dartvel_client.dart';

Future<void> capture(DVDatabaseAdapter app, DVDatabaseAdapter warehouse) async {
  // docs:start capture-log
  final DVCapture log = DVCapture(
    database: app,
    retention: const Duration(days: 7), // a consumer further behind must backfill
  );
  await log.ensureSchema();

  final DVRecordTable orders = DVRecordTable(
    table: 'orders',
    key: 'id',
    columns: <String>['id', 'reference', 'total', 'customer_email'],
    sensitive: <String>{'customer_email'}, // named in the log, never stored
    capture: log,
    database: app,
  );
  await orders.ensureSchema();

  // The write and its change land together.
  await orders.write(<String, Object?>{
    'id': 'o1',
    'reference': 'R-1',
    'total': 4200,
    'customer_email': 'ada@example.com',
  });
  // docs:end

  // docs:start capture-consumer
  final DVCaptureConsumer toWarehouse = log.consumer(
    'warehouse',
    sink: DVWarehouseSink(database: warehouse),
    models: <String>{'orders'},
    lagThreshold: const Duration(minutes: 10),
  );

  // Copy what is already there, then follow new changes in order.
  await toWarehouse.backfill(orders);
  final DVCaptureDelivery delivery = await toWarehouse.deliverAll();

  final DVCaptureLag lag = await toWarehouse.lag();
  DV.log('${delivery.delivered} delivered, ${lag.changes} waiting, '
      'oldest ${lag.age.inSeconds}s old');
  // docs:end
}

Future<void> captureJobs(DVCapture log) async {
  // docs:start capture-jobs
  log.registerJobs(DV.Jobs);
  await log.dispatchDelivery('warehouse', queue: 'capture');
  // docs:end
}
