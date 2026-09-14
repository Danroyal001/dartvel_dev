// Preview Environments: creating, suspending and destroying a branch's
// environment against an adapter.
//
// The fake adapter keeps real state -- which databases exist and what rows
// they hold -- because the failures that matter here are silent ones: a
// preview reading production's rows, a teardown that reported success and
// left a database running, two branches on one database. Each is asserted
// on the adapter's state rather than on what the manager says it did.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 1, 12);

class FakeAdapter implements DVPreviewAdapter {
  FakeAdapter({
    this.canHostPreviews = true,
    this.canBranchDatabases = true,
    String productionDatabase = 'shop',
  }) : productionResources = DVPreviewProduction(
          database: productionDatabase,
          bucket: 'shop-uploads',
          host: 'shop',
          queueNamespace: 'default',
        ) {
    databases[productionDatabase] = <String, Map<String, List<String>>>{
      'users': <String, List<String>>{
        'email': <String>['ada@example.com', 'grace@example.com'],
        'name': <String>['Ada', 'Grace'],
      },
    };
  }

  @override
  final String name = 'fake';
  @override
  final bool canHostPreviews;
  @override
  final bool canBranchDatabases;

  final DVPreviewProduction productionResources;

  final Map<String, Map<String, Map<String, List<String>>>> databases =
      <String, Map<String, Map<String, List<String>>>>{};
  final Set<String> buckets = <String>{'shop-uploads'};
  final Map<String, DVPreviewDeployment> deployments =
      <String, DVPreviewDeployment>{};
  final Set<String> suspended = <String>{};
  final List<String> calls = <String>[];

  bool databaseDestroyLies = false;
  bool deployFails = false;

  @override
  Future<DVPreviewProduction> production() async => productionResources;

  @override
  Future<void> createDatabase(String database) async {
    calls.add('createDatabase $database');
    if (databases.containsKey(database)) throw StateError('exists');
    databases[database] = <String, Map<String, List<String>>>{};
  }

  @override
  Future<void> branchDatabase(String database, {required String from}) async {
    calls.add('branchDatabase $database from $from');
    databases[database] = <String, Map<String, List<String>>>{
      for (final MapEntry<String, Map<String, List<String>>> table
          in databases[from]!.entries)
        table.key: <String, List<String>>{
          for (final MapEntry<String, List<String>> column in table.value.entries)
            column.key: List<String>.of(column.value),
        },
    };
  }

  @override
  Future<Set<String>> valueDigests(
    String database,
    String table,
    String column,
  ) async {
    calls.add('valueDigests $database $table.$column');
    return <String>{
      for (final String v in databases[database]?[table]?[column] ?? <String>[])
        sha256.convert(utf8.encode(v)).toString(),
    };
  }

  @override
  Future<void> createBucket(String bucket) async {
    calls.add('createBucket $bucket');
    buckets.add(bucket);
  }

  @override
  Future<String> deploy(DVPreviewDeployment deployment) async {
    calls.add('deploy ${deployment.identity.name}');
    if (deployFails) throw StateError('platform said no');
    deployments[deployment.identity.hostLabel] = deployment;
    suspended.remove(deployment.identity.hostLabel);
    return 'https://${deployment.identity.hostLabel}.preview.example.dev';
  }

  @override
  Future<void> suspend(DVPreviewIdentity identity) async {
    calls.add('suspend ${identity.name}');
    suspended.add(identity.hostLabel);
  }

  @override
  Future<void> wake(DVPreviewIdentity identity) async {
    calls.add('wake ${identity.name}');
    suspended.remove(identity.hostLabel);
  }

  @override
  Future<void> destroyDeployment(DVPreviewIdentity identity) async {
    calls.add('destroyDeployment ${identity.name}');
    deployments.remove(identity.hostLabel);
  }

  @override
  Future<void> destroyDatabase(String database) async {
    calls.add('destroyDatabase $database');
    if (database == productionResources.database) {
      throw StateError('the test destroyed production');
    }
    if (!databaseDestroyLies) databases.remove(database);
  }

