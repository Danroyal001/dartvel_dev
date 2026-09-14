// The stores the processes of one deployment share, from its configuration.
//
// A generated backend runs as several processes and nothing gave them a store
// in common: a web process dispatched to its own process-local queue, which
// no worker could reach, and every cron process fired every schedule. The
// quiet failures: a web process whose jobs never reach the worker; an
// application's own queue adapter replaced by the one DATABASE_URL names; two
// cron processes on one database each firing an occurrence; and a declared
// cron process with no shared store starting anyway.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Welcome {
  const Welcome(this.userId);
  final String userId;
}

final DVJobPayloadCodec<Welcome> welcomeCodec = DVJobPayloadCodec<Welcome>(
  name: 'welcome',
  encode: (Welcome job) => <String, Object?>{'userId': job.userId},
  decode: (Map<String, Object?> json) => Welcome(json['userId']! as String),
);

DVProcessConfiguration role(Map<String, String> environment) =>
    DVProcessConfiguration.resolve(
      environment: environment,
      generatedPort: 8080,
    );

/// A database that cannot be reached.
class Unreachable implements DVDatabaseAdapter {
  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async =>
      throw StateError('database unreachable');

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async =>
      throw StateError('database unreachable');
}

void main() {
  late Directory dir;
  late String file;

  String? Function(String) reading(Map<String, String> values) =>
      (String key) => values[key];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dartvel_process_stores_');
    file = '${dir.path}/app.db';
    const DVTestHarness().unconfigureQueues();
    const DVDatabase().unconfigure();
    const DVJobPayloadCodecs().clear();
    const DVJobPayloadCodecs().register(welcomeCodec);
  });

  tearDown(() {
    const DVTestHarness().unconfigureQueues();
    const DVDatabase().unconfigure();
    const DVJobPayloadCodecs().clear();
    dir.deleteSync(recursive: true);
  });

  group('DVDatabaseScheduleLease', () {
    late DateTime now;
    late List<String> ran;

    DVScheduler process(DVScheduleLease? lease) =>
        DVScheduler(clock: () => now, lease: lease)
          ..register('invoices', '0 3 * * *', () async => ran.add('invoices'));

    setUp(() {
      now = DateTime.utc(2026, 9, 1, 2, 59);
      ran = <String>[];
    });

    test('without a lease two processes fire the occurrence twice', () async {
      // The control: if this reads once, the test below proves nothing.
      final DVScheduler a = process(null);
      final DVScheduler b = process(null);
      now = DateTime.utc(2026, 9, 1, 3, 0);
      await Future.wait(<Future<void>>[a.tick(), b.tick()]);
      expect(ran, <String>['invoices', 'invoices']);
    });

    test('two connections to one database fire each occurrence once',
        () async {
      final SqliteDVDatabaseAdapter first = SqliteDVDatabaseAdapter.file(file);
      final SqliteDVDatabaseAdapter second = SqliteDVDatabaseAdapter.file(file);
      addTearDown(first.close);
      addTearDown(second.close);
      final DVScheduler a = process(DVDatabaseScheduleLease(first));
      final DVScheduler b = process(DVDatabaseScheduleLease(second));

      now = DateTime.utc(2026, 9, 1, 3, 0);
      await Future.wait(<Future<void>>[a.tick(), b.tick()]);
      // Ticking again inside the minute is still once, on both.
      await Future.wait(<Future<void>>[b.tick(), a.tick()]);
      expect(ran, <String>['invoices']);
      expect(a.failures, isEmpty);
      expect(b.failures, isEmpty);

      // And the next occurrence is claimed afresh, whichever wins it.
      now = DateTime.utc(2026, 9, 2, 3, 0, 20);
      await Future.wait(<Future<void>>[b.tick(), a.tick()]);
      expect(ran, <String>['invoices', 'invoices']);
    });

    test('one instant is one claim, however a process spells it', () async {
      final SqliteDVDatabaseAdapter first = SqliteDVDatabaseAdapter.file(file);
      final SqliteDVDatabaseAdapter second = SqliteDVDatabaseAdapter.file(file);
      addTearDown(first.close);
      addTearDown(second.close);
      final DateTime instant = DateTime.utc(2026, 9, 1, 3, 5);
      expect(
        await DVDatabaseScheduleLease(first).claim('sweep', instant),
        isTrue,
      );
      expect(
        await DVDatabaseScheduleLease(second).claim('sweep', instant.toLocal()),
        isFalse,
      );
      expect(
        await DVDatabaseScheduleLease(second).claim('other', instant),
        isTrue,
      );
    });

    test('a database that cannot be reached runs nothing and says so',
        () async {
      // Running unguarded would be the double fire the lease is for.
      final DVScheduler scheduler = process(
        DVDatabaseScheduleLease(Unreachable()),
      );
      now = DateTime.utc(2026, 9, 1, 3, 0);
      await scheduler.tick();
      expect(ran, isEmpty);
      expect(scheduler.failures, hasLength(1));
    });
  });

  group('DVProcessStores.install', () {
    test('with no DATABASE_URL it installs nothing', () {
      final DVProcessStores stores = DVProcessStores.install(
        read: reading(const <String, String>{}),
      );
      expect(stores.database, isNull);
      expect(const DVQueues().adapterConfigured, isFalse);
    });

    test(
      'DATABASE_URL puts the queue and DV.Database on that database',
      () async {
        final DVProcessStores stores = DVProcessStores.install(
          read: reading(<String, String>{'DATABASE_URL': 'sqlite://$file'}),
        );
        expect(stores.database, isNotNull);
        expect(const DVQueues().adapterConfigured, isTrue);
        expect(identical(const DVDatabase().adapter, stores.database), isTrue);

        await const DVQueues().dispatch(const Welcome('ada'));

        // Another process opening the same database sees the job.
        final SqliteDVDatabaseAdapter other = SqliteDVDatabaseAdapter.file(
          file,
        );
        addTearDown(other.close);
        expect(
          await DVDatabaseQueueAdapter(other).pending('default'),
          hasLength(1),
        );
      },
    );

    test('a queue adapter the application configured is left alone', () async {
      final DVInMemoryQueueAdapter own = DVInMemoryQueueAdapter();
      const DVQueues().useAdapter(own);
      DVProcessStores.install(
        read: reading(<String, String>{'DATABASE_URL': 'sqlite://$file'}),
      );
      await const DVQueues().dispatch(const Welcome('ada'));
      expect(await own.pending('default'), hasLength(1));
    });

    test('a DV.Database already configured -- a preview does -- is reused', () {
      final SqliteDVDatabaseAdapter configured = SqliteDVDatabaseAdapter.file(
        '${dir.path}/preview.db',
      );
      addTearDown(configured.close);
      const DVDatabase().configure(configured);
      final DVProcessStores stores = DVProcessStores.install(
        read: reading(<String, String>{'DATABASE_URL': 'sqlite://$file'}),
      );
      // Not a second connection: two over one SQLite file is two write locks.
      expect(identical(stores.database, configured), isTrue);
    });

    test('a DATABASE_URL it cannot read refuses the start without printing it',
        () {
      expect(
        () => DVProcessStores.install(
          read: reading(const <String, String>{
            'DATABASE_URL': 'postgres://app:hunter2@db.internal',
          }),
        ),
        throwsA(
          isA<DVProcessConfigurationError>().having(
            (DVProcessConfigurationError e) => e.message,
            'message',
            allOf(contains('DATABASE_URL'), isNot(contains('hunter2'))),
          ),
        ),
      );
    });
  });

  group('DVProcessStores.scheduleLeaseFor', () {
    DVProcessStores shared() => DVProcessStores.install(
          read: reading(<String, String>{'DATABASE_URL': 'sqlite://$file'}),
        );
    DVProcessStores none() =>
        DVProcessStores.install(read: reading(const <String, String>{}));

    test('a ticking process on a shared database claims through it', () {
      final DVProcessStores stores = shared();
      expect(
        stores.scheduleLeaseFor(role(const <String, String>{
          'DARTVEL_ROLE': 'cron',
        })),
        isA<DVDatabaseScheduleLease>(),
      );
      // A process given no role may still be one of several instances.
      expect(
        stores.scheduleLeaseFor(role(const <String, String>{})),
        isA<DVDatabaseScheduleLease>(),
      );
    });

    test('a process that ticks nothing gets no lease', () {
      final DVProcessStores stores = shared();
      for (final String r in <String>['worker', 'web']) {
        expect(
          stores.scheduleLeaseFor(role(<String, String>{'DARTVEL_ROLE': r})),
          isNull,
        );
      }
    });

    test('a declared cron process with no shared store refuses to start', () {
      expect(
        () => none().scheduleLeaseFor(role(const <String, String>{
          'DARTVEL_ROLE': 'cron',
        })),
        throwsA(
          isA<DVProcessConfigurationError>().having(
            (DVProcessConfigurationError e) => e.message,
            'message',
            allOf(
              contains('DATABASE_URL'),
              contains('DARTVEL_SCHEDULE_LEASE=none'),
            ),
          ),
        ),
      );
    });

    test('DARTVEL_SCHEDULE_LEASE=none waives it, shared store or not', () {
      final Map<String, String> waived = const <String, String>{
        'DARTVEL_ROLE': 'cron',
        'DARTVEL_SCHEDULE_LEASE': 'none',
      };
      expect(none().scheduleLeaseFor(role(waived)), isNull);
      expect(shared().scheduleLeaseFor(role(waived)), isNull);
    });

    test('a process given no role and no shared store runs unguarded', () {
      // It is the whole deployment; there is no second process to race.
      expect(none().scheduleLeaseFor(role(const <String, String>{})), isNull);
    });
  });
}
