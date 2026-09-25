// An offline data model syncs by itself.
//
// The runtime underneath was built and nothing ran it: replay was a call an
// application had to make, with a remote it had to construct, on a
// reconnect it had to notice. Each of those is a place a write made on a
// train is never sent. Every test here makes a write and then does nothing
// an application would have to remember -- the network comes back, the
// application starts again, the server answers -- and checks what the server
// ended up holding.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

const DVStudioModelSpec _orderSpec = DVStudioModelSpec(
  model: 'Order',
  table: 'orders',
  key: 'id',
  offline: DVConflict.lastWriteWins,
  fields: <DVStudioFieldSpec>[
    DVStudioFieldSpec(name: 'id', type: 'String'),
    DVStudioFieldSpec(name: 'reference', type: 'String'),
  ],
);

DVOfflineStore _device(DVDatabaseAdapter database) => DVOfflineStore(
      table: DVRecordTable(
        table: 'orders',
        key: 'id',
        columns: const <String>['id', 'reference'],
        database: database,
      ),
      policy: const DVOffline(strategy: DVConflict.lastWriteWins),
    );

/// The generated backend's replay route, in this process.
class _Server {
  final MemoryDVDatabaseAdapter database = MemoryDVDatabaseAdapter();
  final List<String> received = <String>[];
  bool down = false;

  Future<DVOfflineReply> send(Map<String, Object?> body) async {
    if (down) throw const SocketException('connection refused');
    for (final Object? m in body['mutations']! as List<Object?>) {
      received.add('${(m! as Map<String, Object?>)['mutationId']}');
    }
    final DVOfflineReplayResult result = await DVOfflineReplay.forSpecs(
      const <DVStudioModelSpec>[_orderSpec],
      database: database,
    ).handle(jsonDecode(jsonEncode(body)));
    return DVOfflineReply(
      result.status,
      jsonDecode(jsonEncode(<String, Object?>{
        'message': result.message,
        ...result.body,
      })) as Map<String, Object?>,
    );
  }

  Future<String?> reference(String id) async {
    final List<Map<String, Object?>> rows = await database
        .query('SELECT reference FROM orders WHERE id = ?', <Object?>[id]);
    return rows.isEmpty ? null : '${rows.single['reference']}';
  }
}

