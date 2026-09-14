// What a crash report says about who and what: an identity bound to consent,
// and the flags in force when it happened.
//
// A crash report is sent without an analytics grant, because the application
// cannot be fixed otherwise. That is exactly why the identity on it has to be
// bound: a report is the one thing that leaves the device before anybody has
// been asked, so a user id that rides along with it by default is collected
// from everybody who never said yes. Each silent failure here produces a
// report that looks right:
//
//  * a user id attached with no grant;
//  * a grant withdrawn and the id still attached;
//  * a consent policy that does not declare the category, which throws inside
//    the crash handler and loses the report it was writing;
//  * a flags snapshot that records an exposure — so a crash counts somebody
//    into an experiment — or that is taken when the report is sent, a launch
//    later, under different rules.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVConsentCategory crashIdentity = DVConsentCategory('crash_identity');

final DVConsentPolicy policy = DVConsentPolicy(
  version: '2026-09-01',
  categories: const <DVConsentDeclaration>[
    DVConsentDeclaration(DVConsentCategory.essential, required: true),
    DVConsentDeclaration(crashIdentity),
  ],
);

Future<DVConsent> openConsent() async {
  final DVConsent consent = DVConsent(
    policy: policy,
    database: MemoryDVDatabaseAdapter(),
    installId: 'install-1',
    onDiagnostic: (String code, String message) {},
  );
  await consent.ensureSchema();
  await consent.load();
  return consent;
}

DVCrashReporting reporter(
  DVMemoryCrashStore store, {
  DVCrashIdentity? identity,
  Map<String, Object?> Function()? flags,
}) =>
    DVCrashReporting(
      store: store,
      context: () => DVCrashContext(
        release: '1.0.0',
        installId: 'install-1',
        userId: identity?.userId,
      ),
      flags: flags,
      onDiagnostic: (String code, String message) {},
    );

DVCrashReport only(DVMemoryCrashStore store) =>
    store.pending().single.report!;

enum Tier { free, gold }

final DVFeatureFlag<bool> newCheckout = DVFeatureFlag<bool>(
  key: 'newCheckout',
  defaultValue: false,
  owner: 'payments',
  expires: DateTime.utc(2099),
);

final DVFeatureFlag<Tier> tier = DVFeatureFlag<Tier>(
  key: 'tier',
  defaultValue: Tier.free,
  owner: 'growth',
  expires: DateTime.utc(2099),
  values: Tier.values,
);

DVFlagRules rules({required bool checkout}) => DVFlagRules(
      rulesVersion: 3,
      flags: <String, List<DVFlagRule>>{
        'newCheckout': <DVFlagRule>[DVFlagRule(value: checkout)],
        'tier': const <DVFlagRule>[DVFlagRule(value: 'gold')],
      },
    );

