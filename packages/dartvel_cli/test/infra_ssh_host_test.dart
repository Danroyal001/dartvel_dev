// The SSH adapter behind dartvel infra: how it connects, what it sends, and
// how it reads a host back.
//
// The quiet failures: a host key accepted because nothing pinned it; an ssh
// option that turns verification off, or a destination that ssh reads as an
// option; a secret value placed on a command line, in a script, or in an
// exception; a firewall ruleset loaded before it was checked; and an
// observation parsed so that a rule added by hand, or a stopped unit, reads
// as matching.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/infra/ssh_host.dart';
import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

const String secretValue = 'sk_live_correct-horse-battery-staple';

const String rsaKey =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ3w6s0R7p0mYtq2i6bqH6pX1bq9sQyZ4l8m2m6yJ0a1';

DVInfraDesiredState desired({String user = 'root', int port = 22}) =>
    dvInfraDesiredState(
      DVInfraManifest.fromConfig(<Object?, Object?>{
        'production': <Object?, Object?>{
          'hosts': <Object?>['app-1.example.com'],
          'ssh': <Object?, Object?>{'user': user, 'port': port},
          'tls': <Object?, Object?>{
            'domains': <Object?>['api.example.com'],
            'acme': <Object?, Object?>{'email': 'ops@example.com'},
          },
          'proxy': <Object?, Object?>{'adapter': 'caddy'},
          'database': <Object?, Object?>{
            'adapter': 'postgres',
            'backup': <Object?, Object?>{
              'schedule': '0 3 * * *',
              'retain': '30d',
            },
          },
        },
      })['production']!,
      appName: 'shop',
      backendPort: 8080,
      secretNames: const <String>{'DATABASE_URL', 'PAYSTACK_SECRET'},
    );

class Call {
  Call(this.executable, this.arguments, this.stdin);
  final String executable;
  final List<String> arguments;
  final List<int>? stdin;
  String get stdinText => stdin == null ? '' : utf8.decode(stdin!);
  String get remote => arguments.last;
}

class Runner {
  final List<Call> calls = <Call>[];
  DVSshOutput Function(Call call) answer =
      (Call c) => const DVSshOutput(0, '', '');

  Future<DVSshOutput> call(
    String executable,
    List<String> arguments, {
    List<int>? stdin,
  }) async {
    final Call c = Call(executable, arguments, stdin);
    calls.add(c);
    return answer(c);
  }
}

DVSshInfraHost hostFor(
  Runner runner, {
  DVInfraDesiredState? state,
  String knownHosts = 'app-1.example.com $rsaKey\n',
}) {
  final DVInfraDesiredState d = state ?? desired();
  return DVSshInfraHost(
    host: 'app-1.example.com',
    desired: d,
    knownHostsPath: '/project/infra/known_hosts',
    knownHostsText: knownHosts,
    run: runner.call,
    salt: () => 'aabbccddeeff00112233445566778899',
  );
}

DVInfraStep stepFor(DVInfraAction action, DVInfraResource r) =>
    DVInfraStep(action: action, kind: r.kind, id: r.id, reason: 'test');

String hashedEntry(String host, List<int> salt) {
  final List<int> mac = Hmac(sha1, salt).convert(utf8.encode(host)).bytes;
  return '|1|${base64.encode(salt)}|${base64.encode(mac)}';
}

