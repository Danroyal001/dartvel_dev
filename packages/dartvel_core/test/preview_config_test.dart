// Preview Environments: what `dartvel.preview` says, what a branch's
// environment is called, and which secret values a preview may hold.
//
// The three are the plan-time half of the section. Each refusal here happens
// before anything is created, which is the only point at which a refusal
// costs nothing.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('dartvel.preview', () {
    test('absent is the section\'s defaults', () {
      final DVPreviewConfig config = DVPreviewConfig.fromConfig(null);
      expect(config.database, DVPreviewDatabase.fresh);
      expect(config.sanitize, isNull);
      expect(config.ttl, const Duration(days: 7));
      expect(config.idle, const Duration(minutes: 30));
      expect(config.max, 10);
      expect(config.visibility, DVPreviewVisibility.members);
      expect(config.schedules, isEmpty);
    });

    test('reads every declared value', () {
      final DVPreviewConfig config = DVPreviewConfig.fromConfig(<Object?, Object?>{
        'database': 'branch',
        'sanitize': 'lib/dev/sanitize.dart',
        'ttl': '3d',
        'idle': '45m',
        'max': 4,
        'visibility': 'link',
        'schedules': <Object?>['nightly-report'],
      });
      expect(config.database, DVPreviewDatabase.branch);
      expect(config.sanitize, 'lib/dev/sanitize.dart');
      expect(config.ttl, const Duration(days: 3));
      expect(config.idle, const Duration(minutes: 45));
      expect(config.max, 4);
      expect(config.visibility, DVPreviewVisibility.link);
      expect(config.schedules, <String>{'nightly-report'});
    });

    test('branching without a sanitization step is refused when read', () {
      expect(
        () => DVPreviewConfig.fromConfig(<Object?, Object?>{'database': 'branch'}),
        throwsA(isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          contains('sanitize'),
        )),
      );
    });

    test('a sanitize step with a fresh database is refused, not ignored', () {
      // Somebody who wrote it believes it runs. On a fresh database it never
      // would, and the belief outlives the configuration change that made it
      // false.
      expect(
        () => DVPreviewConfig.fromConfig(<Object?, Object?>{
          'sanitize': 'lib/dev/sanitize.dart',
        }),
        throwsFormatException,
      );
    });

    test('an unknown key, a misspelled value or a bare number is refused', () {
      for (final Map<Object?, Object?> bad in <Map<Object?, Object?>>[
        <Object?, Object?>{'visiblity': 'public'},
        <Object?, Object?>{'visibility': 'everyone'},
        <Object?, Object?>{'database': 'copy'},
        <Object?, Object?>{'ttl': 7},
        <Object?, Object?>{'ttl': '0d'},
        <Object?, Object?>{'idle': 'soon'},
        <Object?, Object?>{'max': 0},
        <Object?, Object?>{'max': '10'},
        <Object?, Object?>{'schedules': 'nightly'},
      ]) {
        expect(() => DVPreviewConfig.fromConfig(bad), throwsFormatException,
            reason: '$bad');
      }
    });
  });

  group('a branch\'s environment', () {
    test('two branches that slug alike do not share a database or a host', () {
      final DVPreviewIdentity a =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/a-b');
      final DVPreviewIdentity b =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature-a/b');
      expect(a.name, isNot(b.name));
      expect(a.hostLabel, isNot(b.hostLabel));
      expect(a.database, isNot(b.database));
      expect(a.bucket, isNot(b.bucket));
      expect(a.queueNamespace, isNot(b.queueNamespace));
    });

    test('the same branch is the same environment every time', () {
      // One branch, one environment: a second create is a redeploy, which it
      // can only be if the name does not move.
      expect(
        DVPreviewIdentity.forBranch(app: 'shop', branch: 'fix/login').database,
        DVPreviewIdentity.forBranch(app: 'shop', branch: 'fix/login').database,
      );
    });

    test('every name is a valid identifier for where it is used', () {
      final DVPreviewIdentity id = DVPreviewIdentity.forBranch(
        app: 'my_shop',
        branch: 'Users/Ada/JIRA-1234_a-really-long-branch-name-that-somebody-typed'
            '-without-thinking-about-dns-labels-at-all',
      );
      final RegExp dnsLabel = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');
      expect(id.hostLabel, matches(dnsLabel));
      expect(id.hostLabel.length, lessThanOrEqualTo(63));
      expect(id.bucket, matches(dnsLabel));
      expect(id.bucket.length, inInclusiveRange(3, 63));
      expect(id.database, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
      expect(id.database.length, lessThanOrEqualTo(63));
    });

    test('long branches that differ only past the cut stay apart', () {
      const String stem = 'feature/an-extremely-long-branch-name-that-runs-well-past-'
          'every-identifier-limit-there-is';
      final DVPreviewIdentity a =
          DVPreviewIdentity.forBranch(app: 'shop', branch: '$stem-one');
      final DVPreviewIdentity b =
          DVPreviewIdentity.forBranch(app: 'shop', branch: '$stem-two');
      expect(a.hostLabel, isNot(b.hostLabel));
      expect(a.database, isNot(b.database));
    });

    test('every resource says preview, so none can be production\'s name', () {
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'main');
      expect(id.database, contains('preview'));
      expect(id.bucket, contains('preview'));
      expect(id.hostLabel, contains('preview'));
      expect(id.queueNamespace, contains('preview'));
    });

    test('an empty branch is refused', () {
      expect(() => DVPreviewIdentity.forBranch(app: 'shop', branch: '  '),
          throwsArgumentError);
    });
  });

  group('secrets for a preview', () {
    const Map<String, Set<String>> required = <String, Set<String>>{
      'PAYSTACK_SECRET': <String>{'production'},
      'MAPS_KEY': <String>{'preview'},
      'STAGING_ONLY': <String>{'staging'},
      'OPTIONAL': <String>{},
    };

    test('a secret required in production with no preview value is DV-PREVIEW-002',
        () {
      final DVPreviewSecretPlan plan = dvPlanPreviewSecrets(
        required: required,
        previewValue: (String name) =>
            name == 'MAPS_KEY' ? 'maps-preview-value' : null,
      );
      expect(plan.deployable, isFalse);
      expect(plan.findings.map((DVPreviewFinding f) => f.code),
          <String>['DV-PREVIEW-002']);
      expect(plan.findings.single.level, 'error');
      expect(plan.findings.single.message, contains('PAYSTACK_SECRET'));
    });

    test('production\'s value is never what a preview is given', () {
      // The resolver for production is consulted only to compare. A preview
      // value that is production's value is no preview value at all.
      final DVPreviewSecretPlan plan = dvPlanPreviewSecrets(
        required: required,
        previewValue: (String name) => switch (name) {
          'PAYSTACK_SECRET' => 'sk_live_the_real_one',
          'MAPS_KEY' => 'maps-preview-value',
          _ => null,
        },
        productionValue: (String name) =>
            name == 'PAYSTACK_SECRET' ? 'sk_live_the_real_one' : null,
      );
      expect(plan.deployable, isFalse);
      expect(plan.values, isNot(contains('PAYSTACK_SECRET')));
      expect(plan.findings.single.code, 'DV-PREVIEW-002');
      // Never quoted back: the finding goes to a CI log.
      expect(plan.findings.single.message, isNot(contains('sk_live')));
    });

    test('preview values reach the deployment under their own names', () {
      final DVPreviewSecretPlan plan = dvPlanPreviewSecrets(
        required: required,
        previewValue: (String name) => switch (name) {
          'PAYSTACK_SECRET' => 'sk_test_preview',
          'MAPS_KEY' => 'maps-preview-value',
          'OPTIONAL' => 'optional-preview',
          _ => null,
        },
        productionValue: (String name) => 'something-else',
      );
      expect(plan.deployable, isTrue);
      expect(plan.values, <String, String>{
        'PAYSTACK_SECRET': 'sk_test_preview',
        'MAPS_KEY': 'maps-preview-value',
        'OPTIONAL': 'optional-preview',
      });
    });

    test('a secret required only elsewhere is not demanded of a preview', () {
      final DVPreviewSecretPlan plan = dvPlanPreviewSecrets(
        required: required,
        previewValue: (String name) => switch (name) {
          'PAYSTACK_SECRET' => 'sk_test_preview',
          'MAPS_KEY' => 'maps-preview-value',
          _ => null,
        },
      );
      expect(plan.deployable, isTrue);
      expect(plan.values, isNot(contains('STAGING_ONLY')));
    });
  });
}
