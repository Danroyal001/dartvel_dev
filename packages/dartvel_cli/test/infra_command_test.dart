// dartvel infra plan | provision | check, driven against an in-memory host.
//
// The quiet failures at the command line: a provision that connects before
// finding out a required secret is missing; one that applies part of a plan
// and exits 0; a destructive step applied in CI because nobody was there to
// say no; a plan file approved yesterday applied to a host that has changed
// since; a secret value printed in a plan or written to the plan file; a
// check that cannot reach a host and reports it clean; and a check that
// finds a stopped service and exits 0.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/commands/infra_command.dart';
import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

const String secretValue = 'sk_live_correct-horse-battery-staple';
const String dbUrl = 'postgres://app:hunter2hunter2@db.internal/app';
const String hostKey =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ3w6s0R7p0mYtq2i6bqH6pX1bq9sQyZ4l8m2m6yJ0a1';

String pubspec({bool backup = true, int instances = 1}) => '''
name: shop
dartvel:
  secrets:
    PAYSTACK_SECRET:
      scope: backend
      required: [production]
    DATABASE_URL:
      scope: backend
      required: [production]
    PUBLIC_STRIPE_KEY:
      scope: client
      required: []
  infra:
    production:
      adapter: ssh
      hosts: [app-1.example.com]
      tls:
        domains: [api.example.com]
        acme: { email: ops@example.com }
      proxy: { adapter: caddy }
      services:
        backend: { instances: $instances }
        cron: { enabled: true }
${backup ? '''      database:
        adapter: postgres
        backup: { schedule: '0 3 * * *', retain: 30d }
''' : ''}''';

class FakeHost implements DVInfraHost {
  FakeHost(this.name);

  @override
  final String name;

  final Map<String, DVObservedResource> state = <String, DVObservedResource>{};
  final List<String> calls = <String>[];
  String? failOn;
  bool unreachable = false;

  @override
  Future<DVInfraObservation> observe() async {
    if (unreachable) throw StateError('ssh: connect to host $name: timed out');
    return DVInfraObservation(
      host: name,
      releasePresent: true,
      resources: state.values.toList(),
      lastVerifiedRestore: DateTime.now().toUtc(),
      certificates: <String, DVObservedCertificate>{
        'api.example.com': DVObservedCertificate(
          notAfter: DateTime.now().toUtc().add(const Duration(days: 80)),
        ),
      },
    );
  }

  @override
  Future<void> apply(
    DVInfraStep step,
    DVInfraResource? resource, {
    String? secretValue,
  }) async {
    if (step.id == failOn) throw StateError('apt-get: could not resolve host');
    calls.add('${step.action.name} ${step.id}');
    final String key = '${step.kind.name}:${step.id}';
    final DVObservedResource? before = state[key];
    DVObservedResource with_({bool? enabled, bool? active}) => DVObservedResource(
      kind: step.kind,
      id: step.id,
      sha256: before?.sha256,
      mode: before?.mode,
      owner: before?.owner,
      enabled: enabled ?? before?.enabled ?? false,
      active: active ?? before?.active ?? false,
    );
    switch (step.action) {
      case DVInfraAction.install:
      case DVInfraAction.create:
        state[key] = DVObservedResource(kind: step.kind, id: step.id);
      case DVInfraAction.write:
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
        state[key] = DVObservedResource(
          kind: step.kind,
          id: step.id,
          credentialSalt: 's',
          credentialMac: dvInfraCredentialMac('s', secretValue!),
        );
      case DVInfraAction.enable:
        state[key] = with_(enabled: true);
      case DVInfraAction.start:
      case DVInfraAction.restart:
        state[key] = with_(active: true);
      case DVInfraAction.remove:
        state.remove(key);
    }
  }
}

