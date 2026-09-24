// What a running application reaches: DV.Analytics and DV.Privacy, configured
// from `dartvel.analytics` in pubspec.yaml.
//
// The pipeline and the privacy walk are tested on their own elsewhere. What
// is tested here is the wiring, and every failure in it is silent. An event
// tracked in the first milliseconds of a launch, before the stored consent
// has been read, is judged against the declared defaults instead of against
// what the person chose -- and it looks exactly like an allowed event. A typo
// in the configuration that is skipped leaves a category nobody declared, or
// a default nobody meant. Adapters that nobody installed make an erasure
// report success while the subject's events are still in the store.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
// The record layer, which an application does not name and a test of it
// does.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

const DVConsentCategory product = DVConsentCategory('product');
const DVConsentCategory marketing = DVConsentCategory('marketing');

Map<String, Object?> consentConfig({
  Object? version = '2026-09-01',
  Map<String, Object?>? categories,
}) =>
    <String, Object?>{
      'version': version,
      'categories': categories ??
          <String, Object?>{
            'essential': <String, Object?>{'required': true},
            'product': <String, Object?>{'default': 'granted'},
            'marketing': <String, Object?>{
              'default': 'denied',
              'tracking': true,
            },
          },
    };

DVAnalyticsSettings settings({String? flags}) =>
    DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': consentConfig(),
      if (flags != null) 'flags': <String, Object?>{'category': flags},
    });

class ProductViewed extends DVAnalyticsEvent {
  const ProductViewed();
  @override
  String get name => 'product_viewed';
  @override
  DVConsentCategory get category => product;
}

/// A database that is not there yet: opening it waits on [open].
class SlowDatabase {
  SlowDatabase(this.database);
  final DVDatabaseAdapter database;
  final Completer<void> open = Completer<void>();

  Future<DVDatabaseAdapter> call() async {
    await open.future;
    return database;
  }
}

final List<int> signingKey = List<int>.generate(32, (int i) => i * 7 % 256);

