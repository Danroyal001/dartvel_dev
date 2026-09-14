// The provisioning plan, its application, and the drift check.
//
// The quiet failures: a retry after a half-applied provision that repeats the
// steps that already landed; a plan that differs from what is applied because
// the host moved between approval and apply; a destructive step applied with
// nobody saying yes; a failure part way reported as success; a host that
// accepted every step but does not match the manifest afterwards, reported as
// provisioned; a rotated secret delivered without restarting what loads it; a
// secret value that reaches a plan, a result or an error message; and a
// check that stays quiet about a stopped service, a certificate that is not
// renewing, or a backup nobody has restored.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String secretValue = 'sk_live_correct-horse-battery-staple';
const String dbUrl = 'postgres://app:hunter2hunter2@db.internal/app';

Map<Object?, Object?> manifestConfig({int instances = 2}) =>
    <Object?, Object?>{
      'production': <Object?, Object?>{
        'hosts': <Object?>['app-1.example.com'],
        'tls': <Object?, Object?>{
          'domains': <Object?>['api.example.com'],
          'acme': <Object?, Object?>{'email': 'ops@example.com'},
        },
        'proxy': <Object?, Object?>{'adapter': 'caddy'},
        'services': <Object?, Object?>{
          'backend': <Object?, Object?>{'instances': instances},
        },
        'database': <Object?, Object?>{
          'adapter': 'postgres',
          'backup': <Object?, Object?>{
            'schedule': '0 3 * * *',
            'retain': '30d',
            'verifiedRestoreWithin': '7d',
          },
        },
      },
    };

DVInfraDesiredState desiredState({int instances = 2}) => dvInfraDesiredState(
  DVInfraManifest.fromConfig(manifestConfig(instances: instances))['production']!,
  appName: 'shop',
  backendPort: 8080,
  capabilities: const DVInfraBackendCapabilities(portFromEnvironment: true),
  secretNames: const <String>{'DATABASE_URL', 'PAYSTACK_SECRET'},
);

final Map<String, String> secrets = <String, String>{
  'DATABASE_URL': dbUrl,
  'PAYSTACK_SECRET': secretValue,
};

String? lookup(String name) => secrets[name];

/// A host held in memory: what `apply` changes is what `observe` reports.
class FakeHost implements DVInfraHost {
  FakeHost({this.releasePresent = true});

  @override
  String get name => 'app-1.example.com';

  bool releasePresent;
  final Map<String, DVObservedResource> state = <String, DVObservedResource>{};
  final List<String> calls = <String>[];
  final Map<String, int> writes = <String, int>{};

  /// Fails the step with this id, this many times.
  String? failOn;
  int failures = 0;
  String failureText = 'refused';

  /// Units that exit as soon as they are started.
  final Set<String> crashing = <String>{};

  Map<String, DVObservedCertificate> certificates =
      <String, DVObservedCertificate>{};
  DateTime? lastVerifiedRestore;

  String k(DVInfraResourceKind kind, String id) => '${kind.name}:$id';

  @override
  Future<DVInfraObservation> observe() async => DVInfraObservation(
    host: name,
    releasePresent: releasePresent,
    resources: state.values.toList(),
    certificates: certificates,
    lastVerifiedRestore: lastVerifiedRestore,
  );

  @override
  Future<void> apply(
    DVInfraStep step,
    DVInfraResource? resource, {
    String? secretValue,
  }) async {
    if (step.id == failOn && failures > 0) {
      failures--;
      throw StateError(failureText);
    }
    calls.add('${step.action.name} ${step.id}');
    final String key = k(step.kind, step.id);
    final DVObservedResource? before = state[key];
    switch (step.action) {
      case DVInfraAction.install:
      case DVInfraAction.create:
        state[key] = DVObservedResource(kind: step.kind, id: step.id);
      case DVInfraAction.write:
        writes[step.id] = (writes[step.id] ?? 0) + 1;
        state[key] = DVObservedResource(
          kind: step.kind,
          id: step.id,
          sha256: resource!.contentSha256,
          mode: resource.mode,
          owner: resource.owner,
          firewall: resource.firewall,
          enabled: before?.enabled ?? false,
          active: before?.active ?? false,
        );
      case DVInfraAction.deliver:
        const String salt = 'fixed-salt';
        state[key] = DVObservedResource(
          kind: step.kind,
          id: step.id,
          credentialSalt: salt,
          credentialMac: dvInfraCredentialMac(salt, secretValue!),
        );
      case DVInfraAction.enable:
        state[key] = _with(before, step, enabled: true);
      case DVInfraAction.start:
      case DVInfraAction.restart:
        state[key] = _with(
          before,
          step,
          active: !crashing.contains(step.id),
        );
      case DVInfraAction.remove:
        state.remove(key);
    }
  }