  @override
  Future<void> destroyBucket(String bucket) async {
    calls.add('destroyBucket $bucket');
    buckets.remove(bucket);
  }

  @override
  Future<bool> exists(DVPreviewResource kind, String name) async =>
      switch (kind) {
        DVPreviewResource.deployment => deployments.containsKey(name),
        DVPreviewResource.database => databases.containsKey(name),
        DVPreviewResource.bucket => buckets.contains(name),
      };

  /// Every call that named production's database other than as the source
  /// of a branch or of a digest comparison.
  List<String> get touchedProduction => <String>[
        for (final String call in calls)
          // Whole arguments: a preview's own names begin with the app's name,
          // which is also production's database name here.
          if (call.split(' ').skip(1).contains(productionResources.database) &&
              !call.startsWith('branchDatabase') &&
              !call.startsWith('valueDigests'))
            call,
      ];
}

DVPreviewSecretPlan get _secrets => dvPlanPreviewSecrets(
      required: const <String, Set<String>>{
        'PAYSTACK_SECRET': <String>{'production'},
      },
      previewValue: (String name) => 'sk_test_preview_value',
    );

void main() {
  late FakeAdapter adapter;
  late DVMemoryPreviewRegistry registry;
  late List<String> order;

  DVPreviews previews({
    DVPreviewConfig config = const DVPreviewConfig(),
    String? environment,
  }) =>
      DVPreviews(
        app: 'shop',
        adapter: adapter,
        registry: registry,
        config: config,
        currentEnvironment: environment,
      );

  Future<void> migrate(DVPreviewTarget target) async =>
      order.add('migrate ${target.database}');
  Future<void> seed(DVPreviewTarget target) async =>
      order.add('seed ${target.database}');

  setUp(() {
    adapter = FakeAdapter();
    registry = DVMemoryPreviewRegistry();
    order = <String>[];
  });

  group('create', () {
    test('a fresh database of its own, migrated then seeded, then deployed',
        () async {
      final DVPreviewOutcome outcome = await previews().create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        migrate: migrate,
        seed: seed,
      );

      expect(outcome.ok, isTrue, reason: '${outcome.errors} ${outcome.findings}');
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      expect(adapter.databases[id.database], isEmpty,
          reason: 'a fresh database holds no rows of production\'s');
      expect(order, <String>['migrate ${id.database}', 'seed ${id.database}']);
      expect(adapter.buckets, contains(id.bucket));
      expect(adapter.touchedProduction, isEmpty);
      expect(adapter.calls.where((String c) => c.startsWith('branchDatabase')),
          isEmpty);

      final DVPreviewDeployment deployed = adapter.deployments[id.hostLabel]!;
      expect(deployed.variables['DARTVEL_ENVIRONMENT'], 'preview');
      expect(deployed.variables['PAYSTACK_SECRET'], 'sk_test_preview_value');
      expect(deployed.variables['DARTVEL_DATABASE'], id.database);
      expect(deployed.variables['DARTVEL_STORAGE_BUCKET'], id.bucket);
      expect(deployed.variables['DARTVEL_QUEUE_NAMESPACE'], id.queueNamespace);
      // Production's database name goes with the deployment, so the running
      // preview can refuse to start on it.
      expect(deployed.variables['DARTVEL_PRODUCTION_DATABASE'], 'shop');

      expect(outcome.record!.state, DVPreviewState.running);
      expect(outcome.record!.url, contains(id.hostLabel));
      expect(outcome.findings.map((DVPreviewFinding f) => f.code),
          contains('DV-PREVIEW-001'));
      expect((await registry.all()).single.identity.name, id.name);
    });

    test('an adapter that cannot host previews is DV-PREVIEW-010 and creates nothing',
        () async {
      adapter = FakeAdapter(canHostPreviews: false);
      final DVPreviewOutcome outcome = await previews().create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        migrate: migrate,
        seed: seed,
      );
      expect(outcome.ok, isFalse);
      expect(outcome.findings.single.code, 'DV-PREVIEW-010');
      expect(adapter.calls, isEmpty);
      expect(await registry.all(), isEmpty);
    });

    test('a missing preview secret is refused before any resource exists',
        () async {
      final DVPreviewOutcome outcome = await previews().create(
        branch: 'feature/cart',
        now: t0,
        secrets: dvPlanPreviewSecrets(
          required: const <String, Set<String>>{
            'PAYSTACK_SECRET': <String>{'production'},
          },
          previewValue: (_) => null,
        ),
        migrate: migrate,
        seed: seed,
      );
      expect(outcome.ok, isFalse);
      expect(outcome.findings.map((DVPreviewFinding f) => f.code),
          <String>['DV-PREVIEW-002']);
      expect(adapter.calls, isEmpty);
      expect(order, isEmpty);
      expect(await registry.all(), isEmpty);
    });

    test('a preview is never created from inside a preview', () async {
      final DVPreviewOutcome outcome = await previews(environment: 'preview')
          .create(branch: 'feature/cart', now: t0, secrets: _secrets);
      expect(outcome.ok, isFalse);
      expect(outcome.errors.single, contains('preview of a preview'));
      expect(adapter.calls, isEmpty);
    });

    test('a preview whose names collide with production\'s is refused', () async {
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      adapter = FakeAdapter(productionDatabase: id.database);
      final DVPreviewOutcome outcome = await previews().create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        migrate: migrate,
        seed: seed,
      );
      expect(outcome.ok, isFalse);
      expect(outcome.errors.single, contains(id.database));
      expect(adapter.calls.where((String c) => !c.startsWith('valueDigests')),
          isEmpty);
      expect(adapter.databases[id.database]!['users'], isNotNull,
          reason: 'production is untouched');
    });

    test('the same branch twice is one environment, redeployed', () async {
      final DVPreviews p = previews();
      await p.create(
          branch: 'feature/cart', now: t0, secrets: _secrets, migrate: migrate, seed: seed);
      order.clear();
      adapter.deployments.clear();
      final DVPreviewOutcome again = await p.create(
        branch: 'feature/cart',
        now: t0.add(const Duration(hours: 1)),
        secrets: _secrets,
        migrate: migrate,
        seed: seed,
      );
      expect(again.ok, isTrue, reason: '${again.errors}');
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      expect(
          adapter.calls.where((String c) => c == 'createDatabase ${id.database}'),
          hasLength(1));
      expect(order, <String>['migrate ${id.database}'],
          reason: 'seeds ran once, on the empty database');
      expect(await registry.all(), hasLength(1));
      expect(again.record!.deployedAt, t0.add(const Duration(hours: 1)));
      expect(again.record!.createdAt, t0);
      expect(
          adapter.deployments[id.hostLabel]!
              .variables['DARTVEL_PRODUCTION_DATABASE'],
          'shop',
          reason: 'a redeploy writes production\'s database name too');
    });

    test('a failed migration takes down what was created and leaves no record',
        () async {
      final DVPreviewOutcome outcome = await previews().create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        migrate: (DVPreviewTarget target) async =>
            throw StateError('column already exists'),
        seed: seed,
      );
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      expect(outcome.ok, isFalse);
      expect(outcome.errors.join(), contains('column already exists'));
      expect(adapter.databases, isNot(contains(id.database)));
      expect(adapter.buckets, isNot(contains(id.bucket)));
      expect(adapter.deployments, isEmpty);
      expect(await registry.all(), isEmpty);
    });

    test('a deploy that fails is torn down too', () async {
      adapter.deployFails = true;
      final DVPreviewOutcome outcome = await previews().create(
          branch: 'feature/cart', now: t0, secrets: _secrets, migrate: migrate, seed: seed);
      expect(outcome.ok, isFalse);
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      expect(adapter.databases, isNot(contains(id.database)));
      expect(await registry.all(), isEmpty);
    });
  });

  group('database branching', () {
    const Map<String, Set<String>> sensitive = <String, Set<String>>{
      'users': <String>{'email'},
    };
    const DVPreviewConfig branch = DVPreviewConfig(
      database: DVPreviewDatabase.branch,
      sanitize: 'lib/dev/sanitize.dart',
    );

    test('sensitive fields with no sanitization step are DV-PREVIEW-003',
        () async {
      final DVPreviewOutcome outcome = await previews(
        config: const DVPreviewConfig(database: DVPreviewDatabase.branch),
      ).create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        sensitiveColumns: sensitive,
        migrate: migrate,
      );
      expect(outcome.ok, isFalse);
      expect(outcome.findings.map((DVPreviewFinding f) => f.code),
          <String>['DV-PREVIEW-003']);
      expect(outcome.findings.single.message, contains('users.email'));
      expect(adapter.calls, isEmpty);
    });

    test('a declared step that is not supplied to run is refused the same way',
        () async {
      final DVPreviewOutcome outcome = await previews(config: branch).create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        sensitiveColumns: sensitive,
        migrate: migrate,
      );
      expect(outcome.findings.map((DVPreviewFinding f) => f.code),
          <String>['DV-PREVIEW-003']);
      expect(adapter.calls, isEmpty);
    });

    test('a sanitization step that leaves production values is refused and the branch destroyed',
        () async {
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      final DVPreviewOutcome outcome = await previews(config: branch).create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        sensitiveColumns: sensitive,
        migrate: migrate,
        // Runs, returns, and changes one row of two.
        sanitize: (DVPreviewTarget target) async {
          adapter.databases[target.database]!['users']!['email']![0] =
              'user-1@preview.invalid';
        },
      );
      expect(outcome.ok, isFalse);
      expect(outcome.findings.single.code, 'DV-PREVIEW-003');
      expect(outcome.findings.single.message, contains('users.email'));
      expect(outcome.findings.single.message, isNot(contains('grace')));
      expect(adapter.databases, isNot(contains(id.database)));
      expect(adapter.deployments, isEmpty);
      expect(await registry.all(), isEmpty);
    });

    test('a sanitization step that replaces every value is deployed, without seeds',
        () async {
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      final DVPreviewOutcome outcome = await previews(config: branch).create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        sensitiveColumns: sensitive,
        migrate: migrate,
        seed: seed,
        sanitize: (DVPreviewTarget target) async {
          final List<String> emails =
              adapter.databases[target.database]!['users']!['email']!;
          for (int i = 0; i < emails.length; i++) {
            emails[i] = 'user-$i@preview.invalid';
          }
        },
      );
      expect(outcome.ok, isTrue, reason: '${outcome.errors} ${outcome.findings}');
      expect(adapter.deployments, contains(id.hostLabel));
      expect(order, <String>['migrate ${id.database}']);
      expect(
        adapter.calls.indexWhere((String c) => c.startsWith('branchDatabase')),
        lessThan(adapter.calls.indexWhere((String c) => c.startsWith('deploy'))),
      );
      expect(adapter.databases['shop']!['users']!['email'],
          <String>['ada@example.com', 'grace@example.com'],
          reason: 'sanitizing the branch never writes production');
    });

    test('an adapter that cannot branch is refused rather than copied another way',
        () async {
      adapter = FakeAdapter(canBranchDatabases: false);
      final DVPreviewOutcome outcome = await previews(config: branch).create(
        branch: 'feature/cart',
        now: t0,
        secrets: _secrets,
        sensitiveColumns: sensitive,
        migrate: migrate,
        sanitize: (_) async {},
      );
      expect(outcome.ok, isFalse);
      expect(adapter.calls, isEmpty);
    });
  });

  group('visibility', () {
    test('link visibility gets an unguessable token the deployment holds only as a digest',
        () async {
      final DVPreviewOutcome a = await previews(
        config: const DVPreviewConfig(visibility: DVPreviewVisibility.link),
      ).create(branch: 'feature/a', now: t0, secrets: _secrets);
      final DVPreviewOutcome b = await previews(
        config: const DVPreviewConfig(visibility: DVPreviewVisibility.link),
      ).create(branch: 'feature/b', now: t0, secrets: _secrets);
      final String token = a.record!.linkToken!;
      expect(base64Url.decode(base64Url.normalize(token)).length,
          greaterThanOrEqualTo(32));
      expect(token, isNot(b.record!.linkToken));
      final DVPreviewDeployment deployed =
          adapter.deployments[a.record!.identity.hostLabel]!;
      expect(deployed.variables.values, isNot(contains(token)));
      expect(deployed.variables['DARTVEL_PREVIEW_LINK_DIGEST'],
          sha256.convert(utf8.encode(token)).toString());
      expect(a.openUrl, contains(token));
    });

    test('members is the default and public is DV-PREVIEW-007', () async {
      final DVPreviewOutcome members =
          await previews().create(branch: 'feature/a', now: t0, secrets: _secrets);
      expect(adapter.deployments[members.record!.identity.hostLabel]!
          .variables['DARTVEL_PREVIEW_VISIBILITY'], 'members');
      expect(members.record!.linkToken, isNull);

      final DVPreviewOutcome public = await previews(
        config: const DVPreviewConfig(visibility: DVPreviewVisibility.public),
      ).create(branch: 'feature/b', now: t0, secrets: _secrets);
      expect(public.findings.map((DVPreviewFinding f) => f.code),
          contains('DV-PREVIEW-007'));
    });
  });

  group('the cap', () {
    test('at max the oldest idle preview is suspended, not destroyed', () async {
      final DVPreviews p = previews(config: const DVPreviewConfig(max: 2));
      await p.create(branch: 'old', now: t0, secrets: _secrets);
      await p.create(branch: 'newer', now: t0, secrets: _secrets);
      final DVPreviewIdentity old =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'old');
      final DVPreviewIdentity newer =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'newer');
      await p.touch(newer.name, now: t0.add(const Duration(minutes: 5)));

      final DVPreviewOutcome third = await p.create(
          branch: 'third', now: t0.add(const Duration(minutes: 6)), secrets: _secrets);

      expect(third.ok, isTrue);
      final DVPreviewFinding cap = third.findings
          .singleWhere((DVPreviewFinding f) => f.code == 'DV-PREVIEW-004');
      expect(cap.message, contains(old.name));
      expect(adapter.suspended, <String>{old.hostLabel});
      expect(adapter.deployments, contains(old.hostLabel));
      expect(adapter.databases, contains(old.database));
      expect((await registry.find(old.name))!.state, DVPreviewState.suspended);
      expect((await registry.find(newer.name))!.state, DVPreviewState.running);
    });
  });

  group('teardown', () {
    test('destroy takes the deployment, the database and the bucket', () async {
      final DVPreviews p = previews();
      await p.create(branch: 'feature/cart', now: t0, secrets: _secrets);
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');

      final DVPreviewOutcome outcome =
          await p.destroy(id.name, now: t0.add(const Duration(hours: 2)));

      expect(outcome.ok, isTrue);
      expect(outcome.findings.single.code, 'DV-PREVIEW-009');
      expect(adapter.deployments, isEmpty);
      expect(adapter.databases, isNot(contains(id.database)));
      expect(adapter.buckets, isNot(contains(id.bucket)));
      expect(adapter.databases, contains('shop'));
      expect(await registry.all(), isEmpty);
    });

    test('a teardown the platform did not finish keeps the record until it is gone',
        () async {
      final DVPreviews p = previews();
      await p.create(branch: 'feature/cart', now: t0, secrets: _secrets);
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      adapter.databaseDestroyLies = true;

      final DVPreviewOutcome outcome = await p.destroy(id.name, now: t0);

      expect(outcome.ok, isFalse);
      expect(outcome.findings, isEmpty,
          reason: 'DV-PREVIEW-009 says the database went with it; it did not');
      final DVPreviewRecord kept = (await registry.find(id.name))!;
      expect(kept.state, DVPreviewState.destroying);
      expect(kept.remaining, <DVPreviewResource>{DVPreviewResource.database});

      adapter.databaseDestroyLies = false;
      final List<DVPreviewFinding> swept = await p.sweep(now: t0);
      expect(swept.map((DVPreviewFinding f) => f.code), <String>['DV-PREVIEW-009']);
      expect(await registry.all(), isEmpty);
      expect(adapter.databases, isNot(contains(id.database)));
    });
  });

  group('sweep', () {
    test('ttl destroys, idle suspends, a gone branch or closed PR destroys',
        () async {
      final DVPreviews p = previews(
        config: const DVPreviewConfig(
          ttl: Duration(days: 7),
          idle: Duration(minutes: 30),
        ),
      );
      await p.create(branch: 'expired', now: t0, secrets: _secrets);
      final DateTime later = t0.add(const Duration(days: 7, minutes: 1));
      await p.create(branch: 'idle', now: later.subtract(const Duration(hours: 1)), secrets: _secrets);
      await p.create(branch: 'busy', now: later.subtract(const Duration(hours: 1)), secrets: _secrets);
      await p.create(branch: 'merged', now: later, secrets: _secrets);
      await p.create(branch: 'closed', now: later, secrets: _secrets, pullRequest: 412);
      String n(String b) => DVPreviewIdentity.forBranch(app: 'shop', branch: b).name;
      await p.touch(n('busy'), now: later.subtract(const Duration(minutes: 10)));

      final List<DVPreviewFinding> findings = await p.sweep(
        now: later,
        liveBranches: <String>{'expired', 'idle', 'busy', 'closed'},
        closedPullRequests: <int>{412},
      );

      final Set<String> left = <String>{
        for (final DVPreviewRecord r in await registry.all()) r.identity.branch,
      };
      expect(left, <String>{'idle', 'busy'});
      expect((await registry.find(n('idle')))!.state, DVPreviewState.suspended);
      expect((await registry.find(n('busy')))!.state, DVPreviewState.running);
      expect(findings.where((DVPreviewFinding f) => f.code == 'DV-PREVIEW-009'),
          hasLength(3));
      expect(findings.where((DVPreviewFinding f) => f.code == 'DV-PREVIEW-005'),
          hasLength(1));
    });

    test('a create that never finished is swept rather than left running',
        () async {
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'crashed');
      await adapter.createDatabase(id.database);
      await registry.put(DVPreviewRecord(
        identity: id,
        state: DVPreviewState.creating,
        visibility: DVPreviewVisibility.members,
        createdAt: t0,
        lastRequestAt: t0,
      ));
      final List<DVPreviewFinding> findings =
          await previews().sweep(now: t0.add(const Duration(hours: 2)));
      expect(findings.single.code, 'DV-PREVIEW-009');
      expect(adapter.databases, isNot(contains(id.database)));
      expect(await registry.all(), isEmpty);
    });

    test('a request wakes a suspended preview', () async {
      final DVPreviews p = previews(config: const DVPreviewConfig(idle: Duration(minutes: 30)));
      await p.create(branch: 'feature/cart', now: t0, secrets: _secrets);
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      await p.sweep(now: t0.add(const Duration(hours: 1)));
      expect(adapter.suspended, contains(id.hostLabel));

      final DVPreviewRecord woken =
          (await p.touch(id.name, now: t0.add(const Duration(hours: 2))))!;
      expect(woken.state, DVPreviewState.running);
      expect(adapter.suspended, isEmpty);
    });
  });

  test('a record survives a round trip through JSON', () async {
    final DVPreviewOutcome outcome = await previews(
      config: const DVPreviewConfig(visibility: DVPreviewVisibility.link),
    ).create(branch: 'feature/cart', now: t0, secrets: _secrets, pullRequest: 7);
    final DVPreviewRecord record = outcome.record!;
    final DVPreviewRecord back = DVPreviewRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>);
    expect(back.toJson(), record.toJson());
    expect(back.pullRequest, 7);
  });
}