void main() {
  group('identity, bound to consent', () {
    test('no grant: no user id on the report, and the report still arrives',
        () async {
      final DVConsent consent = await openConsent();
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashIdentity identity = DVCrashIdentity(category: crashIdentity)
        ..identify('user-42', consent: consent);

      reporter(store, identity: identity)
          .record(StateError('boom'), StackTrace.current, fatal: true);

      expect(only(store).context.userId, isNull);
      expect(only(store).toJson()['context'], isNot(contains('userId')));
    });

    test('granted: the user id is on the report and survives the round trip',
        () async {
      final DVConsent consent = await openConsent();
      await consent.record(<DVConsentCategory, bool>{crashIdentity: true});
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashIdentity identity = DVCrashIdentity(category: crashIdentity)
        ..identify('user-42', consent: consent);

      reporter(store, identity: identity)
          .record(StateError('boom'), StackTrace.current, fatal: true);

      expect(only(store).context.userId, 'user-42');
    });

    test('withdrawn: the next report carries none', () async {
      final DVConsent consent = await openConsent();
      await consent.record(<DVConsentCategory, bool>{crashIdentity: true});
      final DVCrashIdentity identity = DVCrashIdentity(category: crashIdentity)
        ..identify('user-42', consent: consent);
      expect(identity.userId, 'user-42');

      await consent.record(<DVConsentCategory, bool>{crashIdentity: false});

      expect(identity.userId, isNull);
    });

    test('a category the policy does not declare is no identity, and the '
        'report is still written', () async {
      final DVConsent consent = await openConsent();
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVCrashIdentity identity =
          DVCrashIdentity(category: const DVConsentCategory('undeclared'))
            ..identify('user-42', consent: consent);

      expect(
        () => reporter(store, identity: identity)
            .record(StateError('boom'), StackTrace.current, fatal: true),
        returnsNormally,
      );
      expect(store.raw, hasLength(1));
      expect(only(store).context.userId, isNull);
    });

    test('nobody identified, or identify(null), is no identity', () async {
      final DVConsent consent = await openConsent();
      await consent.record(<DVConsentCategory, bool>{crashIdentity: true});
      final DVCrashIdentity identity = DVCrashIdentity(category: crashIdentity);
      expect(identity.userId, isNull);

      identity
        ..identify('user-42', consent: consent)
        ..identify(null, consent: consent);
      expect(identity.userId, isNull);
    });
  });

  group('the flags in force when it happened', () {
    setUp(DVFlags.resetForTest);
    tearDown(DVFlags.resetForTest);

    test('each declared flag, as it answers now, enums by name', () {
      DVFlags.declare(<DVFeatureFlag<Object?>>[newCheckout, tier]);
      DVFlags.setRules(rules(checkout: true));

      expect(dvCrashFlagsSnapshot(), <String, Object?>{
        'newCheckout': true,
        'tier': 'gold',
      });
    });

    test('taking it records no exposure and reports nothing', () {
      final List<DVFlagExposure> exposures = <DVFlagExposure>[];
      final List<String> codes = <String>[];
      DVFlags.onExposure = exposures.add;
      DVFlags.onDiagnostic = (String code, String message) => codes.add(code);
      // No rules synced: resolve() would report DV-FLAGS-001.
      DVFlags.declare(<DVFeatureFlag<Object?>>[newCheckout]);

      expect(dvCrashFlagsSnapshot(), <String, Object?>{'newCheckout': false});
      expect(exposures, isEmpty);
      expect(codes, isEmpty);
    });

    test('a context that throws is an empty snapshot, and the report is '
        'still written', () {
      DVFlags.declare(<DVFeatureFlag<Object?>>[newCheckout]);
      DVFlags.context = () => throw StateError('no tenant');
      final DVMemoryCrashStore store = DVMemoryCrashStore();

      expect(dvCrashFlagsSnapshot(), isEmpty);
      reporter(store, flags: dvCrashFlagsSnapshot)
          .record(StateError('boom'), StackTrace.current, fatal: true);
      expect(store.raw, hasLength(1));
    });

    test('a flag settled on next launch is the answer this process kept', () {
      // The application read it once and is running on that answer until it
      // restarts. A snapshot evaluated fresh would name the new rule's value:
      // a report claiming a flag the crashing code never saw.
      final DVFeatureFlag<bool> pinned = DVFeatureFlag<bool>(
        key: 'pinnedCheckout',
        defaultValue: false,
        owner: 'payments',
        expires: DateTime.utc(2099),
        settle: DVFlagSettle.onNextLaunch,
      );
      DVFlags.declare(<DVFeatureFlag<Object?>>[pinned]);
      DVFlags.setRules(const DVFlagRules(
        rulesVersion: 1,
        flags: <String, List<DVFlagRule>>{
          'pinnedCheckout': <DVFlagRule>[DVFlagRule(value: true)],
        },
      ));
      expect(pinned.value, isTrue);
      DVFlags.setRules(const DVFlagRules(
        rulesVersion: 2,
        flags: <String, List<DVFlagRule>>{
          'pinnedCheckout': <DVFlagRule>[DVFlagRule(value: false)],
        },
      ));
      expect(pinned.value, isTrue);

      expect(dvCrashFlagsSnapshot()['pinnedCheckout'], isTrue);
    });

    test('taken at record time, not when the report is sent', () {
      DVFlags.declare(<DVFeatureFlag<Object?>>[newCheckout, tier]);
      DVFlags.setRules(rules(checkout: true));
      final DVMemoryCrashStore store = DVMemoryCrashStore();

      reporter(store, flags: dvCrashFlagsSnapshot)
          .record(StateError('boom'), StackTrace.current, fatal: true);
      DVFlags.setRules(rules(checkout: false));

      expect(only(store).flags['newCheckout'], isTrue);
    });
  });
}
