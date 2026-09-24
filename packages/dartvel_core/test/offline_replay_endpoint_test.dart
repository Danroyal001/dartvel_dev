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

const DVStudioModelSpec _invoice = DVStudioModelSpec(
  model: 'Invoice',
  table: 'invoices',
  key: 'id',
  module: 'billing',
  data: DVModuleData('billing'),
  offline: DVConflict.lastWriteWins,
  fields: <DVStudioFieldSpec>[DVStudioFieldSpec(name: 'id', type: 'String')],
);

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

  group('the registry the generated backend builds', () {
    DVStudioModelSpec spec({DVConflict? offline, bool tenantScoped = false}) =>
        DVStudioModelSpec(
          model: 'Order',
          table: 'orders',
          key: 'id',
          tenantScoped: tenantScoped,
          offline: offline,
          fields: const <DVStudioFieldSpec>[
            DVStudioFieldSpec(name: 'id', type: 'String'),
            DVStudioFieldSpec(name: 'reference', type: 'String'),
            DVStudioFieldSpec(
                name: 'cardNumber', type: 'String', sensitive: true),
          ],
        );

    test('holds only the models that said they work offline', () {
      final DVOfflineReplay replay = DVOfflineReplay.forSpecs(
        <DVStudioModelSpec>[
          spec(offline: DVConflict.lastWriteWins),
          DVStudioModelSpec(
            model: 'Ledger',
            table: 'ledgers',
            key: 'id',
            fields: const <DVStudioFieldSpec>[
              DVStudioFieldSpec(name: 'id', type: 'String'),
            ],
          ),
        ],
        database: database,
      );

      expect(replay.remotes.keys, <String>['Order']);
    });

    test('a remote knows which columns it must not echo back', () {
      final DVOfflineReplay replay = DVOfflineReplay.forSpecs(
        <DVStudioModelSpec>[spec(offline: DVConflict.lastWriteWins)],
        database: database,
      );

      expect(replay.remotes['Order']!.sensitiveColumns, <String>{'cardNumber'});
    });

    test('a tenant-scoped model keeps its scope on the server too', () {
      // The same hole the generated device store had: without it a device
      // signed into one tenant replays onto a table with no tenant filter.
      final DVOfflineReplay replay = DVOfflineReplay.forSpecs(
        <DVStudioModelSpec>[
          spec(offline: DVConflict.lastWriteWins, tenantScoped: true),
        ],
        database: database,
      );

      final DVRecordTableRemote remote =
          replay.remotes['Order']! as DVRecordTableRemote;
      expect(remote.table.scope, isNotNull);
      expect(remote.table.scope!.column, dvTenantColumn);
    });

    test('a policy that throws refuses, even asynchronously', () async {
      // The analyzer found this one: returning the future from inside the
      // try let it escape, so a policy that threw after the first await was
      // an error on the way out of replay rather than a refusal.
      final DVOfflineReplay replay = DVOfflineReplay.forSpecs(
        <DVStudioModelSpec>[spec(offline: DVConflict.lastWriteWins)],
        database: database,
      );
      await (replay.remotes['Order']! as DVRecordTableRemote).ensureSchema();

      // No policy is registered at all, which is the reachable form of the
      // same thing: canAction answers false for an action nobody declared.
      final DVOfflineReplayResult result =
          await DVOfflineReplay(replay.remotes).handle(<String, Object?>{
        'model': 'Order',
        'mutations': <Object?>[_mutation()],
      });

      final Map<String, Object?> outcome =
          (result.body['outcomes']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(outcome['rejection'], 'refused by authorization');
    });

    test('under a schema per tenant the write goes to the tenant schema', () {
      // The hole dvTenantTable exists to close, in the one place that takes
      // writes from a device: the replay built its table from the model's
      // bare name, so a tenant whose separation is a schema replayed onto
      // the shared table and every row landed where nobody was looking.
      dvRegisterTenantScopedTables(<String>{'orders'});
      const DVTenants().configure(isolation: DVTenantIsolation.schemaPerTenant);
      addTearDown(
        () => const DVTenants().configure(
          isolation: DVTenantIsolation.sharedDatabase,
        ),
      );

      final DVRecordTableRemote remote = const DVTenants().withTenant(
        'acme',
        () =>
            DVOfflineReplay.forSpecs(
                  <DVStudioModelSpec>[spec(offline: DVConflict.lastWriteWins)],
                  database: database,
                ).remotes['Order']!
                as DVRecordTableRemote,
      );

      expect(remote.table.table, 'dartvel_acme.orders');
    });

    test('a module model is replayed onto the table its mount gave it', () {
      // A module mounted with its own schema names its tables through the
      // mount. Studio reads that name; a replay that wrote the bare one
      // would be writing to a table the module never reads, and the module
      // would come back up to find the device's week of work missing.
      dvModuleRegistry.resetForTesting();
      addTearDown(dvModuleRegistry.resetForTesting);
      dvModuleRegistry.register(
        id: 'billing',
        mountPath: '/billing',
        config: const <String, Object?>{
          'deployment': 'embedded',
          'data': 'schema-isolated',
        },
      );

      final DVOfflineReplay replay = DVOfflineReplay.forSpecs(
        <DVStudioModelSpec>[_invoice],
        database: database,
      );

      final DVRecordTableRemote remote =
          replay.remotes['billing.Invoice']! as DVRecordTableRemote;
      expect(remote.table.table, 'billing_invoices');
    });

    test('a module that owns its database is replayed into that one', () {
      // Not the application's. A module mounted database-isolated keeps its
      // rows somewhere else entirely, and a replay that used the adapter the
      // route resolved would create the module's table in the parent and
      // write a device's queue into it.
      dvModuleRegistry.resetForTesting();
      addTearDown(dvModuleRegistry.resetForTesting);
      final MemoryDVDatabaseAdapter own = MemoryDVDatabaseAdapter();
      dvModuleRegistry.register(
        id: 'billing',
        mountPath: '/billing',
        config: const <String, Object?>{'data': 'database-isolated'},
      ).useDatabase(own);

      final DVOfflineReplay replay = DVOfflineReplay.forSpecs(
        <DVStudioModelSpec>[_invoice],
        database: database,
      );

      final DVRecordTableRemote remote =
          replay.remotes['billing.Invoice']! as DVRecordTableRemote;
      expect(identical(remote.table.database, own), isTrue);
    });

    test('a remote module is not in the registry at all', () {
      // Its deployment owns its data and this process cannot reach it.
      // Resolving its table throws rather than guessing, and a registry that
      // let that escape would answer the whole batch with a server error
      // instead of refusing the one model it cannot apply.
      dvModuleRegistry.resetForTesting();
      addTearDown(dvModuleRegistry.resetForTesting);
      dvModuleRegistry.register(
        id: 'billing',
        mountPath: '/billing',
        config: const <String, Object?>{'data': 'remote'},
      );

      final DVOfflineReplay replay = DVOfflineReplay.forSpecs(
        <DVStudioModelSpec>[_invoice],
        database: database,
      );

      expect(replay.remotes, isEmpty);
    });

    test('every replayed column has a declared type', () {
      // A record table with no types makes untyped columns when it creates
      // the table, and an untyped column in SQLite takes whatever it is
      // given. The generated model declares every field column TEXT and
      // Studio writes the same table, so the replay route has to agree with
      // both or it is writing a different shape into the same rows.
      final DVOfflineReplay replay = DVOfflineReplay.forSpecs(
        <DVStudioModelSpec>[
          spec(offline: DVConflict.lastWriteWins, tenantScoped: true),
        ],
        database: database,
      );

      final DVRecordTableRemote remote =
          replay.remotes['Order']! as DVRecordTableRemote;
      expect(remote.table.types, isNotNull);
      expect(remote.table.types!.keys, containsAll(remote.table.columns));
    });

    test('nothing offline means an empty registry, not an open door', () {
      final DVOfflineReplay replay =
          DVOfflineReplay.forSpecs(<DVStudioModelSpec>[], database: database);

      expect(replay.remotes, isEmpty);
    });
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
