// Offline-first models: the local store, the mutation log and replay.
//
// Every failure worth a test here is a silent one. A mutation replayed twice
// after a reconnect writes twice and reports success. Mutations replayed out
// of order leave the server holding an earlier value than the device showed.
// A conflict resolved by whichever write happened to arrive last, when the
// model declared its clock, looks exactly like a correct merge. A full queue
// that drops the oldest write keeps the app feeling fine while discarding
// work somebody believed was saved. And `DVConflict.ask`, accepted offline,
// waits for an answer from somebody who is not there.
import 'package:dartvel_core/dartvel.dart';
// DVRecordTableRemote is the framework's own: an application asks the model
// for it through Model.offlineRemote.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

const List<String> _columns = <String>['id', 'reference', 'quantity', 'note'];

DVRecordTable _table(DVDatabaseAdapter database, {DVHistory? history}) =>
    DVRecordTable(
      table: 'orders',
      key: 'id',
      columns: _columns,
      history: history,
      softDelete: false,
      database: database,
    );

Map<String, Object?> _order(String id,
        {String reference = 'R-1', int quantity = 1, String note = ''}) =>
    <String, Object?>{
      'id': id,
      'reference': reference,
      'quantity': quantity,
      'note': note,
    };

/// A device clock the test moves by hand.
class _Time {
  DateTime now = DateTime.utc(2026, 9, 13, 12);
  DateTime call() => now;
}

/// A remote that records every mutation it is handed, in order, and can be
/// told to fail transiently or refuse permanently.
class _RecordingRemote implements DVOfflineRemote {
  _RecordingRemote(this.inner);

  final DVOfflineRemote inner;
  final List<String> seen = <String>[];

  /// Mutation ids that throw as if the connection dropped.
  final Set<String> dropFor = <String>{};

  /// Throw after the server has applied, as if the acknowledgement was lost.
  final Set<String> loseAckFor = <String>{};

  // Whatever the remote it wraps must not echo back. A wrapper that answered
  // an empty set would quietly undo the filtering of the thing it wraps,
  // which is why the member is required rather than defaulted.
  @override
  Set<String> get sensitiveColumns => inner.sensitiveColumns;

  @override
  Future<DVRemoteOutcome> apply(DVMutation mutation) async {
    seen.add(mutation.mutationId);
    if (dropFor.remove(mutation.mutationId)) {
      throw StateError('connection dropped');
    }
    final DVRemoteOutcome outcome = await inner.apply(mutation);
    if (loseAckFor.remove(mutation.mutationId)) {
      throw StateError('acknowledgement lost');
    }
    return outcome;
  }
}

