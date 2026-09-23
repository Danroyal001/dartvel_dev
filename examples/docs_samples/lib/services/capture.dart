import '../dartvel_client/dartvel_client.dart';

// docs:start capture-log
// One log for the process, configured where the database is. A model says it
// is captured and nothing else changes: saving a record is what records the
// change, and a sensitive field is named in it and never carried.
//
//   @DVModel(capture: true)
//   class _Order {
//     final String id;
//     final int total;
//     @DVModel.sensitiveField()
//     final String customerEmail;
//     ...
//   }
Future<void> captureWrites(DVDatabaseAdapter app) async {
  final DVCapture log = DVCapture(
    database: app,
    // A consumer further behind than this has to backfill.
    retention: const Duration(days: 7),
  );
  await log.ensureSchema();
  DVCapture.configure(log);
}

// And then an ordinary save, which is the whole of it.
Future<void> takeOrder() => Shipment(
      id: 'o1',
      reference: 'R-1',
      total: 4200,
      customerEmail: 'ada@example.com',
    ).save();
// docs:end

Future<void> consume(DVCapture log, DVDatabaseAdapter warehouse) async {
  // docs:start capture-consumer
  final DVCaptureConsumer toWarehouse = log.consumer(
    'warehouse',
    sink: DVWarehouseSink(database: warehouse),
    models: <String>{'shipments'},
    lagThreshold: const Duration(minutes: 10),
  );

  // Copy what is already there, then follow new changes in order.
  await Shipment.backfillTo(toWarehouse);
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
