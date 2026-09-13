// Feature flags: declared, typed, dated, and answered the same way everywhere.
//
// The failures worth the most test effort here are the silent ones. A rollout
// that re-buckets a user on every read looks like a working 25% — until the
// same person sees the new checkout, then the old one, then the new one. A flag
// the synced rules do not mention that answers `true` looks like a working
// launch. A rule whose value is the wrong type that gets coerced looks like a
// working config. None of those throws, so each is asserted on directly.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

enum Recommender { baseline, embeddings }

final DVFeatureFlag<bool> newCheckout = DVFeatureFlag<bool>(
  key: 'newCheckout',
  defaultValue: false,
  owner: 'payments',
  expires: DateTime.utc(2026, 12, 1),
);

final DVFeatureFlag<String> recommenderName = DVFeatureFlag<String>(
  key: 'recommender',
  defaultValue: 'baseline',
  owner: 'search',
  expires: DateTime.utc(2026, 11, 1),
);

final DVFeatureFlag<int> pageSize = DVFeatureFlag<int>(
  key: 'pageSize',
  defaultValue: 20,
  owner: 'feed',
  expires: DateTime.utc(2027, 2, 1),
);

final DVFeatureFlag<double> sampleRate = DVFeatureFlag<double>(
  key: 'sampleRate',
  defaultValue: 0.1,
  owner: 'obs',
  expires: DateTime.utc(2027, 2, 1),
);

final DVFeatureFlag<Recommender> recommender = DVFeatureFlag<Recommender>(
  key: 'recommenderKind',
  defaultValue: Recommender.baseline,
  owner: 'search',
  expires: DateTime.utc(2027, 2, 1),
  values: Recommender.values,
);

DVFlagRules rules(Map<String, Object?> flags, {int version = 1}) =>
    DVFlagRules.fromJson(<String, Object?>{
      'format': 1,
      'rulesVersion': version,
      'flags': flags,
    });

const DVFlagContext alice = DVFlagContext(
  userId: 'alice',
  tenantId: 'acme',
  deviceId: 'device-1',
  platform: 'ios',
  appVersion: '2.3.0',
  locale: 'en-GB',
);