  DVObservedResource _with(
    DVObservedResource? r,
    DVInfraStep step, {
    bool? enabled,
    bool? active,
  }) => DVObservedResource(
    kind: step.kind,
    id: step.id,
    sha256: r?.sha256,
    mode: r?.mode,
    owner: r?.owner,
    enabled: enabled ?? r?.enabled ?? false,
    active: active ?? r?.active ?? false,
  );
}

Future<DVInfraApplyResult> provision(
  FakeHost host, {
  DVInfraDesiredState? desired,
  bool confirmDestructive = false,
  DVInfraPlan? approved,
}) async {
  final DVInfraDesiredState d = desired ?? desiredState();
  final DVInfraPlan plan =
      approved ?? dvInfraPlan(d, await host.observe(), secret: lookup);
  return dvApplyInfraPlan(
    approved: plan,
    desired: d,
    host: host,
    secret: lookup,
    confirmDestructive: confirmDestructive,
  );
}

void main() {
  group('planning', () {
    test('a fresh host plans every resource, in dependency order', () async {
      final FakeHost host = FakeHost();
      final DVInfraPlan plan = dvInfraPlan(
        desiredState(),
        await host.observe(),
        secret: lookup,
      );
      final List<String> order =
          plan.steps.map((DVInfraStep s) => '${s.action.name} ${s.id}').toList();
      expect(order.first, 'install caddy');
      expect(
        order.indexOf('deliver PAYSTACK_SECRET'),
        lessThan(order.indexOf('start shop-backend-1.service')),
      );
      expect(
        order.indexOf('write /etc/nftables.conf'),
        lessThan(order.indexOf('start shop-backend-1.service')),
      );
      expect(plan.destructive, isEmpty);
    });

    test('the plan carries secret names and never their values', () async {
      final DVInfraPlan plan = dvInfraPlan(
        desiredState(),
        await FakeHost().observe(),
        secret: lookup,
      );
      final String json = plan.toJsonString();
      expect(json, contains('PAYSTACK_SECRET'));
      expect(json, isNot(contains(secretValue)));
      expect(json, isNot(contains('hunter2')));
    });

    test('a plan survives JSON with the same digest', () async {
      final DVInfraPlan plan = dvInfraPlan(
        desiredState(),
        await FakeHost().observe(),
        secret: lookup,
      );
      final DVInfraPlan back = DVInfraPlan.fromJsonString(plan.toJsonString());
      expect(back.digest, plan.digest);
      expect(back.steps.length, plan.steps.length);
    });

    test('a secret that cannot be resolved refuses the plan', () async {
      final DVInfraPlan plan = dvInfraPlan(
        desiredState(),
        await FakeHost().observe(),
        secret: (String name) => name == 'DATABASE_URL' ? dbUrl : null,
      );
      expect(plan.unsupported, anyElement(contains('PAYSTACK_SECRET')));
    });

    test('with no release on the host, services are enabled but not started',
        () async {
      final FakeHost host = FakeHost(releasePresent: false);
      final DVInfraPlan plan = dvInfraPlan(
        desiredState(),
        await host.observe(),
        secret: lookup,
      );
      final List<String> order =
          plan.steps.map((DVInfraStep s) => '${s.action.name} ${s.id}').toList();
      expect(order, contains('enable shop-backend-1.service'));
      expect(order, isNot(contains('start shop-backend-1.service')));
      // Caddy does not need a release to run.
      expect(order, contains('start caddy.service'));
      expect(plan.notes, anyElement(contains('/opt/shop/server')));
    });
  });

  group('applying', () {
    test('a provision applies, verifies, and a second one does nothing',
        () async {
      final FakeHost host = FakeHost();
      final DVInfraApplyResult first = await provision(host);
      expect(first.status, DVInfraApplyStatus.applied, reason: first.message);
      expect(first.ok, isTrue);

      final int calls = host.calls.length;
      final DVInfraApplyResult second = await provision(host);
      expect(second.ok, isTrue);
      expect(second.applied, isEmpty);
      expect(host.calls.length, calls);
    });

    test('a failure part way is a failure, naming what landed and what did '
        'not', () async {
      final FakeHost host = FakeHost()
        ..failOn = '/etc/nftables.conf'
        ..failures = 1;
      final DVInfraApplyResult result = await provision(host);
      expect(result.ok, isFalse);
      expect(result.status, DVInfraApplyStatus.failed);
      expect(result.failed!.id, '/etc/nftables.conf');
      expect(result.applied, isNotEmpty);
      expect(result.pending, isNotEmpty);
      expect(
        result.pending.map((DVInfraStep s) => s.id),
        contains('shop-backend-1.service'),
      );
    });

    test('a retry after a partial provision does not repeat what landed',
        () async {
      final FakeHost host = FakeHost()
        ..failOn = '/etc/nftables.conf'
        ..failures = 1;
      await provision(host);
      final int caddyWrites = host.writes['/etc/caddy/Caddyfile']!;
      final int installs =
          host.calls.where((String c) => c == 'install caddy').length;

      final DVInfraApplyResult retry = await provision(host);
      expect(retry.ok, isTrue, reason: retry.message);
      expect(host.writes['/etc/caddy/Caddyfile'], caddyWrites);
      expect(host.calls.where((String c) => c == 'install caddy').length, installs);
      expect(host.writes['/etc/nftables.conf'], 1);
    });

    test('a host that changed since the plan was approved is refused, and '
        'nothing is applied', () async {
      final FakeHost host = FakeHost();
      await provision(host);
      final DVInfraPlan approved = dvInfraPlan(
        desiredState(),
        await host.observe(),
        secret: lookup,
      );
      // Somebody edits a unit between approval and apply.
      host.state['unit:shop-backend-1.service'] = const DVObservedResource(
        kind: DVInfraResourceKind.unit,
        id: 'shop-backend-1.service',
        sha256: 'edited-by-hand',
        mode: '0644',
        owner: 'root',
        enabled: true,
        active: true,
      );
      final int calls = host.calls.length;
      final DVInfraApplyResult result = await provision(host, approved: approved);
      expect(result.status, DVInfraApplyStatus.refused);
      expect(result.message, contains('plan'));
      expect(host.calls.length, calls);
    });

    test('a manifest that changed since the plan was approved is refused',
        () async {
      final FakeHost host = FakeHost();
      final DVInfraPlan approved = dvInfraPlan(
        desiredState(),
        await host.observe(),
        secret: lookup,
      );
      final DVInfraApplyResult result = await provision(
        host,
        approved: approved,
        desired: desiredState(instances: 1),
      );
      expect(result.status, DVInfraApplyStatus.refused);
      expect(host.calls, isEmpty);
    });

    test('a destructive step is refused without confirmation, before any '
        'step runs', () async {
      final FakeHost host = FakeHost();
      await provision(host);
      final int calls = host.calls.length;

      final DVInfraDesiredState fewer = desiredState(instances: 1);
      final DVInfraApplyResult refused = await provision(host, desired: fewer);
      expect(refused.status, DVInfraApplyStatus.refused);
      expect(refused.message, contains('shop-backend-2.service'));
      expect(host.calls.length, calls);

      final DVInfraApplyResult confirmed = await provision(
        host,
        desired: fewer,
        confirmDestructive: true,
      );
      expect(confirmed.ok, isTrue, reason: confirmed.message);
      expect(host.state.containsKey('unit:shop-backend-2.service'), isFalse);
    });

    test('a unit that will not stay up leaves the provision unverified',
        () async {
      final FakeHost host = FakeHost()..crashing.add('shop-backend-2.service');
      final DVInfraApplyResult result = await provision(host);
      expect(result.ok, isFalse);
      expect(result.status, DVInfraApplyStatus.unverified);
      expect(
        result.remaining.map((DVInfraStep s) => s.id),
        contains('shop-backend-2.service'),
      );
    });

    test('a rotated secret is delivered and restarts what loads it', () async {
      final FakeHost host = FakeHost();
      await provision(host);
      host.calls.clear();
      secrets['PAYSTACK_SECRET'] = 'sk_live_rotated-value-0000';
      addTearDown(() => secrets['PAYSTACK_SECRET'] = secretValue);

      final DVInfraApplyResult result = await provision(host);
      expect(result.ok, isTrue, reason: result.message);
      expect(host.calls, contains('deliver PAYSTACK_SECRET'));
      expect(host.calls, contains('restart shop-backend-1.service'));
      expect(host.calls, contains('restart shop-backend-2.service'));
      // The backup does not load it and is not touched.
      expect(host.calls, isNot(contains('restart shop-backup.service')));
    });

    test('an unchanged secret is not delivered again', () async {
      final FakeHost host = FakeHost();
      await provision(host);
      host.calls.clear();
      await provision(host);
      expect(host.calls, isEmpty);
    });

    test('a host error that quotes a secret is redacted before it is '
        'reported', () async {
      final FakeHost host = FakeHost()
        ..failOn = 'PAYSTACK_SECRET'
        ..failures = 1
        ..failureText = 'could not encrypt $secretValue';
      final DVInfraApplyResult result = await provision(host);
      expect(result.ok, isFalse);
      expect(result.error, isNot(contains(secretValue)));
      expect(result.message, isNot(contains(secretValue)));
      expect(result.toString(), isNot(contains(secretValue)));
    });

    test('an unsupported declaration refuses the apply', () async {
      final FakeHost host = FakeHost();
      // logs.ship is still not built. Two instances were the refusal here
      // until the generated backend read DARTVEL_PORT and DARTVEL_ROLE.
      final Map<Object?, Object?> config = manifestConfig();
      (config['production']! as Map<Object?, Object?>)['logs'] =
          <Object?, Object?>{'ship': 'monitoring'};
      final DVInfraDesiredState d = dvInfraDesiredState(
        DVInfraManifest.fromConfig(config)['production']!,
        appName: 'shop',
        backendPort: 8080,
        secretNames: const <String>{'DATABASE_URL', 'PAYSTACK_SECRET'},
      );
      expect(d.unsupported, isNotEmpty);
      final DVInfraApplyResult result = await provision(host, desired: d);
      expect(result.status, DVInfraApplyStatus.refused);
      expect(host.calls, isEmpty);
    });
  });

  group('checking for drift', () {
    final DateTime now = DateTime.utc(2026, 9, 14, 12);

    Future<List<DVInfraFinding>> check(FakeHost host) async => dvInfraCheck(
      desired: desiredState(),
      observation: await host.observe(),
      secret: lookup,
      now: now,
    );

    Future<FakeHost> provisioned() async {
      final FakeHost host = FakeHost()
        ..lastVerifiedRestore = now.subtract(const Duration(days: 1))
        ..certificates = <String, DVObservedCertificate>{
          'api.example.com': DVObservedCertificate(
            notAfter: now.add(const Duration(days: 80)),
          ),
        };
      final DVInfraApplyResult r = await provision(host);
      expect(r.ok, isTrue, reason: r.message);
      return host;
    }

    test('a provisioned host has no findings', () async {
      expect(await check(await provisioned()), isEmpty);
    });

    test('a unit edited by hand is DV-INFRA-001', () async {
      final FakeHost host = await provisioned();
      final DVObservedResource unit = host.state['unit:shop-backend-1.service']!;
      host.state['unit:shop-backend-1.service'] = DVObservedResource(
        kind: unit.kind,
        id: unit.id,
        sha256: 'edited',
        mode: unit.mode,
        owner: unit.owner,
        enabled: true,
        active: true,
      );
      final List<DVInfraFinding> findings = await check(host);
      expect(findings.single.code, 'DV-INFRA-001');
      expect(findings.single.level, 'warning');
      expect(findings.single.message, contains('shop-backend-1.service'));
    });

    test('a firewall rule added during an incident is DV-INFRA-001', () async {
      final FakeHost host = await provisioned();
      final DVObservedResource fw = host.state['firewall:/etc/nftables.conf']!;
      host.state['firewall:/etc/nftables.conf'] = DVObservedResource(
        kind: fw.kind,
        id: fw.id,
        sha256: fw.sha256,
        mode: fw.mode,
        owner: fw.owner,
        firewall: const DVInfraFirewallRules(
          policy: 'drop',
          tcpPorts: <int>{22, 80, 443, 5432},
        ),
      );
      final List<DVInfraFinding> findings = await check(host);
      expect(findings.single.code, 'DV-INFRA-001');
      expect(findings.single.message, contains('5432'));
    });

    test('a package upgraded underneath is DV-INFRA-001', () async {
      final FakeHost host = await provisioned();
      host.state['package:caddy'] = const DVObservedResource(
        kind: DVInfraResourceKind.package,
        id: 'caddy',
        installedVersion: '2.8.4',
        recordedVersion: '2.7.6',
      );
      final List<DVInfraFinding> findings = await check(host);
      expect(findings.single.code, 'DV-INFRA-001');
      expect(findings.single.message, allOf(contains('2.7.6'), contains('2.8.4')));
    });

    test('a stopped service is DV-INFRA-003, not also drift', () async {
      final FakeHost host = await provisioned();
      final DVObservedResource unit = host.state['unit:shop-backend-2.service']!;
      host.state['unit:shop-backend-2.service'] = DVObservedResource(
        kind: unit.kind,
        id: unit.id,
        sha256: unit.sha256,
        mode: unit.mode,
        owner: unit.owner,
        enabled: true,
        active: false,
      );
      final List<DVInfraFinding> findings = await check(host);
      expect(findings.single.code, 'DV-INFRA-003');
      expect(findings.single.level, 'error');
    });

    test('with no release, the services are still reported not running',
        () async {
      final FakeHost host = await provisioned();
      host.releasePresent = false;
      for (final String id in <String>[
        'shop-backend-1.service',
        'shop-backend-2.service',
      ]) {
        final DVObservedResource unit = host.state['unit:$id']!;
        host.state['unit:$id'] = DVObservedResource(
          kind: unit.kind,
          id: id,
          sha256: unit.sha256,
          mode: unit.mode,
          owner: unit.owner,
          enabled: true,
        );
      }
      final List<DVInfraFinding> findings = await check(host);
      expect(findings.map((DVInfraFinding f) => f.code),
          everyElement('DV-INFRA-003'));
      expect(findings, hasLength(2));
    });

    test('a certificate close to expiry whose renewal fails is DV-INFRA-002',
        () async {
      final FakeHost host = await provisioned();
      host.certificates = <String, DVObservedCertificate>{
        'api.example.com': DVObservedCertificate(
          notAfter: now.add(const Duration(days: 9)),
          renewalFailing: true,
        ),
      };
      final List<DVInfraFinding> findings = await check(host);
      expect(findings.single.code, 'DV-INFRA-002');
      expect(findings.single.message, contains('api.example.com'));
    });

    test('a certificate close to expiry that is still renewing is not', () async {
      final FakeHost host = await provisioned();
      host.certificates = <String, DVObservedCertificate>{
        'api.example.com': DVObservedCertificate(
          notAfter: now.add(const Duration(days: 9)),
        ),
      };
      expect(await check(host), isEmpty);
    });

    test('a renewal failing far from expiry is not yet DV-INFRA-002', () async {
      final FakeHost host = await provisioned();
      host.certificates = <String, DVObservedCertificate>{
        'api.example.com': DVObservedCertificate(
          notAfter: now.add(const Duration(days: 60)),
          renewalFailing: true,
        ),
      };
      expect(await check(host), isEmpty);
    });

    test('no certificate at all, with renewal failing, is DV-INFRA-002',
        () async {
      final FakeHost host = await provisioned();
      host.certificates = <String, DVObservedCertificate>{
        'api.example.com': const DVObservedCertificate(renewalFailing: true),
      };
      expect((await check(host)).single.code, 'DV-INFRA-002');
    });

    test('a restore verified longer ago than the window is DV-INFRA-004',
        () async {
      final FakeHost host = await provisioned();
      host.lastVerifiedRestore = now.subtract(const Duration(days: 8));
      final List<DVInfraFinding> findings = await check(host);
      expect(findings.single.code, 'DV-INFRA-004');
      expect(findings.single.message, contains('8 days'));
    });

    test('a backup that has never been restored is DV-INFRA-004', () async {
      final FakeHost host = await provisioned();
      host.lastVerifiedRestore = null;
      final List<DVInfraFinding> findings = await check(host);
      expect(findings.single.code, 'DV-INFRA-004');
      expect(findings.single.message, contains('never'));
    });

    test('a finding takes its level from the registry', () {
      for (final String code in <String>[
        'DV-INFRA-001',
        'DV-INFRA-002',
        'DV-INFRA-003',
        'DV-INFRA-004',
      ]) {
        expect(
          DVInfraFinding(code, 'h', 'm').level,
          DVDiagnostics.find(code)!.level,
        );
      }
      expect(() => DVInfraFinding('DV-INFRA-999', 'h', 'm'), throwsArgumentError);
    });
  });
}
