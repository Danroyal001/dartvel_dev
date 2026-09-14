// Studio's Flags section, driven the way somebody on call drives it.
//
// The quiet failures: an evaluator that works the answer out itself and
// disagrees with what the app actually reads; a rule value of the wrong type
// taken, so the flag holds its default while the screen says it serves the
// new value; an expired flag listed like any other; override controls in a
// release build, where the runtime ignores them and the screen would claim
// otherwise; and rules put in force before anybody saw what changed.
import 'package:dartvel_core/dartvel.dart'
    show
        DVFeatureFlag,
        DVFlagContext,
        DVFlagResolution,
        DVFlagRollout,
        DVFlagRule,
        DVFlagRules,
        DVFlagSource,
        DVFlagSubject,
        DVFlagTarget,
        DVFlags;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/studio/studio_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum Checkout { classic, express, oneTap }

final DVFeatureFlag<bool> newCheckout = DVFeatureFlag<bool>(
  key: 'newCheckout',
  defaultValue: false,
  owner: 'payments',
  expires: DateTime.utc(2099, 1, 1),
);

final DVFeatureFlag<Checkout> checkoutKind = DVFeatureFlag<Checkout>(
  key: 'checkoutKind',
  defaultValue: Checkout.classic,
  owner: 'payments',
  expires: DateTime.utc(2099, 1, 1),
  values: Checkout.values,
);

final DVFeatureFlag<int> pageSize = DVFeatureFlag<int>(
  key: 'pageSize',
  defaultValue: 20,
  owner: 'feed',
  expires: DateTime.utc(2020, 3, 1),
);

final DVFeatureFlag<double> sampleRate = DVFeatureFlag<double>(
  key: 'sampleRate',
  defaultValue: 0.1,
  owner: 'obs',
  expires: DateTime.utc(2099, 1, 1),
);

DVFlagRules seeded() => DVFlagRules.fromJson(<String, Object?>{
      'format': 1,
      'rulesVersion': 7,
      'flags': <String, Object?>{
        'newCheckout': <Object?>[
          <String, Object?>{
            'value': true,
            'target': <String, Object?>{
              'tenants': <Object?>['acme'],
            },
          },
          <String, Object?>{
            'value': true,
            'rollout': <String, Object?>{'percentage': 25, 'by': 'user'},
          },
        ],
        'checkoutKind': <Object?>[
          <String, Object?>{
            'value': 'express',
            'target': <String, Object?>{
              'platforms': <Object?>['ios'],
            },
          },
          <String, Object?>{
            'value': 'oneTap',
            'target': <String, Object?>{
              'platforms': <Object?>['android'],
              'appVersion': <String, Object?>{'min': '2.0.0'},
              'attributes': <String, Object?>{'beta': true},
            },
          },
        ],
      },
    });

final DateTime receivedAt = DateTime.utc(2026, 9, 1, 12);

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

Finder inKey(String key, Finder matching) =>
    find.descendant(of: byKey(key), matching: matching);

GestureDetector detector(WidgetTester tester, String key) =>
    tester.widget<GestureDetector>(byKey(key));