void main() {
  late Directory root;
  late FakeHost host;
  late List<String> out;
  late Map<String, String> environment;
  late Map<String, String> secrets;
  late List<String?> answers;
  late int hostsBuilt;
  bool onPath = true;
  bool interactive = false;

  DVInfraCli cli() => DVInfraCli(
    root: root.path,
    environment: environment,
    onPath: (String exe) => onPath,
    secretLookup: (String name) => secrets[name],
    hostFactory: (String name, DVInfraDesiredState desired) {
      hostsBuilt++;
      return host;
    },
    interactive: interactive,
    readLine: () => answers.isEmpty ? null : answers.removeAt(0),
    out: out.add,
  );

  String printed() => out.join('\n');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_infra_cli_');
    File('${root.path}/pubspec.yaml').writeAsStringSync(pubspec());
    Directory('${root.path}/infra').createSync();
    File('${root.path}/infra/known_hosts')
        .writeAsStringSync('app-1.example.com $hostKey\n');
    host = FakeHost('app-1.example.com');
    out = <String>[];
    environment = <String, String>{'CI': 'true'};
    secrets = <String, String>{
      'PAYSTACK_SECRET': secretValue,
      'DATABASE_URL': dbUrl,
      // Resolves too, so leaving it out of the plan is the scope rule at
      // work rather than an unset value.
      'PUBLIC_STRIPE_KEY': 'pk_live_publishable-and-public',
    };
    answers = <String?>[];
    hostsBuilt = 0;
    onPath = true;
    interactive = false;
  });

  tearDown(() {
    expect(printed(), isNot(contains(secretValue)));
    expect(printed(), isNot(contains('hunter2')));
    root.deleteSync(recursive: true);
  });

  group('before connecting', () {
    test('no ssh client stops with instructions, connecting to nothing',
        () async {
      onPath = false;
      expect(await cli().plan('production'), 1);
      expect(printed(), contains('ssh'));
      expect(printed(), contains('openssh'));
      expect(hostsBuilt, 0);
    });

    test('an environment the manifest does not declare names the key',
        () async {
      expect(await cli().plan('staging'), 1);
      expect(printed(), contains('dartvel.infra.staging'));
      expect(hostsBuilt, 0);
    });

    test('a manifest that cannot be read is refused, naming the setting',
        () async {
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        pubspec().replaceFirst('instances: 1', 'instance: 1'),
      );
      expect(await cli().plan('production'), 1);
      expect(printed(), contains('dartvel.infra.production.services.backend.instance'));
      expect(hostsBuilt, 0);
    });

    test('a required secret that does not resolve stops before any host is '
        'reached', () async {
      secrets.remove('PAYSTACK_SECRET');
      expect(await cli().provision('production'), 1);
      expect(printed(), contains('PAYSTACK_SECRET'));
      expect(hostsBuilt, 0);
      expect(host.calls, isEmpty);
    });

    test('a secret declaration dartvel build would refuse stops here too',
        () async {
      // A client-scoped name without the PUBLIC_ prefix, or a backend one
      // spelt with it, says two things about the same value. dartvel build
      // refuses it; a provision that went ahead would deliver by one reading
      // of it and the bundle would ship by the other.
      File('${root.path}/pubspec.yaml').writeAsStringSync(pubspec().replaceFirst(
        '  infra:\n',
        '    MAP_TOKEN:\n      scope: client\n      required: []\n  infra:\n',
      ));
      secrets['MAP_TOKEN'] = 'map-token-value-123';
      expect(await cli().plan('production'), 1);
      expect(printed(), contains('MAP_TOKEN'));
      expect(printed(), contains('PUBLIC_'));
      expect(hostsBuilt, 0);
    });

    test('a missing known_hosts file is refused with how to make one',
        () async {
      File('${root.path}/infra/known_hosts').deleteSync();
      expect(await cli().plan('production'), 1);
      expect(printed(), contains('infra/known_hosts'));
      expect(printed(), contains('ssh-keyscan'));
      expect(hostsBuilt, 0);
    });

    test('the default adapter refuses a host the file does not pin', () async {
      File('${root.path}/infra/known_hosts')
          .writeAsStringSync('other.example.com $hostKey\n');
      final List<List<String>> ran = <List<String>>[];
      final DVInfraCli real = DVInfraCli(
        root: root.path,
        environment: environment,
        onPath: (String exe) => true,
        secretLookup: (String name) => secrets[name],
        sshRun: (String exe, List<String> args, {List<int>? stdin}) async {
          ran.add(args);
          throw StateError('must not run');
        },
        out: out.add,
      );
      expect(await real.plan('production'), 1);
      expect(printed(), contains('not pinned'));
      expect(ran, isEmpty);
    });
  });

  group('plan', () {
    test('lists the steps, changes nothing, and writes names not values',
        () async {
      final String file = '${root.path}/plan.json';
      expect(await cli().plan('production', outFile: file), 0);
      expect(printed(), contains('install caddy'));
      expect(printed(), contains('deliver PAYSTACK_SECRET'));
      expect(host.calls, isEmpty);
      final String json = File(file).readAsStringSync();
      expect(json, contains('PAYSTACK_SECRET'));
      expect(json, isNot(contains(secretValue)));
      expect(json, isNot(contains('hunter2')));
      // A client-scoped secret ships in the bundle; it is not delivered.
      expect(json, isNot(contains('PUBLIC_STRIPE_KEY')));
      expect(jsonDecode(json), isA<Map<String, Object?>>());
    });

    test('says what it cannot do', () async {
      File('${root.path}/pubspec.yaml').writeAsStringSync(pubspec(instances: 2));
      expect(await cli().plan('production'), 1);
      expect(printed(), contains('instances'));
    });
  });

  group('provision', () {
    test('a fresh host is provisioned and verified', () async {
      expect(await cli().provision('production'), 0, reason: printed());
      expect(host.calls, contains('install caddy'));
      expect(printed(), contains('verified'));
    });

    test('a failure part way exits non-zero, naming the step', () async {
      host.failOn = 'nftables';
      expect(await cli().provision('production'), 1);
      expect(printed(), contains('nftables'));
      expect(printed(), contains('could not resolve host'));
    });

    test('an unsupported declaration applies nothing', () async {
      File('${root.path}/pubspec.yaml').writeAsStringSync(pubspec(instances: 2));
      expect(await cli().provision('production'), 1);
      expect(host.calls, isEmpty);
    });

    test('in CI a destructive plan needs --confirm-destructive', () async {
      expect(await cli().provision('production'), 0);
      host.calls.clear();
      File('${root.path}/pubspec.yaml').writeAsStringSync(pubspec(backup: false));

      expect(await cli().provision('production'), 1);
      expect(printed(), contains('shop-backup.timer'));
      expect(printed(), contains('--confirm-destructive'));
      expect(host.calls, isEmpty);

      expect(
        await cli().provision('production', confirmDestructive: true),
        0,
        reason: printed(),
      );
      expect(host.calls, contains('remove shop-backup.timer'));
    });

    test('at a terminal a destructive plan asks, and only "yes" proceeds',
        () async {
      environment = <String, String>{};
      interactive = true;
      expect(await cli().provision('production'), 0);
      host.calls.clear();
      File('${root.path}/pubspec.yaml').writeAsStringSync(pubspec(backup: false));

      answers = <String?>['y'];
      expect(await cli().provision('production'), 1);
      expect(host.calls, isEmpty);

      answers = <String?>['yes'];
      expect(await cli().provision('production'), 0, reason: printed());
      expect(host.calls, contains('remove shop-backup.timer'));
    });

    test('a plan file is applied only while it is still the plan', () async {
      final String file = '${root.path}/plan.json';
      expect(await cli().plan('production', outFile: file), 0);
      // Somebody provisions (or edits) the host in between.
      host.state['package:caddy'] = const DVObservedResource(
        kind: DVInfraResourceKind.package,
        id: 'caddy',
      );
      expect(await cli().provision('production', planFile: file), 1);
      expect(printed(), contains('plan again'));
      expect(host.calls, isEmpty);
    });

    test('an untouched plan file is applied', () async {
      final String file = '${root.path}/plan.json';
      expect(await cli().plan('production', outFile: file), 0);
      expect(await cli().provision('production', planFile: file), 0,
          reason: printed());
    });

    test('a plan file edited by hand is refused', () async {
      final String file = '${root.path}/plan.json';
      expect(await cli().plan('production', outFile: file), 0);
      File(file).writeAsStringSync(
        File(file).readAsStringSync().replaceFirst('install', 'remove'),
      );
      expect(await cli().provision('production', planFile: file), 1);
      expect(host.calls, isEmpty);
    });
  });

  group('check', () {
    test('a provisioned host checks clean and exits 0', () async {
      expect(await cli().provision('production'), 0);
      out.clear();
      expect(await cli().check('production'), 0, reason: printed());
      expect(printed(), contains('no findings'));
    });

    test('a stopped service is DV-INFRA-003 and exits non-zero', () async {
      expect(await cli().provision('production'), 0);
      final DVObservedResource unit = host.state['unit:shop-backend-1.service']!;
      host.state['unit:shop-backend-1.service'] = DVObservedResource(
        kind: unit.kind,
        id: unit.id,
        sha256: unit.sha256,
        mode: unit.mode,
        owner: unit.owner,
        enabled: true,
      );
      out.clear();
      expect(await cli().check('production'), 1);
      expect(printed(), contains('DV-INFRA-003'));
    });

    test('drift alone is reported and is a warning, not a failure', () async {
      expect(await cli().provision('production'), 0);
      host.state.remove('file:/etc/caddy/Caddyfile');
      out.clear();
      expect(await cli().check('production'), 0);
      expect(printed(), contains('DV-INFRA-001'));
    });

    test('--json prints the findings as JSON', () async {
      expect(await cli().provision('production'), 0);
      host.state.remove('file:/etc/caddy/Caddyfile');
      out.clear();
      expect(await cli().check('production', json: true), 0);
      final Object? decoded = jsonDecode(printed());
      expect(decoded, isA<List<Object?>>());
      expect(((decoded! as List<Object?>).first! as Map<String, Object?>)['code'],
          'DV-INFRA-001');
    });

    test('a host that cannot be reached is not reported clean', () async {
      host.unreachable = true;
      expect(await cli().check('production'), 1);
      expect(printed(), contains('timed out'));
      expect(printed(), isNot(contains('no findings')));
    });
  });
}
