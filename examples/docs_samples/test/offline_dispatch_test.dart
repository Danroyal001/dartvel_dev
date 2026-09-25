// Dispatch declares offline:, and this is what that promises, with the
// generated model and nothing else from the application: a save made with
// no network returns at once, reads back on the device, and reaches the
// server when the network returns.
//
// The harness below stands in for the two things a test process does not
// have -- a network signal and a server -- and is the framework's side of
// the line. The application's side is `Dispatch(...).save()`.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/framework.dart';
import 'package:docs_samples/dartvel_client/dartvel_client.dart';
import 'package:docs_samples/dartvel_client/model_pages.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryDVDatabaseAdapter server;
  late StreamController<bool> network;
  late bool reachable;

  // Wherever the generated backend puts Dispatch's rows.
  final String table = dartvelStudioModels
      .singleWhere((DVStudioModelSpec spec) => spec.model == 'Dispatch')
      .table;
  Future<List<Map<String, Object?>>> onServer() =>
      server.query('SELECT reference, quantity FROM $table');

  setUp(() {
    server = MemoryDVDatabaseAdapter();
    network = StreamController<bool>.broadcast();
    reachable = false;
    // The application's policy, as the server asks it.
    for (final String action in <String>['create', 'update', 'delete']) {
      const DVAuthAuthorization().registerAction(
          'Dispatch.$action', (Object? caller, Object? resource) => true);
    }
    registerDartvelModels();
    DVOfflineSync.install(
      database: () async => MemoryDVDatabaseAdapter(),
      send: (Map<String, Object?> body) async {
        final DVOfflineReplayResult result = await DVOfflineReplay.forSpecs(
          dartvelStudioModels,
          database: server,
        ).handle(jsonDecode(jsonEncode(body)));
        return DVOfflineReply(
          result.status,
          jsonDecode(jsonEncode(<String, Object?>{...result.body}))
              as Map<String, Object?>,
        );
      },
      reachability: network.stream,
      canReachTheServer: () => reachable,
    );
  });

  tearDown(() async {
    await DVOfflineSync.resetForTesting();
    DVAuthAuthorization.reset();
    await network.close();
  });

  test('a dispatch saved offline is on the server once the network returns',
      () async {
    await const Dispatch(id: 'd1', reference: 'R-1', quantity: 2).save();

    // Read back on the device, with no network.
    expect((await Dispatch.find('d1'))?.quantity, 2);
    expect(await onServer(), isEmpty);

    reachable = true;
    network.add(true);
    await _until(() async => (await onServer()).isNotEmpty);

    expect((await onServer()).single['reference'], 'R-1');
  });

  test('a dispatch deleted offline is deleted on the server', () async {
    reachable = true;
    const Dispatch dispatch = Dispatch(id: 'd1', reference: 'R-1', quantity: 2);
    await dispatch.save();
    await _until(() async => (await onServer()).isNotEmpty);

    reachable = false;
    await dispatch.destroy();
    expect(await Dispatch.find('d1'), isNull);

    reachable = true;
    network.add(true);
    await _until(() async => (await onServer()).isEmpty);
  });

  test('a record says where it stands', () async {
    const Dispatch dispatch = Dispatch(id: 'd1', reference: 'R-1', quantity: 2);
    await dispatch.save();
    expect(await dispatch.syncState.first, DVSyncState.pending);

    reachable = true;
    network.add(true);
    await _until(() async => (await onServer()).isNotEmpty);
    await DVOfflineSync.idle;
    expect(await dispatch.syncState.first, DVSyncState.synced);
  });
}

Future<void> _until(Future<bool> Function() done) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!await done()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('the sync did not happen by itself');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