/// Users whose bucket for [flag] puts them inside and outside a [percent]
/// rollout, found with the runtime's own bucketing.
(String, String) usersAround(String flag, int percent) {
  String? inside;
  String? outside;
  for (int i = 0; inside == null || outside == null; i++) {
    final String id = 'user-$i';
    if (DVFlagRollout.bucket(flag, id) < percent * 100) {
      inside ??= id;
    } else {
      outside ??= id;
    }
  }
  return (inside, outside);
}

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    DVFlags.resetForTest();
    DVFlags.onDiagnostic = (String code, String message) {};
    DVFlags.declare(<DVFeatureFlag<Object?>>[
      newCheckout,
      checkoutKind,
      pageSize,
      sampleRate,
    ]);
    DVFlags.setRules(seeded(), receivedAt: receivedAt);
  });

  tearDown(() {
    DVFlags.resetForTest();
    database.close();
    DVPageStore.resetCache();
  });

  Future<void> pumpStudio(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    DVFlags? flags = const DVFlags(),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Material(child: DVStudioScreen(flags: flags))),
    );
    await tester.pumpAndSettle();
    if (flags != null) {
      await tester.tap(byKey('dv-studio-section-flags'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> openFlag(WidgetTester tester, String key) async {
    await tester.tap(byKey('dv-studio-flag-$key'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    final Finder field = inKey(key, find.byType(EditableText));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key, String option) async {
    final Finder choice = inKey(key, find.text(option));
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
  }

  group('opt-in', () {
    testWidgets('Studio has no Flags section unless flags are given',
        (WidgetTester tester) async {
      await pumpStudio(tester, flags: null);
      expect(byKey('dv-studio-section-flags'), findsNothing);
    });

    testWidgets('given flags, the section lists them',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      expect(byKey('dv-studio-flags'), findsOneWidget);
      for (final String key in <String>[
        'newCheckout',
        'checkoutKind',
        'pageSize',
        'sampleRate',
      ]) {
        expect(byKey('dv-studio-flag-$key'), findsOneWidget);
      }
    });
  });

  group('the list', () {
    testWidgets('says each flag\'s type, owner, default and whether rules exist',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      expect(inKey('dv-studio-flag-newCheckout', find.text('bool')),
          findsOneWidget);
      expect(inKey('dv-studio-flag-checkoutKind', find.text('enum')),
          findsOneWidget);
      expect(inKey('dv-studio-flag-sampleRate', find.text('double')),
          findsOneWidget);
      expect(inKey('dv-studio-flag-pageSize', find.textContaining('feed')),
          findsOneWidget);
      expect(
          inKey('dv-studio-flag-newCheckout', find.textContaining('false')),
          findsWidgets);
      expect(inKey('dv-studio-flag-newCheckout', find.text('2 rules')),
          findsOneWidget);
      expect(inKey('dv-studio-flag-sampleRate', find.text('No rules')),
          findsOneWidget);
    });

    testWidgets('an expired flag is marked, and no other is',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      expect(byKey('dv-studio-flag-expired-pageSize'), findsOneWidget);
      for (final String key in <String>[
        'newCheckout',
        'checkoutKind',
        'sampleRate',
      ]) {
        expect(byKey('dv-studio-flag-expired-$key'), findsNothing);
      }
      expect(byKey('dv-studio-flags-expired-count'), findsOneWidget);
      expect(inKey('dv-studio-flags-expired-count', find.text('1 expired')),
          findsOneWidget);

      await openFlag(tester, 'pageSize');
      expect(byKey('dv-studio-flag-expired-banner'), findsOneWidget);
      await openFlag(tester, 'newCheckout');
      expect(byKey('dv-studio-flag-expired-banner'), findsNothing);
    });

    testWidgets('with no rule set synced it says every flag answers its default',
        (WidgetTester tester) async {
      DVFlags.setRules(null);
      await pumpStudio(tester);
      expect(byKey('dv-studio-flags-no-rules'), findsOneWidget);
      expect(inKey('dv-studio-flag-newCheckout', find.text('No rules')),
          findsOneWidget);
    });
  });

  group('the detail', () {
    testWidgets('shows each rule\'s value and targeting in words',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'checkoutKind');
      expect(inKey('dv-studio-flag-rule-0', find.textContaining('express')),
          findsWidgets);
      expect(
          inKey('dv-studio-flag-rule-0', find.textContaining('platform is ios')),
          findsOneWidget);
      expect(inKey('dv-studio-flag-rule-1', find.textContaining('oneTap')),
          findsWidgets);
      expect(
        inKey('dv-studio-flag-rule-1',
            find.textContaining('app version 2.0.0 or later')),
        findsOneWidget,
      );
      expect(inKey('dv-studio-flag-rule-1', find.textContaining('beta = true')),
          findsOneWidget);
      expect(
          inKey('dv-studio-flag-fallthrough', find.textContaining('classic')),
          findsWidgets);

      await openFlag(tester, 'newCheckout');
      expect(
          inKey('dv-studio-flag-rule-0', find.textContaining('tenant is acme')),
          findsOneWidget);
      expect(inKey('dv-studio-flag-rule-1', find.textContaining('25% of users')),
          findsOneWidget);
    });

    testWidgets('a synced value of the wrong type is shown as holding the default',
        (WidgetTester tester) async {
      DVFlags.setRules(DVFlagRules.fromJson(<String, Object?>{
        'rulesVersion': 3,
        'flags': <String, Object?>{
          'pageSize': <Object?>[
            <String, Object?>{'value': '50'},
          ],
        },
      }));
      await pumpStudio(tester);
      await openFlag(tester, 'pageSize');
      expect(byKey('dv-studio-flag-rule-0-wrong-type'), findsOneWidget);
    });
  });

  group('who gets what', () {
    Future<void> enterContext(
      WidgetTester tester,
      Map<String, String> fields,
    ) async {
      for (final String field in <String>[
        'user',
        'tenant',
        'device',
        'role',
        'platform',
        'locale',
        'version',
        'attributes',
      ]) {
        await type(tester, 'dv-studio-flag-eval-$field', fields[field] ?? '');
      }
    }

    void expectAgrees<T>(
      WidgetTester tester,
      DVFeatureFlag<T> flag,
      DVFlagContext context,
    ) {
      final DVFlagResolution<T> actual = DVFlags.resolve(flag, context: context);
      final Object? value = actual.value;
      final String shown = value is Enum ? value.name : '$value';
      expect(inKey('dv-studio-flag-eval-value', find.text(shown)),
          findsOneWidget,
          reason: 'the app reads $shown for ${context.fingerprint}');
      final String rule =
          actual.rule == null ? 'No rule' : 'Rule ${actual.rule! + 1}';
      expect(inKey('dv-studio-flag-eval-rule', find.text(rule)), findsOneWidget,
          reason: 'the app decided by $rule for ${context.fingerprint}');
    }

    testWidgets('answers what the app resolves, rollout included',
        (WidgetTester tester) async {
      final (String inside, String outside) = usersAround('newCheckout', 25);
      await pumpStudio(tester);
      await openFlag(tester, 'newCheckout');

      await enterContext(tester, <String, String>{'user': inside});
      expectAgrees(tester, newCheckout, DVFlagContext(userId: inside));
      expect(inKey('dv-studio-flag-eval-value', find.text('true')),
          findsOneWidget);

      await enterContext(tester, <String, String>{'user': outside});
      expectAgrees(tester, newCheckout, DVFlagContext(userId: outside));
      expect(inKey('dv-studio-flag-eval-value', find.text('false')),
          findsOneWidget);

      await enterContext(
          tester, <String, String>{'user': outside, 'tenant': 'acme'});
      expectAgrees(tester, newCheckout,
          DVFlagContext(userId: outside, tenantId: 'acme'));

      // No user: the rollout holds the default, and it is rule 2 that held it.
      await enterContext(tester, <String, String>{});
      expectAgrees(tester, newCheckout, const DVFlagContext());
      expect(inKey('dv-studio-flag-eval-rule', find.text('Rule 2')),
          findsOneWidget);
    });

    testWidgets('answers what the app resolves for targeting',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'checkoutKind');

      final List<(Map<String, String>, DVFlagContext)> cases =
          <(Map<String, String>, DVFlagContext)>[
        (
          <String, String>{'platform': 'ios'},
          const DVFlagContext(platform: 'ios'),
        ),
        (
          <String, String>{
            'platform': 'android',
            'version': '2.10.0',
            'attributes': 'beta=true',
          },
          const DVFlagContext(
            platform: 'android',
            appVersion: '2.10.0',
            attributes: <String, Object?>{'beta': true},
          ),
        ),
        (
          <String, String>{
            'platform': 'android',
            'version': '1.9.0',
            'attributes': 'beta=true',
          },
          const DVFlagContext(
            platform: 'android',
            appVersion: '1.9.0',
            attributes: <String, Object?>{'beta': true},
          ),
        ),
        (
          // A string "true" is not the boolean the rule names.
          <String, String>{
            'platform': 'android',
            'version': '2.10.0',
            'attributes': 'beta="true"',
          },
          const DVFlagContext(
            platform: 'android',
            appVersion: '2.10.0',
            attributes: <String, Object?>{'beta': 'true'},
          ),
        ),
      ];
      for (final (Map<String, String> fields, DVFlagContext context)
          in cases) {
        await enterContext(tester, fields);
        expectAgrees(tester, checkoutKind, context);
      }
      await enterContext(tester, cases[1].$1);
      expect(inKey('dv-studio-flag-eval-value', find.text('oneTap')),
          findsOneWidget);
    });

    testWidgets('a debug override is what the app reads, and the evaluator too',
        (WidgetTester tester) async {
      DVFlags.setDebugOverride(checkoutKind, Checkout.express);
      await pumpStudio(tester);
      await openFlag(tester, 'checkoutKind');
      await enterContext(tester, <String, String>{'platform': 'android'});
      expectAgrees(
          tester, checkoutKind, const DVFlagContext(platform: 'android'));
      expect(inKey('dv-studio-flag-eval-source', find.text('Debug override')),
          findsOneWidget);
    });
  });

  group('editing rules', () {
    testWidgets('a wrong-typed value is refused and cannot be reviewed',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'pageSize');
      await tapKey(tester, 'dv-studio-flag-edit');
      await tapKey(tester, 'dv-studio-flag-add-rule');

      for (final String wrong in <String>['2.5', 'abc', '"30"', '0x1F', '']) {
        await type(tester, 'dv-studio-flag-rule-0-value', wrong);
        expect(byKey('dv-studio-flag-rule-0-error'), findsOneWidget,
            reason: '"$wrong" is not an int');
        expect(detector(tester, 'dv-studio-flag-review').onTap, isNull,
            reason: '"$wrong" is not an int');
      }
      await type(tester, 'dv-studio-flag-rule-0-value', '30');
      expect(byKey('dv-studio-flag-rule-0-error'), findsNothing);
      expect(detector(tester, 'dv-studio-flag-review').onTap, isNotNull);
    });

    testWidgets('a double flag refuses text and takes a whole number',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'sampleRate');
      await tapKey(tester, 'dv-studio-flag-edit');
      await tapKey(tester, 'dv-studio-flag-add-rule');
      await type(tester, 'dv-studio-flag-rule-0-value', 'half');
      expect(detector(tester, 'dv-studio-flag-review').onTap, isNull);
      await type(tester, 'dv-studio-flag-rule-0-value', '1');
      expect(detector(tester, 'dv-studio-flag-review').onTap, isNotNull);
    });

    testWidgets('a percentage outside 0 to 100 is refused',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'newCheckout');
      await tapKey(tester, 'dv-studio-flag-edit');
      await type(tester, 'dv-studio-flag-rule-1-percent', '150');
      expect(byKey('dv-studio-flag-rule-1-error'), findsOneWidget);
      expect(detector(tester, 'dv-studio-flag-review').onTap, isNull);
    });

    testWidgets('nothing changed, nothing to review',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'newCheckout');
      await tapKey(tester, 'dv-studio-flag-edit');
      expect(detector(tester, 'dv-studio-flag-review').onTap, isNull);
    });

    testWidgets('a change is shown as a diff and applied only when confirmed',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'newCheckout');
      await tapKey(tester, 'dv-studio-flag-edit');
      expect(find.textContaining('Local to this running app'), findsWidgets);

      await type(tester, 'dv-studio-flag-rule-1-percent', '50');
      final Map<String, Object?> before = DVFlags.rules!.toJson();
      expect(DVFlags.rules!.flags['newCheckout']![1].rollout!.basisPoints,
          2500,
          reason: 'typing is not applying');

      await tapKey(tester, 'dv-studio-flag-review');
      expect(byKey('dv-studio-flag-confirm'), findsOneWidget);
      expect(inKey('dv-studio-flag-confirm', find.textContaining('25% of users')),
          findsWidgets);
      expect(inKey('dv-studio-flag-confirm', find.textContaining('50% of users')),
          findsWidgets);
      expect(
          inKey('dv-studio-flag-confirm',
              find.textContaining('Local to this running app')),
          findsWidgets);
      expect(DVFlags.rules!.toJson(), before,
          reason: 'the diff is shown before anything is applied');

      await tapKey(tester, 'dv-studio-flag-cancel');
      expect(byKey('dv-studio-flag-confirm'), findsNothing);
      expect(DVFlags.rules!.toJson(), before);

      await tapKey(tester, 'dv-studio-flag-review');
      await tapKey(tester, 'dv-studio-flag-apply');
      expect(byKey('dv-studio-flag-confirm'), findsNothing);

      final DVFlagRules after = DVFlags.rules!;
      expect(after.flags['newCheckout']![1].rollout!.basisPoints, 5000);
      expect(after.flags['newCheckout']![1].rollout!.by, DVFlagSubject.user);
      expect(after.flags['newCheckout']![0].target!.tenants, <String>['acme']);
      expect(
        after.toJson()['flags']! as Map<String, Object?>,
        containsPair('checkoutKind',
            (before['flags']! as Map<String, Object?>)['checkoutKind']),
        reason: 'another flag\'s rules are not touched',
      );
      expect(after.rulesVersion, greaterThan(7));
      expect(DVFlags.rulesReceivedAt, receivedAt,
          reason: 'a local edit does not make stale rules look fresh');
      expect(byKey('dv-studio-flag-applied'), findsOneWidget);
    });

    testWidgets('add, edit, reorder and remove make the rules the app reads',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'checkoutKind');
      await tapKey(tester, 'dv-studio-flag-edit');

      // Rule 2 (android) first, rule 1 (ios) removed, a web rule added.
      await tapKey(tester, 'dv-studio-flag-rule-1-up');
      await tapKey(tester, 'dv-studio-flag-rule-1-remove');
      await tapKey(tester, 'dv-studio-flag-add-rule');
      await choose(tester, 'dv-studio-flag-rule-1-value', 'express');
      await type(tester, 'dv-studio-flag-rule-1-platforms', 'web, macos');
      await type(tester, 'dv-studio-flag-rule-1-min-version', '3.0.0');

      await tapKey(tester, 'dv-studio-flag-review');
      expect(inKey('dv-studio-flag-confirm', find.textContaining('Removed')),
          findsWidgets);
      expect(inKey('dv-studio-flag-confirm', find.textContaining('Added')),
          findsWidgets);
      await tapKey(tester, 'dv-studio-flag-apply');

      final List<DVFlagRule> rules = DVFlags.rules!.flags['checkoutKind']!;
      expect(rules, hasLength(2));
      expect(rules[0].value, 'oneTap');
      expect(rules[1].value, 'express');
      final DVFlagTarget target = rules[1].target!;
      expect(target.platforms, <String>['web', 'macos']);
      expect(target.minAppVersion, '3.0.0');
      expect(
        DVFlags.resolve(checkoutKind,
                context:
                    const DVFlagContext(platform: 'web', appVersion: '3.1.0'))
            .value,
        Checkout.express,
      );
      expect(
        DVFlags.resolve(checkoutKind,
                context: const DVFlagContext(platform: 'ios'))
            .value,
        Checkout.classic,
      );
    });

    testWidgets('discarding leaves the rules as they were',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'newCheckout');
      final Map<String, Object?> before = DVFlags.rules!.toJson();
      await tapKey(tester, 'dv-studio-flag-edit');
      await tapKey(tester, 'dv-studio-flag-rule-0-remove');
      await tapKey(tester, 'dv-studio-flag-discard');
      expect(byKey('dv-studio-flag-rule-0'), findsOneWidget);
      expect(DVFlags.rules!.toJson(), before);
    });
  });

  group('debug override', () {
    testWidgets('is marked, reaches every read, and clears',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'newCheckout');
      expect(byKey('dv-studio-flag-override'), findsOneWidget);
      expect(inKey('dv-studio-flag-override', find.text('Debug build only')),
          findsOneWidget);

      await choose(tester, 'dv-studio-flag-override-value', 'true');
      await tapKey(tester, 'dv-studio-flag-override-toggle');
      expect(DVFlags.debugOverrides, <String, Object?>{'newCheckout': true});
      expect(
          DVFlags.resolve(newCheckout, context: const DVFlagContext()).source,
          DVFlagSource.override);
      expect(inKey('dv-studio-flag-newCheckout', find.text('Override')),
          findsOneWidget);

      await tapKey(tester, 'dv-studio-flag-override-toggle');
      expect(DVFlags.debugOverrides, isEmpty);
      expect(inKey('dv-studio-flag-newCheckout', find.text('Override')),
          findsNothing);
    });

    testWidgets('a wrong-typed override value is refused',
        (WidgetTester tester) async {
      await pumpStudio(tester);
      await openFlag(tester, 'pageSize');
      await type(tester, 'dv-studio-flag-override-value', '2.5');
      expect(byKey('dv-studio-flag-override-error'), findsOneWidget);
      expect(detector(tester, 'dv-studio-flag-override-toggle').onTap, isNull);
      expect(DVFlags.debugOverrides, isEmpty);
    });

    testWidgets('a release build has no override controls',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(
        home: Material(
          child: StudioFlagsSection(flags: DVFlags(), releaseBuild: true),
        ),
      ));
      await tester.pumpAndSettle();
      for (final String key in <String>[
        'newCheckout',
        'checkoutKind',
        'pageSize',
        'sampleRate',
      ]) {
        await openFlag(tester, key);
        expect(byKey('dv-studio-flag-override'), findsNothing);
        expect(byKey('dv-studio-flag-override-toggle'), findsNothing);
        expect(byKey('dv-studio-flag-override-value'), findsNothing);
        expect(byKey('dv-studio-flag-override-unavailable'), findsOneWidget);
      }
    });
  });

  group('fits', () {
    for (final Size size in const <Size>[
      Size(800, 600),
      Size(1024, 700),
      Size(1920, 1080),
    ]) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}',
          (WidgetTester tester) async {
        DVFlags.setDebugOverride(sampleRate, 0.5);
        await pumpStudio(tester, size: size);
        expect(tester.takeException(), isNull);
        for (final String key in <String>[
          'newCheckout',
          'checkoutKind',
          'pageSize',
          'sampleRate',
        ]) {
          await openFlag(tester, key);
          expect(tester.takeException(), isNull, reason: key);
        }
        await openFlag(tester, 'checkoutKind');
        await type(tester, 'dv-studio-flag-eval-platform', 'android');
        await tapKey(tester, 'dv-studio-flag-edit');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'dv-studio-flag-add-rule');
        await type(tester, 'dv-studio-flag-rule-2-attributes',
            'plan=enterprise, cohort="early-access-2026"');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'dv-studio-flag-review');
        expect(byKey('dv-studio-flag-confirm'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