void main() {
  group('host keys', () {
    test('a plain entry pins the host on port 22', () {
      expect(
        dvKnownHostsPins('app-1.example.com $rsaKey', 'app-1.example.com', 22),
        isTrue,
      );
    });

    test('a comma list pins each name', () {
      expect(
        dvKnownHostsPins(
          'app-2,app-1.example.com,10.0.0.5 $rsaKey',
          'app-1.example.com',
          22,
        ),
        isTrue,
      );
    });

    test('a hashed entry pins the host it was hashed for, and no other', () {
      final String line =
          '${hashedEntry('app-1.example.com', List<int>.generate(20, (int i) => i))} $rsaKey';
      expect(dvKnownHostsPins(line, 'app-1.example.com', 22), isTrue);
      expect(dvKnownHostsPins(line, 'app-2.example.com', 22), isFalse);
    });

    test('a non-standard port needs the bracketed form', () {
      expect(
        dvKnownHostsPins('app-1.example.com $rsaKey', 'app-1.example.com', 2222),
        isFalse,
      );
      expect(
        dvKnownHostsPins(
          '[app-1.example.com]:2222 $rsaKey',
          'app-1.example.com',
          2222,
        ),
        isTrue,
      );
    });

    test('a key pinned and later revoked is no longer pinned', () {
      // The line that matters is the one added after the first: a key that
      // leaked stays in known_hosts under @revoked, and trusting the older
      // plain line anyway is trusting the leaked key.
      expect(
        dvKnownHostsPins(
          'app-1.example.com $rsaKey\n@revoked app-1.example.com $rsaKey\n',
          'app-1.example.com',
          22,
        ),
        isFalse,
      );
    });

    test('a revoked key, a CA line, a comment and a wildcard do not pin', () {
      for (final String line in <String>[
        '@revoked app-1.example.com $rsaKey',
        '@cert-authority app-1.example.com $rsaKey',
        '# app-1.example.com $rsaKey',
        '*.example.com $rsaKey',
        'app-1.example.com',
      ]) {
        expect(
          dvKnownHostsPins(line, 'app-1.example.com', 22),
          isFalse,
          reason: line,
        );
      }
    });

    test('a host the file does not pin is refused before anything runs', () {
      final Runner runner = Runner();
      expect(
        () => hostFor(runner, knownHosts: 'other.example.com $rsaKey\n'),
        throwsA(
          isA<DVSshHostNotPinned>().having(
            (DVSshHostNotPinned e) => e.toString(),
            'message',
            allOf(contains('app-1.example.com'), contains('known_hosts')),
          ),
        ),
      );
      expect(runner.calls, isEmpty);
    });
  });

  group('connecting', () {
    test('every connection verifies the pinned key and never asks', () async {
      final Runner runner = Runner();
      final DVSshInfraHost host = hostFor(runner);
      final DVInfraDesiredState d = desired();
      await host.apply(
        stepFor(DVInfraAction.install, d.byId('caddy')!),
        d.byId('caddy'),
      );
      await host.observe().catchError((Object _) => const DVInfraObservation(
            host: 'x',
            resources: <DVObservedResource>[],
          ));
      expect(runner.calls, hasLength(2));
      for (final Call c in runner.calls) {
        expect(c.executable, 'ssh');
        final String args = c.arguments.join(' ');
        expect(args, contains('StrictHostKeyChecking=yes'));
        expect(args, contains('UserKnownHostsFile=/project/infra/known_hosts'));
        expect(args, contains('GlobalKnownHostsFile=/dev/null'));
        expect(args, contains('BatchMode=yes'));
        expect(args, contains('UpdateHostKeys=no'));
        expect(args, isNot(contains('accept-new')));
        expect(args, isNot(contains('StrictHostKeyChecking=no')));
        // The destination follows `--`, so it can never be read as an option.
        final int dashes = c.arguments.indexOf('--');
        expect(dashes, greaterThan(0));
        expect(c.arguments[dashes + 1], 'app-1.example.com');
      }
    });

    test('the port and user are passed as options, not in the destination',
        () async {
      final Runner runner = Runner();
      final DVInfraDesiredState d = desired(user: 'deploy', port: 2222);
      final DVSshInfraHost host = hostFor(
        runner,
        state: d,
        knownHosts: '[app-1.example.com]:2222 $rsaKey\n',
      );
      await host.apply(
        stepFor(DVInfraAction.enable, d.byId('caddy.service')!),
        d.byId('caddy.service'),
      );
      final List<String> args = runner.calls.single.arguments;
      expect(args.sublist(0, args.indexOf('--')), containsAllInOrder(<String>['-p', '2222']));
      expect(args.sublist(0, args.indexOf('--')), containsAllInOrder(<String>['-l', 'deploy']));
      // Not root: every step runs through sudo, which must not prompt.
      expect(runner.calls.single.remote, startsWith('sudo -n '));
    });
  });

  group('delivering a secret', () {
    test('the value travels on stdin only', () async {
      final Runner runner = Runner();
      final DVInfraDesiredState d = desired();
      await hostFor(runner).apply(
        stepFor(DVInfraAction.deliver, d.byId('PAYSTACK_SECRET')!),
        d.byId('PAYSTACK_SECRET'),
        secretValue: secretValue,
      );
      final Call c = runner.calls.single;
      expect(c.stdinText, secretValue);
      expect(c.arguments.join(' '), isNot(contains(secretValue)));
      expect(c.remote, contains('systemd-creds encrypt'));
      expect(c.remote, contains('/etc/credstore.encrypted/shop.PAYSTACK_SECRET'));
      // The HMAC beside it, never the value.
      final String mac = dvInfraCredentialMac(
        'aabbccddeeff00112233445566778899',
        secretValue,
      );
      expect(c.remote, contains(mac));
    });

    test('a failure does not quote what was on stdin', () async {
      final Runner runner = Runner()
        ..answer = (Call c) => const DVSshOutput(1, '', 'systemd-creds: no TPM');
      final DVInfraDesiredState d = desired();
      Object? caught;
      try {
        await hostFor(runner).apply(
          stepFor(DVInfraAction.deliver, d.byId('PAYSTACK_SECRET')!),
          d.byId('PAYSTACK_SECRET'),
          secretValue: secretValue,
        );
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect('$caught', contains('no TPM'));
      expect('$caught', isNot(contains(secretValue)));
    });

    test('a deliver with no value is refused rather than sending nothing',
        () async {
      final Runner runner = Runner();
      final DVInfraDesiredState d = desired();
      await expectLater(
        hostFor(runner).apply(
          stepFor(DVInfraAction.deliver, d.byId('PAYSTACK_SECRET')!),
          d.byId('PAYSTACK_SECRET'),
        ),
        throwsA(anything),
      );
      expect(runner.calls, isEmpty);
    });
  });

  group('writing', () {
    test('file content goes on stdin and lands atomically with its mode',
        () async {
      final Runner runner = Runner();
      final DVInfraDesiredState d = desired();
      final DVInfraResource caddy = d.byId('/etc/caddy/Caddyfile')!;
      await hostFor(runner).apply(stepFor(DVInfraAction.write, caddy), caddy);
      final Call c = runner.calls.single;
      expect(c.stdinText, caddy.content);
      expect(c.remote, contains('mktemp'));
      expect(c.remote, contains('0644'));
      expect(c.remote, contains('mv -f'));
    });

    test('a unit write reloads systemd', () async {
      final Runner runner = Runner();
      final DVInfraDesiredState d = desired();
      final DVInfraResource unit = d.byId('shop-backup.timer')!;
      await hostFor(runner).apply(stepFor(DVInfraAction.write, unit), unit);
      expect(runner.calls.single.remote, contains('systemctl daemon-reload'));
    });

    test('a firewall ruleset is checked before it replaces the old one', () async {
      final Runner runner = Runner();
      final DVInfraDesiredState d = desired();
      final DVInfraResource fw = d.byId('/etc/nftables.conf')!;
      await hostFor(runner).apply(stepFor(DVInfraAction.write, fw), fw);
      final String remote = runner.calls.single.remote;
      expect(remote, contains('nft -c -f'));
      expect(remote.indexOf('nft -c -f'), lessThan(remote.indexOf('mv -f')));
    });

    test('removing something whose name is not a plain unit or path is refused',
        () async {
      final Runner runner = Runner();
      for (final String id in <String>[
        "evil.service; rm -rf /",
        'x\$(id).service',
        '../../etc/passwd',
      ]) {
        await expectLater(
          hostFor(runner).apply(
            DVInfraStep(
              action: DVInfraAction.remove,
              kind: DVInfraResourceKind.unit,
              id: id,
              reason: 'test',
            ),
            null,
          ),
          throwsA(anything),
          reason: id,
        );
      }
      expect(runner.calls, isEmpty);
    });

    test('every script it sends is valid shell', () async {
      if (Platform.isWindows) return;
      final Runner runner = Runner();
      final DVInfraDesiredState d = desired();
      final DVSshInfraHost host = hostFor(runner);
      for (final DVInfraResource r in d.resources) {
        for (final DVInfraAction a in DVInfraAction.values) {
          try {
            await host.apply(
              stepFor(a, r),
              a == DVInfraAction.remove ? null : r,
              secretValue: secretValue,
            );
          } on Object {
            // Not every action applies to every kind.
          }
        }
      }
      await host.observe().catchError((Object _) => const DVInfraObservation(
            host: 'x',
            resources: <DVObservedResource>[],
          ));
      expect(runner.calls.length, greaterThan(20));
      for (final Call c in runner.calls) {
        final String script = dvSshScriptOf(c.remote);
        final ProcessResult r = await Process.run('sh', <String>['-n', '-c', script]);
        expect(r.exitCode, 0, reason: '${r.stderr}\n$script');
      }
    });
  });

  group('observing', () {
    const String ruleset = '''
table inet dartvel {
	chain input {
		type filter hook input priority filter; policy drop;
		ct state established,related accept
		ct state invalid drop
		iifname "lo" accept
		meta l4proto { icmp, ipv6-icmp } accept
		tcp dport { 22, 80, 443 } accept
		tcp dport 5432 accept
	}
	chain forward {
		type filter hook forward priority filter; policy drop;
	}
}
''';

    test('the live ruleset is read for what it opens', () {
      final DVInfraFirewallRules rules = dvParseNftRuleset(ruleset);
      expect(rules.policy, 'drop');
      expect(rules.tcpPorts, <int>{22, 80, 443, 5432});
    });

    test('an empty ruleset is a firewall that lets everything in', () {
      expect(dvParseNftRuleset('').policy, 'accept');
    });

    test('a second table cannot open what the first one drops', () {
      // Every base chain on the input hook sees the packet. A drop in any of
      // them is final and an accept is not, so the incident table's accept
      // opens nothing while the dartvel chain still drops it.
      final DVInfraFirewallRules rules = dvParseNftRuleset('''
$ruleset
table ip incident {
	chain input {
		type filter hook input priority -10; policy accept;
		udp dport 51820 accept
	}
}
''');
      expect(rules.policy, 'drop');
      expect(rules.udpPorts, isNot(contains(51820)));
      expect(rules.tcpPorts, <int>{22, 80, 443, 5432});
    });

    test('a rule accepting everything opens everything', () {
      final DVInfraFirewallRules rules = dvParseNftRuleset(
        ruleset.replaceFirst('tcp dport 5432 accept', 'accept'),
      );
      expect(rules.policy, 'accept');
    });

    test('an accept rule it cannot read is treated as open, not ignored', () {
      final DVInfraFirewallRules rules = dvParseNftRuleset(
        ruleset.replaceFirst(
          'tcp dport 5432 accept',
          'meta l4proto tcp th dport 5432 accept',
        ),
      );
      expect(rules.policy, 'accept');
    });

    test('a port range is read as every port in it', () {
      final DVInfraFirewallRules rules = dvParseNftRuleset(
        ruleset.replaceFirst('tcp dport 5432 accept', 'tcp dport 6000-6002 accept'),
      );
      expect(rules.tcpPorts, containsAll(<int>[6000, 6001, 6002]));
    });

    test('the observer report becomes an observation', () {
      final String report = <String>[
        'release yes',
        'pkg caddy 2.8.4 2.7.6',
        'pkg nftables 1.0.9 1.0.9',
        'user shop',
        'file /etc/caddy/Caddyfile ${'a' * 64} 644 root',
        'unit shop-backend-1.service ${'b' * 64} 644 root enabled active',
        'unit caddy.service - - - enabled failed',
        'fw /etc/nftables.conf ${'c' * 64} 644 root',
        'fwlive ${base64.encode(utf8.encode(ruleset))}',
        'cred PAYSTACK_SECRET 00ff 1234abcd',
        'cred DATABASE_URL - -',
        'cert api.example.com 1789000000 yes',
        'restore 1788000000',
      ].join('\n');
      final DVInfraObservation o = dvParseInfraObservation(
        'app-1.example.com',
        report,
      );
      expect(o.releasePresent, isTrue);
      final DVObservedResource caddy = o.find(DVInfraResourceKind.package, 'caddy')!;
      expect(caddy.installedVersion, '2.8.4');
      expect(caddy.recordedVersion, '2.7.6');
      expect(o.find(DVInfraResourceKind.user, 'shop'), isNotNull);
      expect(o.find(DVInfraResourceKind.file, '/etc/caddy/Caddyfile')!.mode, '0644');
      final DVObservedResource backend =
          o.find(DVInfraResourceKind.unit, 'shop-backend-1.service')!;
      expect(backend.enabled, isTrue);
      expect(backend.active, isTrue);
      final DVObservedResource caddyUnit =
          o.find(DVInfraResourceKind.unit, 'caddy.service')!;
      expect(caddyUnit.sha256, isNull);
      expect(caddyUnit.active, isFalse);
      final DVObservedResource fw =
          o.find(DVInfraResourceKind.firewall, '/etc/nftables.conf')!;
      expect(fw.firewall!.tcpPorts, contains(5432));
      expect(
        o.find(DVInfraResourceKind.credential, 'PAYSTACK_SECRET')!.credentialMac,
        '1234abcd',
      );
      expect(
        o.find(DVInfraResourceKind.credential, 'DATABASE_URL')!.credentialMac,
        isNull,
      );
      expect(o.certificates['api.example.com']!.renewalFailing, isTrue);
      expect(
        o.certificates['api.example.com']!.notAfter,
        DateTime.fromMillisecondsSinceEpoch(1789000000 * 1000, isUtc: true),
      );
      expect(
        o.lastVerifiedRestore,
        DateTime.fromMillisecondsSinceEpoch(1788000000 * 1000, isUtc: true),
      );
    });

    test('a report line it does not understand fails the observation', () {
      // Skipping it would read as a host with less on it than it has.
      expect(
        () => dvParseInfraObservation('h', 'unit shop.service garbage'),
        throwsFormatException,
      );
    });

    test('a failed observation is an error, not an empty host', () async {
      final Runner runner = Runner()
        ..answer = (Call c) => const DVSshOutput(255, '', 'Host key verification failed.');
      await expectLater(
        hostFor(runner).observe(),
        throwsA(
          predicate((Object e) => '$e'.contains('Host key verification failed')),
        ),
      );
    });
  });
}