void main() {
  setUp(() {
    DVAnalyticsRuntime.resetForTest();
    DVPrivacyRuntime.resetForTest();
    DVFlags.resetForTest();
  });

  group('dartvel.analytics.consent is read strictly', () {
    test('reads what the section declares', () {
      final DVConsentPolicy policy =
          DVConsentPolicy.fromConfig(consentConfig());
      expect(policy.version, '2026-09-01');
      expect(policy.declaration(product)!.defaultGranted, isTrue);
      expect(policy.declaration(marketing)!.tracking, isTrue);
      expect(policy.declaration(DVConsentCategory.essential)!.required, isTrue);
    });

    test('a misspelt consent key is refused, not skipped', () {
      expect(
        () => DVConsentPolicy.fromConfig(<String, Object?>{
          ...consentConfig(),
          'categoires': <String, Object?>{},
        }),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '$e', 'message', contains('categoires'))),
      );
    });

    test('a misspelt category key is refused, not read as false', () {
      // Skipped, `tracknig: true` leaves a tracking category untracked, so
      // iOS never shows the App Tracking Transparency prompt for it.
      expect(
        () => DVConsentPolicy.fromConfig(consentConfig(
          categories: <String, Object?>{
            'marketing': <String, Object?>{'tracknig': true},
          },
        )),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => '$e', 'message', contains('tracknig'))),
      );
    });

    test('required and tracking must be booleans', () {
      // `required: yes` in quotes is the string "yes"; read as `== true` it
      // was false, and a category the application needs defaulted to denied.
      for (final MapEntry<String, Object?> field in <MapEntry<String, Object?>>[
        const MapEntry<String, Object?>('required', 'yes'),
        const MapEntry<String, Object?>('tracking', 'true'),
      ]) {
        expect(
          () => DVConsentPolicy.fromConfig(consentConfig(
            categories: <String, Object?>{
              'product': <String, Object?>{field.key: field.value},
            },
          )),
          throwsA(isA<ArgumentError>().having(
              (ArgumentError e) => '$e', 'message', contains(field.key))),
          reason: field.key,
        );
      }
    });

    test('a category written as a bare value is refused', () {
      // `product: denied` reads naturally and declares nothing: the body was
      // not a map, so it was treated as empty and the default came from
      // nowhere.
      expect(
        () => DVConsentPolicy.fromConfig(consentConfig(
          categories: <String, Object?>{'product': 'denied'},
        )),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => '$e', 'message', contains('product'))),
      );
    });

    test('a default that is neither granted nor denied is refused', () {
      expect(
        () => DVConsentPolicy.fromConfig(consentConfig(
          categories: <String, Object?>{
            'product': <String, Object?>{'default': 'denid'},
          },
        )),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an empty body is a category with the declared defaults', () {
      final DVConsentPolicy policy = DVConsentPolicy.fromConfig(consentConfig(
        categories: <String, Object?>{'product': null},
      ));
      expect(policy.declaration(product)!.defaultGranted, isFalse);
    });
  });

  group('dartvel.analytics is read strictly', () {
    test('a misspelt analytics key is refused', () {
      expect(
        () => DVAnalyticsSettings.fromConfig(<String, Object?>{
          'consnet': consentConfig(),
        }),
        throwsA(isA<DVAnalyticsConfigurationError>().having(
            (DVAnalyticsConfigurationError e) => e.message,
            'message',
            allOf(contains('consnet'), contains('consent')))),
      );
    });

    test('analytics with no consent declared is refused', () {
      // Without a policy there is nothing to check an event against, and the
      // only safe reading -- deny everything -- would be a pipeline that
      // silently records nothing.
      expect(
        () => DVAnalyticsSettings.fromConfig(<String, Object?>{
          'store': 'database',
        }),
        throwsA(isA<DVAnalyticsConfigurationError>().having(
            (DVAnalyticsConfigurationError e) => e.message,
            'message',
            contains('consent'))),
      );
    });

    test('a store Dartvel does not have is refused', () {
      expect(
        () => DVAnalyticsSettings.fromConfig(<String, Object?>{
          'store': 'clickhouse',
          'consent': consentConfig(),
        }),
        throwsA(isA<DVAnalyticsConfigurationError>().having(
            (DVAnalyticsConfigurationError e) => e.message,
            'message',
            contains('clickhouse'))),
      );
    });

    test('flag exposure must name a declared category', () {
      expect(
        () => settings(flags: 'experiments'),
        throwsA(isA<DVAnalyticsConfigurationError>().having(
            (DVAnalyticsConfigurationError e) => e.message,
            'message',
            contains('experiments'))),
      );
      expect(
        () => DVAnalyticsSettings.fromConfig(<String, Object?>{
          'consent': consentConfig(),
          'flags': <String, Object?>{'categroy': 'product'},
        }),
        throwsA(isA<DVAnalyticsConfigurationError>().having(
            (DVAnalyticsConfigurationError e) => e.message,
            'message',
            contains('categroy'))),
      );
    });

    test('the session cap must be a positive whole number', () {
      for (final Object value in <Object>[0, 'lots', 2.5]) {
        expect(
          () => DVAnalyticsSettings.fromConfig(<String, Object?>{
            'consent': consentConfig(),
            'sessionCap': value,
          }),
          throwsA(isA<DVAnalyticsConfigurationError>()),
          reason: '$value',
        );
      }
      expect(
        DVAnalyticsSettings.fromConfig(<String, Object?>{
          'consent': consentConfig(),
          'sessionCap': 50,
        }).sessionCap,
        50,
      );
    });

    test('a consent error names where it is', () {
      expect(
        () => DVAnalyticsSettings.fromConfig(<String, Object?>{
          'consent': consentConfig(version: null),
        }),
        throwsA(isA<DVAnalyticsConfigurationError>().having(
            (DVAnalyticsConfigurationError e) => e.message,
            'message',
            allOf(contains('dartvel.analytics.consent'), contains('version')))),
      );
    });
  });

  group('DV.Analytics', () {
    test('throws until the application declares analytics', () {
      expect(
        () => DVAnalyticsRuntime.current,
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', contains('dartvel.analytics'))),
      );
    });

    test('an event tracked before the stored consent is read waits for it',
        () async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      // A previous launch: product defaults to granted, and the person said
      // no to it.
      final DVAnalyticsRuntime first =
          DVAnalyticsRuntime.start(settings: settings(), database: () => db);
      final DVConsent consent = await first.consent;
      expect(await consent.record(<DVConsentCategory, bool>{product: false}),
          isTrue);
      final String install = consent.installId;

      // This launch. The database takes a moment to open, and the first
      // screen tracks straight away.
      DVAnalyticsRuntime.resetForTest();
      final SlowDatabase slow = SlowDatabase(db);
      final DVAnalyticsRuntime second =
          DVAnalyticsRuntime.start(settings: settings(), database: slow.call);
      final Future<DVTrackResult> early = second.track(const ProductViewed());
      slow.open.complete();

      final DVTrackResult result = await early;
      expect(result.accepted, isFalse,
          reason: 'judged against the declared default, the event is allowed '
              'although the person withdrew consent');
      expect(result.code, 'DV-ANALYTICS-001');
      expect((await second.consent).installId, install,
          reason: 'the install id is kept between launches, or every launch '
              'is a new install that nobody has asked');
      expect(await (await second.pipeline).pending(), 0);
    });

    test('a pipeline that cannot start drops events and says why', () async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(),
        database: () => throw StateError('disk full'),
      );
      final DVTrackResult result = await runtime.track(const ProductViewed());
      expect(result.accepted, isFalse);
      expect(result.reason, contains('disk full'));
    });

    test('is the configured runtime once started', () async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      expect(identical(DVAnalyticsRuntime.current, runtime), isTrue);
      await runtime.ready;
      expect((await runtime.track(const ProductViewed())).accepted, isTrue);
    });

    test('flag exposure goes through analytics when configured', () async {
      final DVFeatureFlag<bool> newCheckout = DVFeatureFlag<bool>(
        key: 'newCheckout',
        defaultValue: false,
        owner: 'payments',
        expires: DateTime.utc(2099),
      );
      DVFlags.declare(<DVFeatureFlag<Object?>>[newCheckout]);
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(flags: 'product'),
        database: MemoryDVDatabaseAdapter.new,
      );
      await runtime.ready;
      expect(newCheckout.value, isFalse);
      final DVAnalytics pipeline = await runtime.pipeline;
      await pipeline.idle;
      await pipeline.flush();
      final List<DVAnalyticsRecord> stored =
          await (pipeline.store as DVAnalyticsDatabaseStore).events();
      expect(stored.map((DVAnalyticsRecord r) => r.name),
          <String>['dartvel.flag_exposed']);
    });

    test('flag exposure is not wired when no category is configured',
        () async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      await runtime.ready;
      expect(DVFlags.onExposure, isNull);
    });
  });

  group('DV.Privacy', () {
    test('throws until configured, naming the key it needs', () {
      expect(
        () => DVPrivacyRuntime.current,
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', contains('DARTVEL_PRIVACY_KEY'))),
      );
    });

    test('is configured from the environment, and refuses a short key', () {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      expect(
        DVPrivacyRuntime.configureFromEnvironment(
          environment: const <String, String>{},
          database: db,
          models: const <DVPrivacyModel>[],
        ),
        isFalse,
      );
      expect(() => DVPrivacyRuntime.current, throwsStateError);

      expect(
        () => DVPrivacyRuntime.configureFromEnvironment(
          environment: const <String, String>{'DARTVEL_PRIVACY_KEY': 'abcd'},
          database: db,
          models: const <DVPrivacyModel>[],
        ),
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', contains('32 bytes'))),
      );

      expect(
        DVPrivacyRuntime.configureFromEnvironment(
          environment: <String, String>{
            'DARTVEL_PRIVACY_KEY':
                signingKey.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(),
          },
          database: db,
          models: const <DVPrivacyModel>[],
        ),
        isTrue,
      );
      expect(DVPrivacyRuntime.current, isA<DVPrivacy>());
    });

    for (final bool analyticsFirst in <bool>[true, false]) {
      test(
          'analytics adapters are installed whichever starts first '
          '(analytics first: $analyticsFirst)', () async {
        final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
        void configurePrivacy() => DVPrivacyRuntime.configure(
              models: const <DVPrivacyModel>[],
              database: db,
              signingKey: signingKey,
            );
        if (!analyticsFirst) configurePrivacy();
        final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
            settings: settings(), database: () => db);
        await runtime.ready;
        if (analyticsFirst) configurePrivacy();

        expect(
          DVPrivacyRuntime.current.adapters.map((DVPrivacyAdapter a) => a.name),
          containsAll(<String>['analytics:events', 'analytics:consent']),
        );

        // And they work: an erasure removes the subject's events.
        final DVAnalytics pipeline = await runtime.pipeline;
        pipeline.identify('user-1');
        expect((await runtime.track(const ProductViewed())).accepted, isTrue);
        await pipeline.flush();
        final DVAnalyticsDatabaseStore store =
            pipeline.store as DVAnalyticsDatabaseStore;
        expect(await store.events(subject: 'user-1'), hasLength(1));
        await DVPrivacyRuntime.current.ensureSchema();
        final DVErasureResult result = await DVPrivacyRuntime.current
            .erase(subject: 'user-1', reason: 'test');
        expect(result.complete, isTrue);
        expect(await store.events(subject: 'user-1'), isEmpty);
      });
    }

    group('started by a server', () {
      late SqliteDVDatabaseAdapter db;
      late DVRecordTable sessions;

      setUp(() async {
        db = SqliteDVDatabaseAdapter.memory();
        sessions = DVRecordTable(
          table: 'sessions',
          key: 'id',
          columns: const <String>['id', 'user_id', 'ip', 'created_at'],
          database: db,
        );
        await sessions.ensureSchema();
        final DateTime now = DateTime.now().toUtc();
        await sessions.write(<String, Object?>{
          'id': 'old',
          'user_id': 'u1',
          'ip': '10.0.0.1',
          'created_at': now.subtract(const Duration(days: 45)).toIso8601String(),
        });
        await sessions.write(<String, Object?>{
          'id': 'new',
          'user_id': 'u2',
          'ip': '10.0.0.2',
          'created_at': now.toIso8601String(),
        });
      });

      tearDown(() => const DVQueues().useAdapter(DVInMemoryQueueAdapter()));

      void configure() => DVPrivacyRuntime.configure(
            models: <DVPrivacyModel>[
              DVPrivacyModel(
                name: 'sessions',
                table: sessions,
                subject: const DVSubject.field('user_id'),
                personal: const <String>{'ip'},
                retention: const DVRetention.days(30, from: 'created_at'),
              ),
            ],
            database: db,
            signingKey: signingKey,
          );

      Future<Set<String>> tables() async => <String>{
            for (final Map<String, Object?> row in await db.query(
                "SELECT name FROM sqlite_master WHERE type = 'table'"))
              '${row['name']}',
          };

      test('does nothing where DV.Privacy is not configured', () async {
        expect(await DVPrivacyRuntime.start(), isFalse);
        expect(DVPrivacyRuntime.schedules(), isNull);
        expect(await tables(), isNot(contains('dv_privacy_requests')));
      });

      test('creates the walk\'s own tables and runs its jobs from the queue',
          () async {
        configure();
        const DVQueues().useAdapter(
            DVDatabaseQueueAdapter(SqliteDVDatabaseAdapter.memory()));
        expect(await DVPrivacyRuntime.start(), isTrue);
        expect(
          await tables(),
          containsAll(<String>[
            'dv_privacy_requests',
            DVPrivacy.tombstoneTable,
            DVPrivacy.openErasuresTable,
          ]),
        );
        await DVPrivacyRuntime.current
            .requestErasure(subject: 'u1', reason: 'DSAR');
        await const DVQueues().dispatch<DVPrivacyRetentionRequest>(
            const DVPrivacyRetentionRequest());
        expect(await const DVQueues().work(maxJobs: 2), 2);
        expect(await sessions.read('old'), isNull);
        expect(await sessions.read('new'), isNotNull);
      });

      test('an adapter installed after start is in the walk its jobs run',
          () async {
        configure();
        await DVPrivacyRuntime.start();
        final List<String> erased = <String>[];
        DVPrivacyRuntime.installAdapters(
            <DVPrivacyAdapter>[_ErasingAdapter(erased)]);
        await DVPrivacyRuntime.current
            .requestErasure(subject: 'u2', reason: 'DSAR');
        expect(await const DVQueues().work(), 1);
        expect(erased, <String>['u2']);
      });

      test('sweeps retention and checks erasure deadlines on a schedule, '
          'each occurrence claimed through the lease', () async {
        configure();
        await DVPrivacyRuntime.start();
        DateTime clock = DateTime(2026, 9, 13, 2, 50);
        final _Lease lease = _Lease();
        final DVScheduler scheduler =
            DVPrivacyRuntime.schedules(clock: () => clock, lease: lease)!;
        expect(scheduler.names, <String>[
          DVPrivacyRuntime.retentionTask,
          DVPrivacyRuntime.deadlineTask,
        ]);
        await scheduler.tick();
        expect(await sessions.read('old'), isNotNull,
            reason: 'nothing is due before the first occurrence');

        clock = DateTime(2026, 9, 13, 3, 20);
        await scheduler.tick();
        expect(scheduler.failures, isEmpty);
        expect(await sessions.read('old'), isNull);
        expect(await sessions.read('new'), isNotNull);
        expect(lease.claims.map(((String, DateTime) c) => c.$1),
            containsAll(<String>[
              DVPrivacyRuntime.retentionTask,
              DVPrivacyRuntime.deadlineTask,
            ]));

        // A process that loses the claim sweeps nothing.
        await sessions.write(<String, Object?>{
          'id': 'old2',
          'user_id': 'u1',
          'ip': '10.0.0.3',
          'created_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 45))
              .toIso8601String(),
        });
        lease.grant = false;
        clock = DateTime(2026, 9, 14, 3, 20);
        await scheduler.tick();
        expect(await sessions.read('old2'), isNotNull);
      });

      test('the deadline check runs an erasure whose job was lost', () async {
        configure();
        await DVPrivacyRuntime.start();
        await DVPrivacyRuntime.current
            .requestErasure(subject: 'u1', reason: 'DSAR');
        // The in-process queue that held the job did not survive a restart.
        const DVQueues().useAdapter(DVInMemoryQueueAdapter());
        final DVErasureDeadlines deadlines = await DVPrivacyRuntime.current
            .checkErasureDeadlines(staleAfter: Duration.zero);
        expect(deadlines.results, hasLength(1));
        expect(await sessions.read('old'), isNull);
      });
    });
  });
}

class _ErasingAdapter implements DVPrivacyAdapter {
  _ErasingAdapter(this.erased);

  final List<String> erased;

  @override
  String get name => 'probe-index';

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async =>
      erased.add('${subject.id}');

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{};
}

class _Lease implements DVScheduleLease {
  bool grant = true;
  final List<(String, DateTime)> claims = <(String, DateTime)>[];

  @override
  Future<bool> claim(String task, DateTime occurrence) async {
    claims.add((task, occurrence));
    return grant;
  }
}