void main() {
  test('DVConflict.ask is refused as an offline strategy', () {
    expect(
      () => DVOfflineStore(
        table: _table(MemoryDVDatabaseAdapter()),
        policy: const DVOffline(strategy: DVConflict.ask),
      ),
      throwsA(isA<DVOfflineStrategyError>()
          .having((DVOfflineStrategyError e) => e.code, 'code', 'DV-HISTORY-002')),
      reason: 'offline there is nobody to ask; accepting it would park the '
          'conflict waiting for an answer that never comes',
    );
  });

  for (final (String name, DVDatabaseAdapter Function() create) adapter
      in _adapters) {
    group('on ${adapter.$1}', () {
      late _Time time;
      late DVOfflineStore store;
      late DVRecordTable server;
      late _RecordingRemote remote;

      Future<DVOfflineStore> open({
        DVConflict strategy = DVConflict.lastWriteWins,
        int maxMutations = 100,
        Duration maxAge = const Duration(days: 7),
        bool Function(Map<String, Object?> values)? validate,
      }) async {
        final DVOfflineStore opened = DVOfflineStore(
          table: _table(adapter.$2()),
          policy: DVOffline(
            strategy: strategy,
            maxMutations: maxMutations,
            maxAge: maxAge,
            maxClockSkew: const Duration(minutes: 5),
          ),
          clock: DVOfflineClock(now: time.call),
        );
        await opened.ensureSchema();
        server = _table(adapter.$2(),
            history: const DVHistory(keep: Duration(days: 30)));
        await server.ensureSchema();
        remote = _RecordingRemote(DVRecordTableRemote(
          server,
          strategy: strategy,
          validate: validate,
        ));
        await (remote.inner as DVRecordTableRemote).ensureSchema();
        return opened;
      }

      setUp(() async {
        time = _Time();
        store = await open();
      });

      test('a write is readable locally at once and queued in order', () async {
        await store.write(_order('o1', quantity: 1));
        await store.write(_order('o1', quantity: 2));
        await store.write(_order('o2'));

        expect((await store.read('o1'))!.values['quantity'], 2,
            reason: 'the same model API reads the local store while offline');
        final List<DVMutation> pending = await store.pending();
        expect(pending.map((DVMutation m) => m.key).toList(),
            <Object?>['o1', 'o1', 'o2']);
        expect(pending.map((DVMutation m) => m.sequence).toList(),
            orderedEquals(<int>[...pending.map((DVMutation m) => m.sequence)]..sort()));
        expect(store.syncStateOf('o1'), DVSyncState.pending);
      });

      test('at the bound the next write is refused, and nothing is dropped',
          () async {
        store = await open(maxMutations: 2);
        await store.write(_order('o1', quantity: 1));
        await store.write(_order('o2', quantity: 1));

        await expectLater(
          store.write(_order('o3', quantity: 9)),
          throwsA(isA<DVOfflineQueueFullError>().having(
              (DVOfflineQueueFullError e) => e.code, 'code', 'DV-OFFLINE-002')),
        );

        final List<DVMutation> pending = await store.pending();
        expect(pending.map((DVMutation m) => m.key).toList(), <Object?>['o1', 'o2'],
            reason: 'dropping the oldest would discard work somebody believed '
                'was saved, and no later sync could recover it');
        expect(await store.read('o3'), isNull,
            reason: 'a refused write must not half-happen in the local store');
      });

      test('a queue whose oldest write is past maxAge refuses the next',
          () async {
        store = await open(maxAge: const Duration(days: 7));
        await store.write(_order('o1'));
        time.now = time.now.add(const Duration(days: 8));

        await expectLater(store.write(_order('o2')),
            throwsA(isA<DVOfflineQueueFullError>()));
        expect((await store.pending()).length, 1);
      });

      test('replay applies every mutation in the order it was made', () async {
        await store.write(_order('o1', quantity: 1));
        await store.write(_order('o1', quantity: 2));
        await store.write(_order('o1', quantity: 3));

        final DVReplayResult result = await store.replay(remote);

        expect(result.applied, 3);
        expect((await server.read('o1'))!.values['quantity'], 3,
            reason: 'out of order, the server would hold an earlier value '
                'than the one the device showed');
        expect(await store.pending(), isEmpty);
        expect(store.syncStateOf('o1'), DVSyncState.synced);
      });

      test('two replays at once send each mutation exactly once', () async {
        await store.write(_order('o1', quantity: 1));
        await store.write(_order('o2', quantity: 1));

        await Future.wait(<Future<DVReplayResult>>[
          store.replay(remote),
          store.replay(remote),
        ]);

        expect(remote.seen.length, 2,
            reason: 'a reconnect storm must not replay the log twice');
        expect((await server.history('o1')).length, 1);
      });

      test('a lost acknowledgement does not apply the mutation twice',
          () async {
        // Counted where the write reaches the server table, because nothing
        // downstream of the table can tell: an unchanged write records no
        // history entry and bumps no version, so a duplicate application of
        // the same values is invisible in both. This test passed with the
        // server's deduplication removed until it counted here.
        int applications = 0;
        store = await open(validate: (Map<String, Object?> _) {
          applications++;
          return true;
        });
        await store.write(_order('o1', quantity: 5));
        final String id = (await store.pending()).single.mutationId;
        remote.loseAckFor.add(id);

        final DVReplayResult first = await store.replay(remote);
        expect(first.applied, 0);
        expect((await store.pending()).single.mutationId, id,
            reason: 'unacknowledged, it stays queued');

        final DVReplayResult second = await store.replay(remote);
        expect(second.applied, 1);
        expect(remote.seen, <String>[id, id]);
        expect((await server.history('o1')).length, 1,
            reason: 'the server deduplicates by mutation id, so the resend '
                'is not a second write');
        expect(applications, 1,
            reason: 'the resend must not reach the table a second time');
        expect(await store.pending(), isEmpty);
      });

      test('a transient failure stops replay rather than skipping ahead',
          () async {
        await store.write(_order('o1', quantity: 1));
        await store.write(_order('o1', quantity: 2));
        await store.write(_order('o1', quantity: 3));
        final List<DVMutation> pending = await store.pending();
        remote.dropFor.add(pending[1].mutationId);

        final DVReplayResult first = await store.replay(remote);
        expect(first.applied, 1);
        expect(remote.seen, <String>[pending[0].mutationId, pending[1].mutationId],
            reason: 'sending the third before the second lands would apply '
                'them out of order');
        expect((await server.read('o1'))!.values['quantity'], 1);

        await store.replay(remote);
        expect((await server.read('o1'))!.values['quantity'], 3);
        expect(await store.pending(), isEmpty);
      });

      test('a permanent rejection is dead-lettered and replay continues',
          () async {
        store = await open(
            validate: (Map<String, Object?> v) => (v['quantity']! as int) > 0);
        await store.write(_order('bad', quantity: -1));
        await store.write(_order('good', quantity: 4));

        final DVReplayResult result = await store.replay(remote);

        expect(result.rejected, 1);
        expect(result.applied, 1);
        expect((await store.rejected()).single.key, 'bad');
        expect(await store.pending(), isEmpty,
            reason: 'a rejected mutation is not retried forever');
        expect(store.syncStateOf('bad'), DVSyncState.rejected);
        expect(store.reported, contains('DV-OFFLINE-003'));
        expect((await server.read('good'))!.values['quantity'], 4);
      });

      test('lastWriteWins compares the declared clock, not arrival order',
          () async {
        // The device writes at 12:00 while offline.
        await store.write(_order('o1', note: 'device at noon'));
        // The server receives a write from elsewhere at 12:30.
        time.now = time.now.add(const Duration(minutes: 30));
        await (remote.inner as DVRecordTableRemote).applyDirect(
            _order('o1', note: 'server at half past'),
            at: time.now);
        // The device reconnects at 13:00 and replays its older write.
        time.now = time.now.add(const Duration(minutes: 30));

        final DVReplayResult result = await store.replay(remote);

        expect((await server.read('o1'))!.values['note'], 'server at half past',
            reason: 'the device write is older by the declared clock; letting '
                'it win because it arrived last is the silent wrong merge');
        expect(result.conflicted, 1);
        expect(store.syncStateOf('o1'), DVSyncState.conflicted);
        expect((await store.read('o1'))!.values['note'], 'server at half past',
            reason: 'the local copy follows what the server kept');
      });

      test('a later offline write does win under lastWriteWins', () async {
        await (remote.inner as DVRecordTableRemote).applyDirect(
            _order('o1', note: 'server first'),
            at: time.now);
        time.now = time.now.add(const Duration(minutes: 10));
        await store.write(_order('o1', note: 'device later'));

        await store.replay(remote);

        expect((await server.read('o1'))!.values['note'], 'device later');
      });

      test('serverWins discards the local change and says so', () async {
        store = await open(strategy: DVConflict.serverWins);
        await (remote.inner as DVRecordTableRemote)
            .applyDirect(_order('o1', note: 'server'), at: time.now);
        await store.write(_order('o1', note: 'device'));

        final DVReplayResult result = await store.replay(remote);

        expect((await server.read('o1'))!.values['note'], 'server');
        expect(result.conflicted, 1);
        expect(store.syncStateOf('o1'), DVSyncState.conflicted);
        expect((await store.read('o1'))!.values['note'], 'server');
      });

      test('fieldMerge keeps both writers\' changes to different fields',
          () async {
        store = await open(strategy: DVConflict.fieldMerge);
        final DVRemoteOutcome seeded = await (remote.inner as DVRecordTableRemote)
            .applyDirect(_order('o1', quantity: 1, note: 'first'), at: time.now);
        await store.adoptServer(seeded.record!);

        await (remote.inner as DVRecordTableRemote)
            .applyDirect(_order('o1', quantity: 1, note: 'server note'),
                at: time.now.add(const Duration(minutes: 1)));
        await store.write(_order('o1', quantity: 7, note: 'first'));

        await store.replay(remote);

        final Map<String, Object?> merged = (await server.read('o1'))!.values;
        expect(merged['quantity'], 7);
        expect(merged['note'], 'server note');
      });

      test('an offline delete reaches the server on replay', () async {
        await (remote.inner as DVRecordTableRemote)
            .applyDirect(_order('o1'), at: time.now);
        await store.delete('o1');

        expect(await store.read('o1'), isNull);
        await store.replay(remote);
        expect(await server.read('o1'), isNull);
      });

      test('a skewed clock is corrected and reported once', () async {
        // The server says it is a day later than the device thinks.
        store.clock.observeServerTime(time.now.add(const Duration(days: 1)));
        store.clock.observeServerTime(time.now.add(const Duration(days: 1)));
        await store.write(_order('o1'));

        final DVMutation m = (await store.pending()).single;
        expect(m.deviceTime, time.now);
        expect(m.correctedTime, time.now.add(const Duration(days: 1)),
            reason: 'last-write-wins compares corrected stamps, or a device '
                'with a wrong date wins every conflict');
        expect(store.reported.where((String c) => c == 'DV-OFFLINE-004').length, 1);
      });

      test('clear empties the local store and the log', () async {
        await store.write(_order('o1'));
        await store.clear();
        expect(await store.read('o1'), isNull);
        expect(await store.pending(), isEmpty);
      });
    });
  }

  test('a memory-backed store says so, once', () async {
    final DVOfflineStore store = DVOfflineStore(
      table: _table(MemoryDVDatabaseAdapter()),
      policy: const DVOffline(strategy: DVConflict.lastWriteWins),
    );
    await store.ensureSchema();
    await store.write(_order('o1'));
    await store.write(_order('o2'));

    expect(store.persistent, isFalse);
    expect(store.reported.where((String c) => c == 'DV-OFFLINE-001').length, 1,
        reason: 'an application that cannot persist should know before '
            'somebody closes the lid');
  });

  test('a SQLite-backed store is persistent and reports nothing', () async {
    final DVOfflineStore store = DVOfflineStore(
      table: _table(SqliteDVDatabaseAdapter.memory()),
      policy: const DVOffline(strategy: DVConflict.lastWriteWins),
    );
    await store.ensureSchema();
    await store.write(_order('o1'));
    expect(store.persistent, isTrue);
    expect(store.reported, isEmpty);
  });
}
