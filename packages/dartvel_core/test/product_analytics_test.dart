// Product analytics and consent.
//
// Every failure worth a test here is silent. An event recorded before consent
// was given, or delivered after it was withdrawn, looks exactly like an event
// that was allowed. Events tracked while a category was denied and flushed
// once consent arrives look like a working pipeline. A sensitive field in a
// property map reaches somebody else's warehouse and nobody sees it leave. An
// erased subject's events left in the store, an anonymous id or a session id
// that carries across a withdrawal, a changed consent policy that quietly
// keeps the old answers: none of them throws, so each is asserted directly.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

const DVConsentCategory product = DVConsentCategory('product');
const DVConsentCategory marketing = DVConsentCategory('marketing');

final DVConsentPolicy policyV1 = DVConsentPolicy(
  version: '2026-09-01',
  categories: const <DVConsentDeclaration>[
    DVConsentDeclaration(DVConsentCategory.essential, required: true),
    DVConsentDeclaration(product),
    DVConsentDeclaration(marketing, tracking: true),
  ],
);

final DVConsentPolicy policyV2 = DVConsentPolicy(
  version: '2026-10-01',
  categories: policyV1.categories,
);

final List<int> _signingKey = List<int>.generate(32, (int i) => i * 11 % 256);

class Order {
  const Order(this.id, this.total, this.cardNumber);
  final String id;
  final int total;
  final String cardNumber;

  /// What a generated model emits: sensitive fields absent by construction.
  Map<String, Object?> toPublicJson() => <String, Object?>{
        'id': id,
        'total': total,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'total': total,
        'card_number': cardNumber,
      };
}

/// Not a generated model: only an internal form, which carries everything.
class LegacyOrder {
  const LegacyOrder(this.id, this.cardNumber);
  final String id;
  final String cardNumber;
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'card_number': cardNumber,
      };
}

class Opaque {
  @override
  String toString() => 'ada@example.com';
}

class CheckoutCompleted extends DVAnalyticsEvent {
  const CheckoutCompleted(this.order, {this.coupon});
  final Object order;
  final String? coupon;

  @override
  String get name => 'checkout_completed';
  @override
  DVConsentCategory get category => product;
  @override
  Map<String, Object?> get properties => <String, Object?>{
        'order': order,
        'coupon': coupon,
      };
}

class Step extends DVAnalyticsEvent {
  const Step(this.name, {this.category = product, this.extra = const {}});
  @override
  final String name;
  @override
  final DVConsentCategory category;
  final Map<String, Object?> extra;
  @override
  Map<String, Object?> get properties => extra;
}

class _Provider implements DVAnalyticsProvider {
  _Provider(this.name, this.categories, {this.failing = false});
  @override
  final String name;
  @override
  final Set<DVConsentCategory> categories;
  bool failing;
  final List<DVAnalyticsRecord> received = <DVAnalyticsRecord>[];
  int sends = 0;

  @override
  Future<void> send(List<DVAnalyticsRecord> batch) async {
    sends++;
    if (failing) throw StateError('$name unreachable');
    received.addAll(batch);
  }
}

class _ErasableProvider extends _Provider implements DVAnalyticsErasableSink {
  _ErasableProvider(super.name, super.categories);
  final List<String> erased = <String>[];

  @override
  Future<void> eraseSubject(String subject) async {
    erased.add(subject);
    received.removeWhere(
        (DVAnalyticsRecord r) => r.userId == subject || r.anonymousId == subject);
  }

  @override
  Future<List<Map<String, Object?>>> exportSubject(String subject) async =>
      <Map<String, Object?>>[
        for (final DVAnalyticsRecord r in received)
          if (r.userId == subject) r.toJson(),
      ];
}

/// A database whose writes to one table fail, as a full disk or a lost
/// connection does.
class _FailingWrites implements DVDatabaseAdapter {
  _FailingWrites(this.inner, this.table);
  final DVDatabaseAdapter inner;
  final String table;
  bool failing = false;

  @override
  Future<int> execute(String sql, [List<Object?>? params]) {
    if (failing && sql.contains(table) && !sql.startsWith('CREATE')) {
      throw StateError('disk full');
    }
    return inner.execute(sql, params);
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql,
          [List<Object?>? params]) =>
      inner.query(sql, params);
}