void main() {
  late List<String> reported;

  setUp(() {
    DVFlags.resetForTest();
    reported = <String>[];
    DVFlags.onDiagnostic = (String code, String message) => reported.add(code);
  });

  group('the bucket', () {
    test('is the first eight bytes of SHA-256 of "key:subject", mod 10,000',
        () {
      // Computed independently here rather than read back from the code under
      // test, so a change to the arithmetic cannot agree with itself.
      final List<int> digest =
          sha256.convert(utf8.encode('newCheckout:alice')).bytes;
      BigInt value = BigInt.zero;
      for (int i = 0; i < 8; i++) {
        value = (value << 8) | BigInt.from(digest[i]);
      }
      final int expected = (value % BigInt.from(10000)).toInt();

      expect(DVFlagRollout.bucket('newCheckout', 'alice'), expected);
    });

    test('is stable: the same subject gets the same answer on every read', () {
      final int first = DVFlagRollout.bucket('newCheckout', 'alice');
      for (int i = 0; i < 50; i++) {
        expect(DVFlagRollout.bucket('newCheckout', 'alice'), first);
      }
    });

    test('differs between flags, so two 10% rollouts pick different tenths',
        () {
      int same = 0;
      for (int i = 0; i < 2000; i++) {
        final bool a = DVFlagRollout.bucket('flagA', 'user-$i') < 1000;
        final bool b = DVFlagRollout.bucket('flagB', 'user-$i') < 1000;
        if (a && b) same++;
      }
      // Independent 10% draws overlap in about 1% of subjects (~20 of 2000).
      // The same draw would overlap in all ~200.
      expect(same, lessThan(60));
    });

    test('raising a percentage never drops anyone who was already in', () {
      for (int i = 0; i < 500; i++) {
        final DVFlagContext who = DVFlagContext(userId: 'user-$i');
        final bool atTen = DVFlags.evaluate(
          newCheckout,
          rules(<String, Object?>{
            'newCheckout': <Object?>[
              <String, Object?>{
                'value': true,
                'rollout': <String, Object?>{'percentage': 10, 'by': 'user'},
              },
            ],
          }),
          who,
        ).value;
        final bool atTwenty = DVFlags.evaluate(
          newCheckout,
          rules(<String, Object?>{
            'newCheckout': <Object?>[
              <String, Object?>{
                'value': true,
                'rollout': <String, Object?>{'percentage': 20, 'by': 'user'},
              },
            ],
          }),
          who,
        ).value;
        if (atTen) expect(atTwenty, isTrue, reason: 'user-$i fell out');
      }
    });

    test('a 25% rollout serves roughly a quarter', () {
      final DVFlagRules r = rules(<String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{
            'value': true,
            'rollout': <String, Object?>{'percentage': 25, 'by': 'user'},
          },
        ],
      });
      int on = 0;
      for (int i = 0; i < 4000; i++) {
        if (DVFlags.evaluate(newCheckout, r, DVFlagContext(userId: 'u$i'))
            .value) {
          on++;
        }
      }
      expect(on, inInclusiveRange(880, 1120));
    });
  });

  group('resolution order', () {
    test('with no rule set synced, the compiled default answers, and says so '
        'once', () {
      expect(DVFlags.resolve(newCheckout).value, isFalse);
      expect(DVFlags.resolve(newCheckout).source, DVFlagSource.defaults);
      DVFlags.resolve(pageSize);
      expect(reported.where((String c) => c == 'DV-FLAGS-001'), hasLength(1));
    });

    test('a flag the rules do not mention answers its default, not true', () {
      DVFlags.setRules(rules(<String, Object?>{
        'somethingElse': <Object?>[
          <String, Object?>{'value': true},
        ],
      }));
      final DVFlagResolution<bool> r = DVFlags.resolve(newCheckout);
      expect(r.value, isFalse);
      expect(r.source, DVFlagSource.defaults);
    });

    test('the synced rules win over the default', () {
      DVFlags.setRules(rules(<String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{'value': true},
        ],
        'pageSize': <Object?>[
          <String, Object?>{'value': 50},
        ],
      }, version: 7));
      final DVFlagResolution<bool> r = DVFlags.resolve(newCheckout);
      expect(r.value, isTrue);
      expect(r.source, DVFlagSource.rules);
      expect(r.rulesVersion, 7);
      expect(DVFlags.resolve(pageSize).value, 50);
    });

    test('an override wins in a debug build, and reports each time', () async {
      DVFlags.setRules(rules(<String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{'value': false},
        ],
      }));
      await DVFlags.withOverrides(<String, Object?>{'newCheckout': true},
          () async {
        expect(DVFlags.resolve(newCheckout).value, isTrue);
        expect(DVFlags.resolve(newCheckout).source, DVFlagSource.override);
        DVFlags.resolve(newCheckout);
      });
      expect(reported.where((String c) => c == 'DV-FLAGS-008'), hasLength(3));
    });

    test('overrides are scoped to the callback and do not leak', () async {
      await DVFlags.withOverrides(<String, Object?>{'newCheckout': true},
          () async {
        await Future<void>.delayed(Duration.zero);
        expect(DVFlags.resolve(newCheckout).value, isTrue);
      });
      expect(DVFlags.resolve(newCheckout).value, isFalse);
    });

    test('a release build has no code path that reads an override', () {
      final DVFlagResolution<bool> r = DVFlags.evaluate(
        newCheckout,
        null,
        alice,
        overrides: <String, Object?>{'newCheckout': true},
        allowOverrides: false,
      );
      expect(r.value, isFalse);
      expect(r.source, DVFlagSource.defaults);
    });
  });

  group('targeting', () {
    DVFlagRules targeted(Map<String, Object?> target) =>
        rules(<String, Object?>{
          'newCheckout': <Object?>[
            <String, Object?>{'value': true, 'target': target},
          ],
        });

    test('by platform, tenant, role, locale, app version and attribute', () {
      expect(
          DVFlags.evaluate(newCheckout,
                  targeted(<String, Object?>{'platforms': <String>['ios']}), alice)
              .value,
          isTrue);
      expect(
          DVFlags.evaluate(
                  newCheckout,
                  targeted(<String, Object?>{
                    'platforms': <String>['android']
                  }),
                  alice)
              .value,
          isFalse);
      expect(
          DVFlags.evaluate(newCheckout,
                  targeted(<String, Object?>{'tenants': <String>['acme']}), alice)
              .value,
          isTrue);
      expect(
          DVFlags.evaluate(
                  newCheckout,
                  targeted(<String, Object?>{
                    'organizationRoles': <String>['admin']
                  }),
                  alice)
              .value,
          isFalse);
      expect(
          DVFlags.evaluate(newCheckout,
                  targeted(<String, Object?>{'locales': <String>['en-GB']}), alice)
              .value,
          isTrue);
      expect(
          DVFlags.evaluate(
                  newCheckout,
                  targeted(<String, Object?>{
                    'appVersion': <String, Object?>{
                      'min': '2.0.0',
                      'max': '2.4.0'
                    }
                  }),
                  alice)
              .value,
          isTrue);
      expect(
          DVFlags.evaluate(
                  newCheckout,
                  targeted(<String, Object?>{
                    'appVersion': <String, Object?>{'min': '2.10.0'}
                  }),
                  alice)
              .value,
          isFalse,
          reason: '2.3.0 is below 2.10.0 numerically, not lexically');
      expect(
          DVFlags.evaluate(
                  newCheckout,
                  targeted(<String, Object?>{
                    'attributes': <String, Object?>{'beta': true}
                  }),
                  const DVFlagContext(
                      userId: 'x', attributes: <String, Object?>{'beta': true}))
              .value,
          isTrue);
    });

    test('a rollout composes inside a targeted population', () {
      final DVFlagRules r = rules(<String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{
            'value': true,
            'target': <String, Object?>{'platforms': <String>['ios']},
            'rollout': <String, Object?>{'percentage': 100, 'by': 'user'},
          },
        ],
      });
      expect(DVFlags.evaluate(newCheckout, r, alice).value, isTrue);
      expect(
          DVFlags.evaluate(newCheckout, r,
                  const DVFlagContext(userId: 'alice', platform: 'android'))
              .value,
          isFalse);
    });

    test('a rollout with no subject holds the default and does not roll a die',
        () {
      final DVFlagRules r = rules(<String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{
            'value': true,
            'rollout': <String, Object?>{'percentage': 100, 'by': 'user'},
          },
        ],
      });
      for (int i = 0; i < 20; i++) {
        final DVFlagResolution<bool> res =
            DVFlags.evaluate(newCheckout, r, const DVFlagContext());
        expect(res.value, isFalse);
        expect(res.codes, contains('DV-FLAGS-005'));
      }
    });
  });

  group('types', () {
    test('int, double, String and enum flags read their typed values', () {
      final DVFlagRules r = rules(<String, Object?>{
        'pageSize': <Object?>[
          <String, Object?>{'value': 40},
        ],
        'sampleRate': <Object?>[
          <String, Object?>{'value': 1},
        ],
        'recommender': <Object?>[
          <String, Object?>{'value': 'embeddings'},
        ],
        'recommenderKind': <Object?>[
          <String, Object?>{'value': 'embeddings'},
        ],
      });
      expect(DVFlags.evaluate(pageSize, r, alice).value, 40);
      expect(DVFlags.evaluate(sampleRate, r, alice).value, 1.0);
      expect(DVFlags.evaluate(recommenderName, r, alice).value, 'embeddings');
      expect(DVFlags.evaluate(recommender, r, alice).value,
          Recommender.embeddings);
    });

    test('a value of the wrong type holds the default instead of coercing', () {
      final DVFlagRules r = rules(<String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{'value': 'true'},
        ],
        'pageSize': <Object?>[
          <String, Object?>{'value': 2.5},
        ],
        'recommenderKind': <Object?>[
          <String, Object?>{'value': 'nonsense'},
        ],
      });
      final DVFlagResolution<bool> a = DVFlags.evaluate(newCheckout, r, alice);
      expect(a.value, isFalse);
      expect(a.codes, contains('DV-FLAGS-006'));
      expect(DVFlags.evaluate(pageSize, r, alice).value, 20);
      expect(DVFlags.evaluate(recommender, r, alice).value,
          Recommender.baseline);
    });
  });

  group('the rule set', () {
    test('round-trips through JSON', () {
      final DVFlagRules r = rules(<String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{
            'value': true,
            'target': <String, Object?>{'platforms': <String>['ios']},
            'rollout': <String, Object?>{'percentage': 25, 'by': 'tenant'},
          },
        ],
      }, version: 3);
      final DVFlagRules back =
          DVFlagRules.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>);
      expect(back.toJson(), r.toJson());
      expect(back.rulesVersion, 3);
    });

    test('a format newer than this build skips what it cannot read and says so',
        () {
      final DVFlagRules r = DVFlagRules.fromJson(<String, Object?>{
        'format': 99,
        'rulesVersion': 1,
        'flags': <String, Object?>{
          'newCheckout': <Object?>[
            <String, Object?>{'value': true},
            <String, Object?>{
              'value': true,
              'rollout': <String, Object?>{'percentage': 50, 'by': 'planet'},
            },
          ],
        },
      }, report: (String code, String _) => reported.add(code));
      expect(reported, contains('DV-FLAGS-003'));
      expect(r.flags['newCheckout'], hasLength(1));
    });

    test('rules naming a flag this build does not declare are reported', () {
      DVFlags.declare(<DVFeatureFlag<Object?>>[newCheckout]);
      DVFlags.setRules(rules(<String, Object?>{
        'ghost': <Object?>[
          <String, Object?>{'value': true},
        ],
      }));
      expect(reported, contains('DV-FLAGS-002'));
    });

    test('stale rules stay in force, and past maxAge they report each read',
        () {
      DVFlags.maxAge = const Duration(hours: 1);
      DVFlags.setRules(
        rules(<String, Object?>{
          'newCheckout': <Object?>[
            <String, Object?>{'value': true},
          ],
        }),
        receivedAt: DateTime.utc(2026, 1, 1),
      );
      final DateTime later = DateTime.utc(2026, 1, 3);
      expect(DVFlags.resolve(newCheckout, now: later).value, isTrue,
          reason: 'a kill switch must not expire back to its default');
      DVFlags.resolve(newCheckout, now: later);
      expect(reported.where((String c) => c == 'DV-FLAGS-009'), hasLength(2));
    });

    test('a changed rule set notifies listeners, so a signal can rebuild',
        () async {
      final List<void> seen = <void>[];
      final StreamSubscription<void> sub = DVFlags.changes.listen(seen.add);
      DVFlags.setRules(rules(<String, Object?>{}));
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
      await sub.cancel();
    });
  });

  group('settle', () {
    test('onNextLaunch pins the first answer for the process', () {
      final DVFeatureFlag<bool> pinned = DVFeatureFlag<bool>(
        key: 'wizard',
        defaultValue: false,
        owner: 'onboarding',
        expires: DateTime.utc(2027, 1, 1),
        settle: DVFlagSettle.onNextLaunch,
      );
      expect(DVFlags.resolve(pinned).value, isFalse);
      DVFlags.setRules(rules(<String, Object?>{
        'wizard': <Object?>[
          <String, Object?>{'value': true},
        ],
      }));
      expect(DVFlags.resolve(pinned).value, isFalse,
          reason: 'a flow half-way through must not flip under its user');
      expect(DVFlags.resolve(newCheckout).value, isFalse);
    });

    test('by default a changed rule takes effect at once', () {
      expect(DVFlags.resolve(newCheckout).value, isFalse);
      DVFlags.setRules(rules(<String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{'value': true},
        ],
      }));
      expect(DVFlags.resolve(newCheckout).value, isTrue);
    });
  });

  group('expiry and exposure', () {
    test('a flag past its expiry reports, and is listed as due', () {
      final DateTime now = DateTime.utc(2026, 12, 2);
      DVFlags.declare(<DVFeatureFlag<Object?>>[newCheckout, pageSize]);
      DVFlags.resolve(newCheckout, now: now);
      expect(reported, contains('DV-FLAGS-004'));
      expect(DVFlags.expired(now).map((DVFeatureFlag<Object?> f) => f.key),
          <String>['newCheckout']);
    });

    test('exposure is recorded once per session per context', () {
      final List<DVFlagExposure> exposures = <DVFlagExposure>[];
      DVFlags.onExposure = exposures.add;
      DVFlags.context = () => alice;
      DVFlags.resolve(newCheckout);
      DVFlags.resolve(newCheckout);
      DVFlags.resolve(newCheckout);
      expect(exposures, hasLength(1));
      expect(exposures.single.key, 'newCheckout');
      expect(exposures.single.value, isFalse);
      DVFlags.context = () => const DVFlagContext(userId: 'bob');
      DVFlags.resolve(newCheckout);
      expect(exposures, hasLength(2));
    });

    test('withheld consent records nothing and says the result is biased', () {
      final List<DVFlagExposure> exposures = <DVFlagExposure>[];
      DVFlags.onExposure = exposures.add;
      DVFlags.exposureConsent = () => false;
      DVFlags.resolve(newCheckout);
      expect(exposures, isEmpty);
      expect(reported, contains('DV-FLAGS-007'));
    });
  });
}