void main() {
  late _Server server;
  late StreamController<bool> network;
  late bool reachable;
  late MemoryDVDatabaseAdapter device;

  void install() {
    DVOfflineSync.install(
      database: () async => device,
      send: server.send,
      reachability: network.stream,
      canReachTheServer: () => reachable,
      firstRetry: const Duration(milliseconds: 20),
      maxRetry: const Duration(milliseconds: 80),
    );
  }

  setUp(() {
    server = _Server();
    network = StreamController<bool>.broadcast();
    reachable = true;
    device = MemoryDVDatabaseAdapter();
    const DVAuthAuthorization().registerAction(
        'Order.create', (Object? caller, Object? resource) => true);
    const DVAuthAuthorization().registerAction(
        'Order.update', (Object? caller, Object? resource) => true);
    const DVAuthAuthorization().registerAction(
        'Order.delete', (Object? caller, Object? resource) => true);
    DVOfflineSync.register('Order', _device);
  });

  tearDown(() async {
    await DVOfflineSync.resetForTesting();
    DVAuthAuthorization.reset();
    await network.close();
  });

  test('a write made offline reaches the server when the network returns',
      () async {
    reachable = false;
    install();

    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});
    DVOfflineSync.written('Order');
    await DVOfflineSync.idle;

    expect(await store.read('o1'), isNotNull, reason: 'written locally');
    expect(server.received, isEmpty, reason: 'nothing tried while offline');

    reachable = true;
    network.add(true);
    await pumpUntil(() async => await server.reference('o1') != null);

    expect(await server.reference('o1'), 'R-1');
    expect(await store.pending(), isEmpty);
    expect(store.syncStateOf('o1'), DVSyncState.synced);
  });

  test('a write made online is sent without anything asking for it',
      () async {
    install();

    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});
    DVOfflineSync.written('Order');
    await pumpUntil(() async => await server.reference('o1') != null);

    expect(await server.reference('o1'), 'R-1');
  });

  test('a failed send is retried by itself, and nothing is lost', () async {
    // unknown reports reachable, so the first attempt is made and fails:
    // the write's own failure is what says the server is gone.
    server.down = true;
    install();

    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});
    DVOfflineSync.written('Order');
    await DVOfflineSync.idle;
    expect((await store.pending()).single.key, 'o1',
        reason: 'a failed send keeps the write queued');

    server.down = false;
    await pumpUntil(() async => await server.reference('o1') != null);
    expect(await server.reference('o1'), 'R-1');
  });

  test('writes queued before the application closed are sent at start',
      () async {
    // Last session: written, never sent.
    final DVOfflineStore before = _device(device);
    await before.ensureSchema();
    await before.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});

    // This session: the model is registered and the runtime installed, and
    // nothing touches Order at all.
    install();
    await pumpUntil(() async => await server.reference('o1') != null);

    expect(await server.reference('o1'), 'R-1');
  });

  test('a refused write is not retried, and says so on the record',
      () async {
    DVAuthAuthorization.reset(); // the policy says no to everything
    install();

    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});
    DVOfflineSync.written('Order');
    await pumpUntil(
        () async => store.syncStateOf('o1') == DVSyncState.rejected);
    final int sends = server.received.length;

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.received.length, sends,
        reason: 'a permanent refusal is not a reason to send again');
    expect(await server.reference('o1'), isNull);
  });

  test('two reconnects at once send each write once', () async {
    reachable = false;
    install();
    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});
    await store.write(<String, Object?>{'id': 'o2', 'reference': 'R-2'});

    reachable = true;
    network
      ..add(true)
      ..add(true);
    DVOfflineSync.written('Order');
    await pumpUntil(() async => await server.reference('o2') != null);
    await DVOfflineSync.idle;

    expect(server.received.toSet().length, server.received.length,
        reason: 'the same mutation id sent twice: $server.received');
  });

  test('when the server keeps another write, the device is told', () async {
    // Somebody else's later write already landed. The device's copy follows
    // the server's, and a watcher of the model has to hear about it: a list
    // that keeps showing the device's own value after the server discarded
    // it is showing something that is no longer true anywhere.
    final DVRecordTableRemote other = DVRecordTableRemote(
      DVRecordTable(
        table: 'orders',
        key: 'id',
        columns: const <String>['id', 'reference'],
        types: const <String, String>{'id': 'TEXT', 'reference': 'TEXT'},
        database: server.database,
      ),
      strategy: DVConflict.lastWriteWins,
    );
    await other.ensureSchema();
    await other.applyDirect(<String, Object?>{'id': 'o1', 'reference': 'THEIRS'},
        at: DateTime.now().toUtc().add(const Duration(hours: 1)));

    final List<Object?> adopted = <Object?>[];
    await DVOfflineSync.resetForTesting();
    DVOfflineSync.register(
      'Order',
      (DVDatabaseAdapter database) => DVOfflineStore(
        table: _device(database).table,
        policy: const DVOffline(strategy: DVConflict.lastWriteWins),
        onAdopted: (DVRecord record) => adopted.add(record.values['reference']),
      ),
    );
    install();

    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'MINE'});
    DVOfflineSync.written('Order');
    await pumpUntil(
        () async => store.syncStateOf('o1') == DVSyncState.conflicted);

    expect((await store.read('o1'))!.values['reference'], 'THEIRS');
    expect(adopted, <Object?>['THEIRS']);
  });

  test('the device learns the server clock from the answer', () async {
    install();
    final DVOfflineStore store = await DVOfflineSync.store('Order');
    store.clock.offset = const Duration(days: 3); // nonsense until corrected
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});
    DVOfflineSync.written('Order');
    await pumpUntil(() async => await server.reference('o1') != null);

    expect(store.clock.offset.abs(), lessThan(const Duration(minutes: 1)));
  });

  test('signing out empties the device copy and the queue', () async {
    reachable = false;
    install();
    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});

    await DVOfflineSync.signedOut();

    expect(await store.all(), isEmpty,
        reason: 'a signed-out device must not still hold the rows');
    expect(await store.pending(), isEmpty);
  });

  test('signing out sends what it can first', () async {
    reachable = false;
    install();
    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});

    reachable = true;
    await DVOfflineSync.signedOut();

    expect(await server.reference('o1'), 'R-1');
  });

  test('without the runtime installed, the model still reads and writes',
      () async {
    // A plain Dart test, or an application whose widget tests never start
    // the generated runtime: local only, and nothing thrown.
    final DVOfflineStore store = await DVOfflineSync.store('Order');
    await store.write(<String, Object?>{'id': 'o1', 'reference': 'R-1'});
    DVOfflineSync.written('Order');
    await DVOfflineSync.idle;

    expect((await store.read('o1'))?.values['reference'], 'R-1');
  });

  group('over HTTP', () {
    late HttpServer http;
    late List<(Map<String, String>, Object?)> requests;
    late int status;

    setUp(() async {
      requests = <(Map<String, String>, Object?)>[];
      status = 200;
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((HttpRequest request) async {
        final String text = await utf8.decodeStream(request);
        final Map<String, String> headers = <String, String>{};
        request.headers.forEach((String name, List<String> values) {
          headers[name] = values.join(',');
        });
        requests.add((headers, jsonDecode(text)));
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, Object?>{
            'outcomes': <Object?>[
              <String, Object?>{
                'mutationId': 'm',
                'discarded': false,
                'record': <String, Object?>{
                  'key': 'o1',
                  'version': 1,
                  'values': <String, Object?>{'id': 'o1', 'reference': 'R-1'},
                },
              },
            ],
            'serverTime': DateTime.now().toUtc().toIso8601String(),
          }));
        await request.response.close();
      });
    });

    tearDown(() => http.close(force: true));

    test('posts JSON with the caller\'s session and a CSRF token', () async {
      final DVOfflineSend send = dvOfflineSendOverHttp(
        endpoint: () => Uri.parse('http://127.0.0.1:${http.port}/api/offline/replay'),
        headers: () => <String, String>{'Authorization': 'Bearer dvs_x'},
      );

      final DVOfflineReply reply = await send(<String, Object?>{
        'model': 'Order',
        'mutations': <Object?>[],
      });

      expect(reply.status, 200);
      final (Map<String, String> headers, Object? body) = requests.single;
      expect(headers['authorization'], 'Bearer dvs_x');
      expect(headers[DVCSRF.headerName], isNotNull);
      expect(headers['content-type'], contains('application/json'));
      expect((body! as Map<String, Object?>)['model'], 'Order');
    });

    test('a server error is not an answer', () async {
      status = 503;
      final DVOfflineSend send = dvOfflineSendOverHttp(
        endpoint: () => Uri.parse('http://127.0.0.1:${http.port}/x'),
      );

      final DVOfflineReply reply = await send(const <String, Object?>{});
      expect(reply.status, 503);
    });
  });
}

/// Waits for [done] without a fixed sleep, failing after a few seconds.
Future<void> pumpUntil(Future<bool> Function() done) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!await done()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('timed out waiting for the sync to happen by itself');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
