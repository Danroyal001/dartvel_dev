// The one route that takes writes a device made while nobody was watching.
//
// Everything about it is somebody else's input: the model it names, the key,
// the values, how many of them there are. The route is authenticated by the
// generated backend like every other, and the model's own policy decides
// each mutation -- but before either runs, this is what decides whether the
// request is a request at all.
//
// The failures it is here for are the quiet ones. A model nobody declared
// offline is an arbitrary-table write primitive. A batch with no bound is a
// way to hold a connection open with somebody else's database. A key that is
// not a scalar reaches the table as a string nobody meant. And an outcome
// answered whole hands back the columns the table calls sensitive.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

DVRecordTable _orders(DVDatabaseAdapter database) => DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: const <String>['id', 'reference', 'cardNumber'],
      sensitive: const <String>{'cardNumber'},
      database: database,
    );

Map<String, Object?> _mutation({
  String id = 'm-1',
  Object key = 'o1',
  String op = DVMutation.opWrite,
}) =>
    <String, Object?>{
      'mutationId': id,
      'sequence': 1,
      'table': 'orders',
      'op': op,
      'key': key,
      'values': <String, Object?>{
        'id': key,
        'reference': 'R-1',
        'cardNumber': '4111111111111111',
      },
      'deviceTime': DateTime.utc(2026).toIso8601String(),
      'correctedTime': DateTime.utc(2026).toIso8601String(),
    };

void main() {
  late MemoryDVDatabaseAdapter database;
  late DVRecordTable table;
  late Map<String, DVOfflineRemote> registry;

  setUp(() async {
    database = MemoryDVDatabaseAdapter();
    table = _orders(database);
    await table.ensureSchema();
    final DVRecordTableRemote remote = DVRecordTableRemote(
      table,
      strategy: DVConflict.lastWriteWins,
      authorize: (DVMutation _) async => true,
    );
    await remote.ensureSchema();
    registry = <String, DVOfflineRemote>{'Order': remote};
  });

  Future<DVOfflineReplayResult> replay(Object? body) =>
      DVOfflineReplay(registry).handle(body);

  test('a model nobody declared offline is refused, not written', () async {
    final DVOfflineReplayResult result = await replay(<String, Object?>{
      'model': 'Secrets',
      'mutations': <Object?>[_mutation()],
    });

    expect(result.status, 404);
    // Not "no such model", which would answer whether one exists.
    expect(result.message, isNot(contains('Secrets')));
  });

  test('a batch larger than the bound is refused whole', () async {
    final DVOfflineReplayResult result = await replay(<String, Object?>{
      'model': 'Order',
      'mutations': <Object?>[
        for (int i = 0; i < DVOfflineReplay.maxMutations + 1; i++)
          _mutation(id: 'm-$i', key: 'o$i'),
      ],
    });

    expect(result.status, 413);
    expect(await table.read('o0'), isNull,
        reason: 'a refused batch applies none of itself');
  });

  test('a key that is not a scalar is refused', () async {
    // It would reach the table as the string a Map interpolates to, which is
    // a key nobody meant and one no other writer will ever match.
    final DVOfflineReplayResult result = await replay(<String, Object?>{
      'model': 'Order',
      'mutations': <Object?>[
        _mutation(key: <String, Object?>{'nested': 1}),
      ],
    });

    expect(result.status, 400);
  });

  test('a body that is not a replay request is refused, not thrown at',
      () async {
    for (final Object? body in <Object?>[
      null,
      'a string',
      <Object?>[],
      <String, Object?>{'model': 'Order'},
      <String, Object?>{'mutations': <Object?>[]},
      <String, Object?>{'model': 'Order', 'mutations': 'not a list'},
      <String, Object?>{'model': 'Order', 'mutations': <Object?>['not a map']},
      <String, Object?>{
        'model': 'Order',
        'mutations': <Object?>[<String, Object?>{'mutationId': 'only this'}],
      },
    ]) {
      final DVOfflineReplayResult result = await replay(body);
      expect(result.status, 400, reason: 'for $body');
    }
  });

  test('what it applies, it answers for, without the sensitive column',
      () async {
    final DVOfflineReplayResult result = await replay(<String, Object?>{
      'model': 'Order',
      'mutations': <Object?>[_mutation()],
    });

    expect(result.status, 200);
    final List<Object?> outcomes = result.body['outcomes']! as List<Object?>;
    expect(outcomes, hasLength(1));
    final Map<String, Object?> record =
        (outcomes.single! as Map<String, Object?>)['record']!
            as Map<String, Object?>;
    final Map<String, Object?> values =
        record['values']! as Map<String, Object?>;

    expect(values['reference'], 'R-1');
    expect(values.containsKey('cardNumber'), isFalse);
    // And the write did land, so the absence above is filtering rather than
    // a refusal.
    expect((await table.read('o1'))!.values['cardNumber'],
        '4111111111111111');
  });

  test('each outcome is answered against its own mutation id', () async {
    final DVOfflineReplayResult result = await replay(<String, Object?>{
      'model': 'Order',
      'mutations': <Object?>[
        _mutation(id: 'm-1', key: 'o1'),
        _mutation(id: 'm-2', key: 'o2'),
      ],
    });

    final List<Object?> outcomes = result.body['outcomes']! as List<Object?>;
    expect(
      outcomes
          .map((Object? o) => (o! as Map<String, Object?>)['mutationId'])
          .toList(),
      <String>['m-1', 'm-2'],
    );
  });

  test('one malformed mutation refuses the batch and applies none of it',
      () async {
    // Order is the whole point of a queue, so the batch is decoded before
    // any of it is applied. Applying the ones before the bad entry and
    // stopping there would leave the device's queue and the server's table
    // disagreeing about a write that half happened.
    final DVOfflineReplayResult result = await replay(<String, Object?>{
      'model': 'Order',
      'mutations': <Object?>[
        _mutation(id: 'm-1', key: 'o1'),
        <String, Object?>{..._mutation(id: 'm-2', key: 'o2'), 'op': 'nonsense'},
        _mutation(id: 'm-3', key: 'o3'),
      ],
    });

    expect(result.status, 400);
    expect(await table.read('o1'), isNull,
        reason: 'the one before the bad entry must not have landed either');
    expect(await table.read('o3'), isNull);
  });
}