void main() {
  late List<String> reported;
  void report(String code, String message) => reported.add(code);

  setUp(() {
    reported = <String>[];
    DVSecrets.reset();
    DVFlags.resetForTest();
  });

  group('the consent policy', () {
    test('is read from dartvel.analytics.consent', () {
      final DVConsentPolicy policy = DVConsentPolicy.fromConfig(
        <String, Object?>{
          'version': '2026-09-01',
          'categories': <String, Object?>{
            'essential': <String, Object?>{'required': true},
            'product': <String, Object?>{'default': 'denied'},
            'marketing': <String, Object?>{
              'default': 'denied',
              'tracking': true,
            },
          },
        },
      );
      expect(policy.version, '2026-09-01');
      expect(policy.declaration(DVConsentCategory.essential)!.required, isTrue);
      expect(policy.declaration(product)!.required, isFalse);
      expect(policy.declaration(product)!.defaultGranted, isFalse);
      expect(policy.declaration(marketing)!.tracking, isTrue);
    });

    test('a policy without a version is refused, because nothing could re-ask',
        () {
      expect(
        () => DVConsentPolicy.fromConfig(<String, Object?>{
          'categories': <String, Object?>{
            'product': <String, Object?>{'default': 'denied'},
          },
        }),
        throwsArgumentError,
      );
    });

    test('a default that is neither granted nor denied is refused', () {
      expect(
        () => DVConsentPolicy.fromConfig(<String, Object?>{
          'version': '1',
          'categories': <String, Object?>{
            'product': <String, Object?>{'default': 'maybe'},
          },
        }),
        throwsArgumentError,
      );
    });

    test('a required category cannot default to denied', () {
      expect(
        () => DVConsentPolicy(version: '1', categories: const <DVConsentDeclaration>[
          DVConsentDeclaration(DVConsentCategory.essential,
              required: true, defaultGranted: false),
        ]),
        throwsArgumentError,
      );
    });

    test('a category with no way to ask on a target is DV-ANALYTICS-002', () {
      final List<DVAnalyticsFinding> findings = policyV1.check(
        targets: <DVConsentTarget>[
          DVConsentTarget.web,
          const DVConsentTarget('kiosk-display', prompts: <DVConsentPrompt>{}),
        ],
      );
      expect(findings.map((DVAnalyticsFinding f) => f.code).toSet(),
          <String>{'DV-ANALYTICS-002'});
      expect(findings.map((DVAnalyticsFinding f) => f.target).toSet(),
          <String>{'kiosk-display'});
      // essential is never asked, so it is never a finding.
      expect(findings.map((DVAnalyticsFinding f) => f.category).toSet(),
          <String>{'product', 'marketing'});
    });

    test('a tracking category on iOS needs the App Tracking Transparency prompt',
        () {
      final List<DVAnalyticsFinding> findings = policyV1.check(
        targets: <DVConsentTarget>[
          DVConsentTarget.ios,
          const DVConsentTarget('ios',
              prompts: <DVConsentPrompt>{DVConsentPrompt.settingsScreen},
              tracksWithAppTrackingTransparency: true),
        ],
      );
      expect(findings, hasLength(1));
      expect(findings.single.category, 'marketing');
      expect(DVConsentTarget.ios.prompts,
          contains(DVConsentPrompt.appTrackingTransparency));
    });
  });

  for (final _Adapter adapter in _adapters) {
    group('consent records (${adapter.$1})', () {
      late DVDatabaseAdapter database;
      DateTime now = DateTime.utc(2026, 9, 14, 9);

      Future<DVConsent> open(DVConsentPolicy policy,
          {DVDatabaseAdapter? db}) async {
        final DVConsent consent = DVConsent(
          policy: policy,
          database: db ?? database,
          installId: 'install-1',
          clock: () => now,
          onDiagnostic: report,
        );
        await consent.ensureSchema();
        await consent.load();
        return consent;
      }

      setUp(() {
        database = adapter.$2();
        now = DateTime.utc(2026, 9, 14, 9);
      });

      test('before any choice, essential is granted and the rest are denied',
          () async {
        final DVConsent consent = await open(policyV1);
        expect(consent.isGranted(DVConsentCategory.essential), isTrue);
        expect(consent.isGranted(product), isFalse);
        expect(consent.isGranted(marketing), isFalse);
        expect(consent.needsPrompt, isTrue);
      });

      test('a choice is a record of what was asked, answered, when, and under '
          'which version', () async {
        final DVConsent consent = await open(policyV1);
        final bool written = await consent.record(
          <DVConsentCategory, bool>{product: true, marketing: false},
          prompt: DVConsentPrompt.banner,
          userId: 'u1',
        );
        expect(written, isTrue);
        expect(consent.isGranted(product), isTrue);
        expect(consent.isGranted(marketing), isFalse);
        expect(consent.needsPrompt, isFalse);

        final List<DVConsentRecord> records = await consent.records();
        expect(records, hasLength(1));
        final DVConsentRecord r = records.single;
        expect(r.policyVersion, '2026-09-01');
        expect(r.asked, <String>{'product', 'marketing'});
        expect(r.answers, <String, bool>{'product': true, 'marketing': false});
        expect(r.recordedAt, now);
        expect(r.installId, 'install-1');
        expect(r.userId, 'u1');
        expect(r.prompt, DVConsentPrompt.banner);

        // Read back by a new process, from the record and nothing else.
        final DVConsent again = await open(policyV1);
        expect(again.isGranted(product), isTrue);
        expect(again.needsPrompt, isFalse);
      });

      test('the latest choice wins, and a withdrawal is a record too', () async {
        final DVConsent consent = await open(policyV1);
        await consent.record(<DVConsentCategory, bool>{product: true});
        now = now.add(const Duration(minutes: 1));
        await consent.record(<DVConsentCategory, bool>{product: false});
        expect(consent.isGranted(product), isFalse);
        expect(await consent.records(), hasLength(2));
        final DVConsent again = await open(policyV1);
        expect(again.isGranted(product), isFalse);
      });

      test('a category that was asked and not answered is denied', () async {
        final DVConsent consent = await open(policyV1);
        await consent.record(<DVConsentCategory, bool>{product: true},
            asked: <DVConsentCategory>{product, marketing});
        expect(consent.isGranted(marketing), isFalse);
        expect((await consent.records()).single.answers,
            <String, bool>{'product': true, 'marketing': false});
      });

      test('a new version of the categories asks again and does not keep the '
          'old answers', () async {
        final DVConsent first = await open(policyV1);
        await first.record(<DVConsentCategory, bool>{product: true});
        expect(first.isGranted(product), isTrue);

        final DVConsent bumped = await open(policyV2);
        expect(bumped.needsPrompt, isTrue);
        expect(bumped.isGranted(product), isFalse);

        await bumped.record(<DVConsentCategory, bool>{product: true});
        expect(bumped.isGranted(product), isTrue);
        expect(bumped.needsPrompt, isFalse);
      });

      test('a grant that cannot be written is not consent (DV-ANALYTICS-006)',
          () async {
        final _FailingWrites failing =
            _FailingWrites(database, DVConsent.table);
        final DVConsent consent = await open(policyV1, db: failing);
        failing.failing = true;
        final bool written =
            await consent.record(<DVConsentCategory, bool>{product: true});
        expect(written, isFalse);
        expect(consent.isGranted(product), isFalse);
        expect(consent.needsPrompt, isTrue);
        expect(reported, contains('DV-ANALYTICS-006'));
      });

      test('a withdrawal that cannot be written still stops collection, and '
          'says it was not recorded', () async {
        final _FailingWrites failing =
            _FailingWrites(database, DVConsent.table);
        final DVConsent consent = await open(policyV1, db: failing);
        await consent.record(<DVConsentCategory, bool>{product: true});
        failing.failing = true;
        final bool written =
            await consent.record(<DVConsentCategory, bool>{product: false});
        expect(written, isFalse);
        expect(consent.isGranted(product), isFalse);
        expect(reported, contains('DV-ANALYTICS-006'));
      });

      test('a required category is always granted, whatever is answered',
          () async {
        final DVConsent consent = await open(policyV1);
        await consent.record(<DVConsentCategory, bool>{
          DVConsentCategory.essential: false,
        });
        expect(consent.isGranted(DVConsentCategory.essential), isTrue);
      });

      test('an undeclared category is refused rather than silently denied',
          () async {
        final DVConsent consent = await open(policyV1);
        expect(() => consent.isGranted(const DVConsentCategory('ads')),
            throwsArgumentError);
        expect(
            () => consent.record(<DVConsentCategory, bool>{
                  const DVConsentCategory('ads'): true,
                }),
            throwsArgumentError);
      });

      test('an identity bound to a category is withheld without its grant',
          () async {
        final DVConsent consent = await open(policyV1);
        expect(consent.boundIdentity(product, userId: 'u1'), isNull);
        await consent.record(<DVConsentCategory, bool>{product: true});
        expect(consent.boundIdentity(product, userId: 'u1'), 'u1');
        await consent.record(<DVConsentCategory, bool>{product: false});
        expect(consent.boundIdentity(product, userId: 'u1'), isNull);
      });
    });

    group('the event pipeline (${adapter.$1})', () {
      late DVDatabaseAdapter database;
      late DVConsent consent;
      late DVAnalyticsDatabaseStore store;
      DateTime now = DateTime.utc(2026, 9, 14, 9);

      Future<DVAnalytics> open({
        List<DVAnalyticsProvider> providers = const <DVAnalyticsProvider>[],
        Set<String> sensitiveFields = const <String>{'card_number'},
        int sessionCap = 1000,
        int batchSize = 100,
      }) async {
        final DVAnalytics analytics = DVAnalytics(
          consent: consent,
          database: database,
          store: store,
          providers: providers,
          sensitiveFields: sensitiveFields,
          sessionCap: sessionCap,
          batchSize: batchSize,
          clock: () => now,
          onDiagnostic: report,
        );
        await analytics.ensureSchema();
        return analytics;
      }

      Future<List<DVAnalyticsRecord>> stored() => store.events();

      setUp(() async {
        database = adapter.$2();
        now = DateTime.utc(2026, 9, 14, 9);
        consent = DVConsent(
          policy: policyV1,
          database: database,
          installId: 'install-1',
          clock: () => now,
          onDiagnostic: report,
        );
        await consent.ensureSchema();
        await consent.load();
        store = DVAnalyticsDatabaseStore(database: database);
        await store.ensureSchema();
      });

      test('a denied category is dropped at the call (DV-ANALYTICS-001)',
          () async {
        final DVAnalytics analytics = await open();
        final DVTrackResult result =
            await analytics.track(const Step('viewed_pricing'));
        expect(result.accepted, isFalse);
        expect(result.code, 'DV-ANALYTICS-001');
        expect(reported, contains('DV-ANALYTICS-001'));
        expect(await analytics.pending(), 0);
        await analytics.flush();
        expect(await stored(), isEmpty);
      });

      test('events tracked before consent are not delivered once it arrives',
          () async {
        final DVAnalytics analytics = await open();
        await analytics.track(const Step('before'));
        await consent.record(<DVConsentCategory, bool>{product: true});
        await analytics.track(const Step('after'));
        await analytics.flush();
        expect((await stored()).map((DVAnalyticsRecord r) => r.name),
            <String>['after']);
      });

      test('essential events need no choice', () async {
        final DVAnalytics analytics = await open();
        await analytics
            .track(const Step('app_started', category: DVConsentCategory.essential));
        await analytics.flush();
        expect(await stored(), hasLength(1));
      });

      test('a granted event reaches the store with its version and session',
          () async {
        await consent.record(<DVConsentCategory, bool>{product: true});
        final DVAnalytics analytics = await open();
        await analytics.startSession();
        final DVTrackResult result = await analytics
            .track(const CheckoutCompleted(Order('o1', 4200, '4242'), coupon: 'X'));
        expect(result.accepted, isTrue);
        expect(await analytics.flush(), 1);
        final DVAnalyticsRecord r = (await stored()).single;
        expect(r.name, 'checkout_completed');
        expect(r.category, 'product');
        expect(r.policyVersion, '2026-09-01');
        expect(r.sessionId, analytics.sessionId);
        expect(r.occurredAt, now);
        expect(r.properties, <String, Object?>{
          'order': <String, Object?>{'id': 'o1', 'total': 4200},
          'coupon': 'X',
        });
      });

      test('withdrawal after tracking and before delivery sends nothing',
          () async {
        await consent.record(<DVConsentCategory, bool>{product: true});
        final _Provider posthog = _Provider('posthog', <DVConsentCategory>{product});
        final DVAnalytics analytics = await open(providers: <DVAnalyticsProvider>[posthog]);
        await analytics.track(const Step('queued'));
        expect(await analytics.pending(), 2);
        await consent.record(<DVConsentCategory, bool>{product: false});
        // Cleared at the withdrawal, not only filtered on the way out.
        expect(await analytics.pending(), 0);
        await analytics.flush();
        expect(await stored(), isEmpty);
        expect(posthog.received, isEmpty);
      });

      test('a queued event is checked again as it leaves, even with no change '
          'notification', () async {
        await consent.record(<DVConsentCategory, bool>{product: true});
        final DVAnalytics analytics = await open();
        await analytics.track(const Step('queued'));
        // A second consent object over the same records, as another isolate
        // or a restart would have: the analytics object hears nothing.
        final DVConsent other = DVConsent(
          policy: policyV1,
          database: database,
          installId: 'install-1',
          clock: () => now,
          onDiagnostic: report,
        );
        await other.load();
        await other.record(<DVConsentCategory, bool>{product: false});
        await consent.load();
        await analytics.flush();
        expect(await stored(), isEmpty);
      });

      test('after withdrawal, new events are dropped', () async {
        await consent.record(<DVConsentCategory, bool>{product: true});
        final DVAnalytics analytics = await open();
        await consent.record(<DVConsentCategory, bool>{product: false});
        expect((await analytics.track(const Step('later'))).accepted, isFalse);
        await analytics.flush();
        expect(await stored(), isEmpty);
      });

      test('an event naming an undeclared category is refused', () async {
        final DVAnalytics analytics = await open();
        expect(
          () => analytics
              .track(const Step('x', category: DVConsentCategory('ads'))),
          throwsArgumentError,
        );
      });

      test('a provider receives only the categories it declares', () async {
        await consent.record(
            <DVConsentCategory, bool>{product: true, marketing: true});
        final _Provider posthog = _Provider('posthog', <DVConsentCategory>{product});
        final DVAnalytics analytics = await open(providers: <DVAnalyticsProvider>[posthog]);
        await analytics.track(const Step('p'));
        await analytics.track(const Step('m', category: marketing));
        await analytics.flush();
        expect(posthog.received.map((DVAnalyticsRecord r) => r.name), <String>['p']);
        expect((await stored()).map((DVAnalyticsRecord r) => r.name).toSet(),
            <String>{'p', 'm'});
      });

      test('a provider with no consent category is DV-ANALYTICS-005', () async {
        expect(
          () => open(providers: <DVAnalyticsProvider>[
            _Provider('mixpanel', const <DVConsentCategory>{}),
          ]),
          throwsA(isA<DVAnalyticsConfigurationError>()),
        );
        expect(reported, contains('DV-ANALYTICS-005'));
      });

      test('a provider naming an undeclared category is refused', () async {
        expect(
          () => open(providers: <DVAnalyticsProvider>[
            _Provider('mixpanel', <DVConsentCategory>{const DVConsentCategory('ads')}),
          ]),
          throwsA(isA<DVAnalyticsConfigurationError>()),
        );
      });

      group('payloads', () {
        setUp(() async {
          await consent.record(<DVConsentCategory, bool>{product: true});
        });

        test('a property naming a sensitive field is refused whole '
            '(DV-ANALYTICS-004)', () async {
          final DVAnalytics analytics = await open();
          final DVTrackResult result = await analytics.track(const Step('pay',
              extra: <String, Object?>{'card_number': '4242424242424242'}));
          expect(result.accepted, isFalse);
          expect(result.code, 'DV-ANALYTICS-004');
          expect(reported, contains('DV-ANALYTICS-004'));
          await analytics.flush();
          expect(await stored(), isEmpty);
        });

        test('a sensitive field named in a nested map is refused too',
            () async {
          final DVAnalytics analytics = await open();
          final DVTrackResult result = await analytics.track(const Step('pay',
              extra: <String, Object?>{
                'payment': <String, Object?>{'Card_Number': '4242'},
              }));
          expect(result.code, 'DV-ANALYTICS-004');
          await analytics.flush();
          expect(jsonEncode((await stored()).map((DVAnalyticsRecord r) => r.toJson()).toList()),
              isNot(contains('4242')));
        });

        test('a model is serialized through its public shape', () async {
          final DVAnalytics analytics = await open();
          await analytics
              .track(const CheckoutCompleted(Order('o1', 10, '4242424242424242')));
          await analytics.flush();
          final String row = jsonEncode((await stored()).single.toJson());
          expect(row, isNot(contains('4242424242424242')));
          expect(row, contains('o1'));
        });

        test('an object with only an internal form loses its sensitive fields',
            () async {
          final DVAnalytics analytics = await open();
          final DVTrackResult result = await analytics
              .track(const CheckoutCompleted(LegacyOrder('o2', '4242424242424242')));
          expect(result.accepted, isTrue);
          await analytics.flush();
          final String row = jsonEncode((await stored()).single.toJson());
          expect(row, isNot(contains('4242424242424242')));
          expect(row, contains('o2'));
        });

        test('credential-shaped keys and resolved secrets are redacted',
            () async {
          DVSecrets.configure(<String, String>{'STRIPE_KEY': 'sk_live_abcdefgh123'});
          final String secret = const DVSecrets().get('STRIPE_KEY');
          final DVAnalytics analytics = await open();
          await analytics.track(Step('call', extra: <String, Object?>{
            'password': 'hunter22',
            'url': 'https://api.example/charge?key=$secret',
          }));
          await analytics.flush();
          final String row = jsonEncode((await stored()).single.toJson());
          expect(row, isNot(contains('hunter22')));
          expect(row, isNot(contains(secret)));
        });

        test('a value with no analytics shape is refused, not stringified',
            () async {
          final DVAnalytics analytics = await open();
          final DVTrackResult result = await analytics
              .track(Step('odd', extra: <String, Object?>{'who': Opaque()}));
          expect(result.accepted, isFalse);
          await analytics.flush();
          expect(jsonEncode((await stored()).map((DVAnalyticsRecord r) => r.toJson()).toList()),
              isNot(contains('ada@example.com')));
        });
      });

      group('the session cap', () {
        setUp(() async {
          await consent.record(<DVConsentCategory, bool>{product: true});
        });

        test('drops a runaway past the cap, says so once, and samples nothing '
            'below it', () async {
          final DVAnalytics analytics =
              await open(sessionCap: 50, batchSize: 500);
          await analytics.startSession();
          for (int i = 0; i < 400; i++) {
            await analytics.track(const Step('loop'));
          }
          for (int i = 0; i < 30; i++) {
            await analytics.track(const Step('other'));
          }
          await analytics.flush();
          final List<DVAnalyticsRecord> rows = await stored();
          expect(rows.where((DVAnalyticsRecord r) => r.name == 'loop'), hasLength(50));
          expect(rows.where((DVAnalyticsRecord r) => r.name == 'other'), hasLength(30));
          expect(reported.where((String c) => c == 'DV-ANALYTICS-003'), hasLength(1));
        });

        test('a new session starts a new count', () async {
          final DVAnalytics analytics = await open(sessionCap: 5);
          await analytics.startSession();
          for (int i = 0; i < 10; i++) {
            await analytics.track(const Step('loop'));
          }
          await analytics.startSession();
          for (int i = 0; i < 10; i++) {
            await analytics.track(const Step('loop'));
          }
          await analytics.flush();
          expect(await stored(), hasLength(10));
        });
      });

      group('delivery', () {
        setUp(() async {
          await consent.record(<DVConsentCategory, bool>{product: true});
        });

        test('sends in batches of batchSize', () async {
          final _Provider posthog = _Provider('posthog', <DVConsentCategory>{product});
          final DVAnalytics analytics = await open(
              providers: <DVAnalyticsProvider>[posthog], batchSize: 10);
          for (int i = 0; i < 25; i++) {
            await analytics.track(Step('e$i'));
          }
          expect(await analytics.flush(), 50);
          expect(posthog.sends, 3);
          expect(posthog.received.map((DVAnalyticsRecord r) => r.name).toList(),
              <String>[for (int i = 0; i < 25; i++) 'e$i']);
        });

        test('a failing provider keeps its events, and the store is not sent '
            'them twice', () async {
          final _Provider posthog =
              _Provider('posthog', <DVConsentCategory>{product}, failing: true);
          final DVAnalytics analytics = await open(providers: <DVAnalyticsProvider>[posthog]);
          await analytics.track(const Step('a'));
          await analytics.track(const Step('b'));
          await analytics.flush();
          expect(await stored(), hasLength(2));
          expect(posthog.received, isEmpty);
          expect(await analytics.pending(), 2);

          posthog.failing = false;
          await analytics.flush();
          await analytics.flush();
          expect(await stored(), hasLength(2));
          expect(posthog.received.map((DVAnalyticsRecord r) => r.name), <String>['a', 'b']);
          expect(await analytics.pending(), 0);
        });

        test('the store ignores a batch it already holds', () async {
          final DVAnalytics analytics = await open();
          await analytics.track(const Step('once'));
          await analytics.flush();
          final List<DVAnalyticsRecord> rows = await stored();
          await store.send(rows);
          expect(await stored(), hasLength(1));
        });

        test('events queued survive a restart of the process', () async {
          final _Provider posthog =
              _Provider('posthog', <DVConsentCategory>{product}, failing: true);
          final DVAnalytics first = await open(providers: <DVAnalyticsProvider>[posthog]);
          await first.track(const Step('kept'));
          await first.flush();
          final _Provider back = _Provider('posthog', <DVConsentCategory>{product});
          final DVAnalytics second = await open(providers: <DVAnalyticsProvider>[back]);
          await second.flush();
          expect(back.received.map((DVAnalyticsRecord r) => r.name), <String>['kept']);
        });

        test('a queued flush job delivers', () async {
          const DVQueues queues = DVQueues();
          queues.useAdapter(DVInMemoryQueueAdapter());
          final DVAnalytics analytics = await open();
          analytics.registerJobs(queues);
          await analytics.track(const Step('via_queue'));
          await analytics.requestFlush(queues: queues);
          expect(await queues.work(), 1);
          expect(await stored(), hasLength(1));
        });
      });

      group('identity', () {
        setUp(() async {
          await consent.record(<DVConsentCategory, bool>{product: true});
        });

        test('no row carries both an anonymous id and a user id', () async {
          final DVAnalytics analytics = await open();
          await analytics.startSession();
          await analytics.track(const Step('anonymous'));
          analytics.identify('u1');
          await analytics.track(const Step('signed_in'));
          await analytics.flush();
          final List<DVAnalyticsRecord> rows = await stored();
          final DVAnalyticsRecord before =
              rows.firstWhere((DVAnalyticsRecord r) => r.name == 'anonymous');
          final DVAnalyticsRecord after =
              rows.firstWhere((DVAnalyticsRecord r) => r.name == 'signed_in');
          expect(before.userId, isNull);
          expect(before.anonymousId, isNotNull);
          expect(after.userId, 'u1');
          expect(after.anonymousId, isNull);
          // Nor is the pair joined by a session both belong to.
          expect(after.sessionId, isNot(before.sessionId));
        });

        test('the anonymous id is not the install id crash reports carry',
            () async {
          final DVAnalytics analytics = await open();
          expect(analytics.anonymousId, isNot('install-1'));
        });

        test('a withdrawal starts a new anonymous id and session, so what came '
            'before cannot be joined to what comes after', () async {
          final DVAnalytics analytics = await open();
          await analytics.startSession();
          await analytics.track(const Step('before'));
          await analytics.flush();
          await consent.record(<DVConsentCategory, bool>{product: false});
          await consent.record(<DVConsentCategory, bool>{product: true});
          await analytics.track(const Step('after'));
          await analytics.flush();
          final List<DVAnalyticsRecord> rows = await stored();
          final DVAnalyticsRecord before =
              rows.firstWhere((DVAnalyticsRecord r) => r.name == 'before');
          final DVAnalyticsRecord after =
              rows.firstWhere((DVAnalyticsRecord r) => r.name == 'after');
          expect(after.anonymousId, isNot(before.anonymousId));
          expect(after.sessionId, isNot(before.sessionId));
        });

        test('the new anonymous id outlives a restart', () async {
          final DVAnalytics analytics = await open();
          final String first = analytics.anonymousId;
          await consent.record(<DVConsentCategory, bool>{product: false});
          await analytics.idle;
          final String rotated = analytics.anonymousId;
          expect(rotated, isNot(first));
          final DVAnalytics restarted = await open();
          expect(restarted.anonymousId, rotated);
        });

        test('signing out starts a new anonymous id', () async {
          final DVAnalytics analytics = await open();
          final String first = analytics.anonymousId;
          analytics.identify('u1');
          analytics.identify(null);
          await analytics.track(const Step('next_person'));
          await analytics.flush();
          expect((await stored()).single.anonymousId, isNot(first));
        });
      });

      group('erasure and export', () {
        late DVPrivacy privacy;
        late DVAnalytics analytics;
        late _ErasableProvider posthog;

        Future<void> seed() async {
          await consent.record(<DVConsentCategory, bool>{product: true},
              userId: 'u1');
          analytics.identify('u1');
          await analytics.track(const Step('u1_event'));
          await analytics.flush();
          await analytics.track(const Step('u1_unsent'));
          analytics.identify('u2');
          await analytics.track(const Step('u2_event'));
          await analytics.flush(sinks: <String>{DVAnalytics.storeName});
        }

        setUp(() async {
          posthog = _ErasableProvider('posthog', <DVConsentCategory>{product});
          analytics = await open(providers: <DVAnalyticsProvider>[posthog]);
          final DVRecordTable users = DVRecordTable(
            table: 'users',
            key: 'id',
            columns: const <String>['id', 'email'],
            database: database,
          );
          await users.ensureSchema();
          await users.write(<String, Object?>{'id': 'u1', 'email': 'a@x'});
          privacy = DVPrivacy(
            models: <DVPrivacyModel>[
              DVPrivacyModel(
                name: 'users',
                table: users,
                subject: DVSubject.self,
                personal: const <String>{'email'},
                retention: DVRetention.indefinite,
              ),
            ],
            database: database,
            signingKey: _signingKey,
            adapters: analytics.privacyAdapters(),
          );
          await privacy.ensureSchema();
        });

        test('an erased subject has no events left anywhere analytics keeps '
            'them, and nobody else loses theirs', () async {
          await seed();
          final DVErasureResult result =
              await privacy.erase(subject: 'u1', reason: 'request');
          expect(result.complete, isTrue);

          final List<DVAnalyticsRecord> rows = await stored();
          expect(rows.where((DVAnalyticsRecord r) => r.userId == 'u1'), isEmpty);
          expect(rows.map((DVAnalyticsRecord r) => r.name), contains('u2_event'));
          expect(posthog.erased, <String>['u1']);

          // Nothing unsent for u1 goes out after the erasure either.
          await analytics.flush();
          expect(posthog.received.where((DVAnalyticsRecord r) => r.userId == 'u1'),
              isEmpty);
          expect(
              (await stored()).where((DVAnalyticsRecord r) => r.userId == 'u1'),
              isEmpty);
        });

        test('consent records outlive the erasure, by pseudonym and with no '
            'personal field (DV-PRIVACY-010)', () async {
          final DVMemoryLogSink logs = DVMemoryLogSink();
          final DVLogger previous = DVObservability.logger;
          DVObservability.logger = DVLogger(sinks: <DVLogSink>[logs]);
          addTearDown(() => DVObservability.logger = previous);

          await seed();
          await privacy.erase(subject: 'u1', reason: 'request');

          // The install id links the record to a device, which is personal
          // data too, so it goes the way of the user id.
          expect(await consent.records(subject: 'u1'), isEmpty);
          expect(await consent.records(subject: 'install-1'), isEmpty);
          final List<DVConsentRecord> kept =
              await consent.records(subject: privacy.pseudonym('u1'));
          expect(kept, hasLength(1));
          final DVConsentRecord r = kept.single;
          expect(r.userId, privacy.pseudonym('u1'));
          expect(r.installId, privacy.pseudonym('u1'));
          expect(r.answers, <String, bool>{'product': true});
          expect(r.policyVersion, '2026-09-01');
          expect(jsonEncode(r.toJson()), isNot(contains('"u1"')));
          expect(logs.records.map((DVLogRecord l) => l.code),
              contains('DV-PRIVACY-010'));
        });

        test('a provider that cannot erase leaves the erasure incomplete',
            () async {
          final _Provider mixpanel = _Provider('mixpanel', <DVConsentCategory>{product});
          final DVAnalytics withMixpanel =
              await open(providers: <DVAnalyticsProvider>[mixpanel]);
          final DVPrivacy p = DVPrivacy(
            models: privacy.models,
            database: database,
            signingKey: _signingKey,
            adapters: withMixpanel.privacyAdapters(),
          );
          final DVErasureResult result =
              await p.erase(subject: 'u1', reason: 'request');
          expect(result.complete, isFalse);
          expect(result.unreached, <String>['analytics:mixpanel']);
          expect(result.codes, contains('DV-PRIVACY-009'));
        });

        test('an erasure by install id removes that device\'s anonymous events',
            () async {
          await consent.record(<DVConsentCategory, bool>{product: true});
          await analytics.track(const Step('anon'));
          await analytics.flush();
          final String anon = analytics.anonymousId;
          // Stored first, or the erasure below has nothing to prove.
          expect(
              (await stored()).where((DVAnalyticsRecord r) => r.anonymousId == anon),
              hasLength(1));
          await privacy.erase(subject: anon, reason: 'request');
          expect(
              (await stored()).where((DVAnalyticsRecord r) => r.anonymousId == anon),
              isEmpty);
        });

        test('export carries the subject\'s events and consent records only',
            () async {
          await seed();
          final DVExportArchive archive = await privacy.export(subject: 'u1');
          final Map<String, Object?> events =
              archive.adapters['analytics:events']!;
          final String text = jsonEncode(events);
          expect(text, contains('u1_event'));
          expect(text, contains('u1_unsent'));
          expect(text, isNot(contains('u2_event')));
          expect(jsonEncode(archive.adapters['analytics:consent']),
              contains('2026-09-01'));
          expect(jsonEncode(archive.adapters['analytics:posthog']),
              contains('u1_event'));
        });
      });

      group('funnels', () {
        test('count subjects reaching each step in order', () async {
          await consent.record(<DVConsentCategory, bool>{product: true});
          final DVAnalytics analytics = await open();
          Future<void> person(String id, List<String> steps) async {
            analytics.identify(id);
            for (final String s in steps) {
              now = now.add(const Duration(seconds: 1));
              await analytics.track(Step(s));
            }
          }

          await person('a', <String>['view', 'cart', 'pay']);
          await person('b', <String>['view', 'cart']);
          await person('c', <String>['cart', 'view']); // out of order
          await person('d', <String>['view']);
          await analytics.flush();
          expect(await store.funnel(<String>['view', 'cart', 'pay']),
              <int>[4, 2, 1]);
        });
      });

      group('feature flag exposure', () {
        final DVFeatureFlag<bool> newCheckout = DVFeatureFlag<bool>(
          key: 'newCheckout',
          defaultValue: false,
          owner: 'payments',
          expires: DateTime.utc(2027, 1, 1),
        );

        test('is recorded as dartvel.flag_exposed when consent allows',
            () async {
          await consent.record(<DVConsentCategory, bool>{product: true});
          final DVAnalytics analytics = await open();
          analytics.connectFlags(category: product);
          DVFlags.onDiagnostic = report;
          DVFlags.setRules(DVFlagRules.fromJson(<String, Object?>{
            'format': 1,
            'rulesVersion': 7,
            'flags': <String, Object?>{
              'newCheckout': <Object?>[
                <String, Object?>{'value': true},
              ],
            },
          }));
          DVFlags.context = () => const DVFlagContext(userId: 'u1');
          expect(newCheckout.value, isTrue);
          expect(newCheckout.value, isTrue);
          await analytics.flush();
          final DVAnalyticsRecord r = (await stored()).single;
          expect(r.name, 'dartvel.flag_exposed');
          expect(r.properties, <String, Object?>{
            'flag': 'newCheckout',
            'value': true,
            'rulesVersion': 7,
          });
        });

        test('records nothing without consent and says so (DV-FLAGS-007)',
            () async {
          final DVAnalytics analytics = await open();
          analytics.connectFlags(category: product);
          DVFlags.onDiagnostic = report;
          expect(newCheckout.value, isFalse);
          await analytics.flush();
          expect(await stored(), isEmpty);
          expect(reported, contains('DV-FLAGS-007'));
        });
      });
    });
  }
}
