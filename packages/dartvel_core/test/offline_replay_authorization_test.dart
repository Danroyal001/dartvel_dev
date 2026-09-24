// A device's queued writes are somebody's writes, and the server asks.
//
// Replay is the one write path where the server is handed a mutation that
// nothing on the server decided to make: it was made on a device, possibly
// days ago, possibly by a person whose access has since been withdrawn, and
// it names its own table and key. Applying it because it arrived is the same
// as having no authorization on the route that carries it.
//
// Two holes this covers, both silent -- the write lands and nothing says so:
//
//  - `validate` was asked for a write and not for a delete, so a queued
//    delete for any key in an offline table was applied unchecked.
//  - There was no authorization hook at all, so `Model.offlineRemote` -- the
//    server side of replay, generated for a model that declares `offline:`
//    -- applied a device's writes with, at most, a synchronous look at the
//    values. It could not ask the model's policy, because policy is async
//    and takes the stored record, not a map.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

DVRecordTable _table(DVDatabaseAdapter database) => DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'reference', 'quantity'],
      database: database,
    );

DVMutation _write(String key, {String id = 'm1', int quantity = 2}) =>
    DVMutation(
      mutationId: id,
      sequence: 1,
      table: 'orders',
      op: DVMutation.opWrite,
      key: key,
      values: <String, Object?>{
        'id': key,
        'reference': 'R-1',
        'quantity': quantity,
      },
      deviceTime: DateTime.utc(2026),
      correctedTime: DateTime.utc(2026),
    );

DVMutation _delete(String key, {String id = 'd1'}) => DVMutation(
      mutationId: id,
      sequence: 2,
      table: 'orders',
      op: DVMutation.opDelete,
      key: key,
      values: const <String, Object?>{},
      deviceTime: DateTime.utc(2026),
      correctedTime: DateTime.utc(2026),
    );

void main() {
  late DVRecordTable server;
  late MemoryDVDatabaseAdapter database;

  setUp(() async {
    database = MemoryDVDatabaseAdapter();
    server = _table(database);
    await server.ensureSchema();
  });

  Future<DVRecordTableRemote> remote({
    Future<bool> Function(DVMutation mutation)? authorize,
    bool Function(Map<String, Object?> values)? validate,
  }) async {
    final DVRecordTableRemote built = DVRecordTableRemote(
      server,
      strategy: DVConflict.lastWriteWins,
      authorize: authorize,
      validate: validate,
    );
    await built.ensureSchema();
    return built;
  }

  test('a write nobody authorised is refused, and nothing is written',
      () async {
    final DVRecordTableRemote server_ =
        await remote(authorize: (DVMutation _) async => false);

    final DVRemoteOutcome outcome = await server_.apply(_write('o1'));

    expect(outcome.isRejected, isTrue);
    expect(await server.read('o1'), isNull);
  });

  test('a delete nobody authorised is refused, and the row stays', () async {
    await server.write(<String, Object?>{
      'id': 'o1',
      'reference': 'R-1',
      'quantity': 2,
    });
    final DVRecordTableRemote server_ =
        await remote(authorize: (DVMutation _) async => false);

    final DVRemoteOutcome outcome = await server_.apply(_delete('o1'));

    expect(outcome.isRejected, isTrue);
    expect(await server.read('o1'), isNotNull);
  });

  test('a delete is put to validate too, which it never used to be', () async {
    // The hole this covers: validate was asked on the write path only, so a
    // queued delete for any key in the table was applied unchecked.
    await server.write(<String, Object?>{
      'id': 'o1',
      'reference': 'R-1',
      'quantity': 2,
    });
    final DVRecordTableRemote server_ =
        await remote(validate: (Map<String, Object?> _) => false);

    final DVRemoteOutcome outcome = await server_.apply(_delete('o1'));

    expect(outcome.isRejected, isTrue);
    expect(await server.read('o1'), isNotNull);
  });

  test('the authorised write lands, so the refusals above mean something',
      () async {
    final DVRecordTableRemote server_ =
        await remote(authorize: (DVMutation _) async => true);

    final DVRemoteOutcome outcome = await server_.apply(_write('o1'));

    expect(outcome.isRejected, isFalse);
    expect(await server.read('o1'), isNotNull);
  });

  test('a refusal is remembered, so a resend is not a second chance',
      () async {
    // Replay resends a mutation whose acknowledgement was lost. A device
    // that resent one it had been refused, and got a different answer
    // because the policy had since changed, would apply a write the server
    // already said no to.
    bool allow = false;
    final DVRecordTableRemote server_ =
        await remote(authorize: (DVMutation _) async => allow);

    expect((await server_.apply(_write('o1'))).isRejected, isTrue);
    allow = true;
    expect((await server_.apply(_write('o1'))).isRejected, isTrue);
    expect(await server.read('o1'), isNull);
  });

  test('a policy that throws refuses rather than admitting', () async {
    // Default deny. A check that cannot reach its answer is not a yes.
    final DVRecordTableRemote server_ = await remote(
      authorize: (DVMutation _) async => throw StateError('no policy'),
    );

    final DVRemoteOutcome outcome = await server_.apply(_write('o1'));

    expect(outcome.isRejected, isTrue);
    expect(await server.read('o1'), isNull);
  });
}
