// Change capture on a model, without building the machinery by hand.
//
// A generated model already builds its own DVRecordTable -- its table, key,
// columns, sensitive fields, history and tenant scope all come from @DVModel
// -- and that table has always taken a capture log. There was no way to hand
// it one, so the docs taught a reader to build a DVRecordTable themselves,
// listing the columns of a model they had already declared, and to write rows
// as raw maps. Two sources of truth for one model's shape, and the second one
// drifts.
//
// A capture log is configured once, like the database, and a model says it is
// captured. Nothing else changes: saving a record is what records the change.
import 'package:dartvel_core/dartvel.dart';
// The record layer, which an application does not name and a test of it
// does.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

void main() {
  late MemoryDVDatabaseAdapter database;

  setUp(() async {
    database = MemoryDVDatabaseAdapter();
    const DVDatabase().configure(database);
  });

  tearDown(() {
    DVCapture.unconfigure();
    const DVDatabase().unconfigure();
  });

  test('a configured log is what a captured model writes to', () async {
    final DVCapture log = DVCapture(
      database: database,
      retention: const Duration(days: 7),
    );
    await log.ensureSchema();
    DVCapture.configure(log);

    expect(DVCapture.configured, same(log),
        reason: 'a model that is captured has a log to name');

    // The table a generated model builds for itself, handed the configured
    // log the way the generator will hand it one.
    final DVRecordTable orders = DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'total'],
      capture: DVCapture.configured,
    );
    await orders.ensureSchema();

    await orders.write(<String, Object?>{'id': 'o1', 'total': 4200});

    final List<DVCapturedChange> changes = await log.changes(limit: 10);
    expect(changes, hasLength(1));
    expect(changes.single.model, 'orders');
  });

  // The server configures the log from pubspec.yaml, and a model is also
  // saved from processes the server did not start: a worker, a script, a
  // desktop app sharing the database. Each of those used to see no log and
  // record nothing, so a change made there never reached a destination and
  // nothing said so. A captured model now records to a log in the database
  // it is written to, which the server delivers from.
  test('with no log configured, a captured model records to its database',
      () async {
    final DVRecordTable orders = DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'total'],
      capture: DVCapture.configured,
    );
    await orders.ensureSchema();

    await orders.write(<String, Object?>{'id': 'o1', 'total': 4200});
    expect(await orders.read('o1'), isNotNull);

    // The server's own log over the same database reads what was recorded.
    final DVCapture server = DVCapture(
      database: database,
      retention: const Duration(days: 30),
    );
    final List<DVCapturedChange> changes = await server.changes();
    expect(changes.single.model, 'orders');
    expect(changes.single.key, 'o1');
  });

  test('a process with no database has no log to record to', () {
    const DVDatabase().unconfigure();
    expect(DVCapture.configured, isNull);
  });
}
