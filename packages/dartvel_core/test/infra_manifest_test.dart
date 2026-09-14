// `dartvel.infra`: what a provisioned host is declared to have, and the
// resources that declaration becomes.
//
// The quiet failures this guards: a typo in a key that quietly became a
// default; a firewall that opens nothing but also closes nothing, or closes
// the port the provisioner itself connects on; a declaration the provisioner
// cannot honour that is dropped rather than refused, so a host is reported
// provisioned without it; a backup schedule translated into a timer that
// fires on a different day from the cron line it came from; and a secret
// value that reaches a file, a unit or a plan.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<Object?, Object?> specExample() => <Object?, Object?>{
  'production': <Object?, Object?>{
    'adapter': 'ssh',
    'hosts': <Object?>['app-1.example.com'],
    'tls': <Object?, Object?>{
      'domains': <Object?>['api.example.com'],
      'acme': <Object?, Object?>{'email': 'ops@example.com'},
    },
    'proxy': <Object?, Object?>{'adapter': 'caddy'},
    'services': <Object?, Object?>{
      'backend': <Object?, Object?>{'instances': 2},
      'workers': <Object?, Object?>{
        'queues': <Object?>['default', 'mail'],
        'instances': 2,
      },
      'cron': <Object?, Object?>{'enabled': true},
    },
    'database': <Object?, Object?>{
      'adapter': 'postgres',
      'backup': <Object?, Object?>{'schedule': '0 3 * * *', 'retain': '30d'},
    },
    'logs': <Object?, Object?>{'ship': 'monitoring'},
  },
};

DVInfraManifest production([Map<Object?, Object?>? config]) =>
    DVInfraManifest.fromConfig(config ?? specExample())['production']!;

const DVInfraBackendCapabilities everything = DVInfraBackendCapabilities(
  portFromEnvironment: true,
  workerRole: true,
  cronRole: true,
);

/// A backend generated before it read DARTVEL_PORT and DARTVEL_ROLE.
const DVInfraBackendCapabilities beforeRoles = DVInfraBackendCapabilities(
  portFromEnvironment: false,
  workerRole: false,
  cronRole: false,
);

DVInfraDesiredState desired(
  DVInfraManifest manifest, {
  DVInfraBackendCapabilities capabilities = everything,
  Set<String> secrets = const <String>{'DATABASE_URL', 'PAYSTACK_SECRET'},
}) => dvInfraDesiredState(
  manifest,
  appName: 'shop',
  backendPort: 8080,
  capabilities: capabilities,
  secretNames: secrets,
);

Map<Object?, Object?> edited(void Function(Map<Object?, Object?> env) edit) {
  final Map<Object?, Object?> config = specExample();
  edit(config['production']! as Map<Object?, Object?>);
  return config;
}

void main() {
  group('reading the manifest', () {
    test('the specification example reads', () {
      final DVInfraManifest m = production();
      expect(m.environment, 'production');
      expect(m.adapter, DVInfraAdapterKind.ssh);
      expect(m.hosts, <String>['app-1.example.com']);
      expect(m.tls!.domains, <String>['api.example.com']);
      expect(m.tls!.acmeEmail, 'ops@example.com');
      expect(m.proxy, 'caddy');
      expect(m.services.backendInstances, 2);
      expect(m.services.workerQueues, <String>['default', 'mail']);
      expect(m.services.workerInstances, 2);
      expect(m.services.cron, isTrue);
      expect(m.database!.backup!.schedule, '0 3 * * *');
      expect(m.database!.backup!.retain, const Duration(days: 30));
      expect(m.logsShip, 'monitoring');
    });

    test('an unknown key is refused, naming its path', () {
      expect(
        () => production(edited((Map<Object?, Object?> e) => e['host'] = 'x')),
        throwsA(
          isA<FormatException>().having(
            (FormatException f) => f.message,
            'message',
            contains('dartvel.infra.production.host'),
          ),
        ),
      );
    });

    test('a misspelt nested key is refused rather than defaulted', () {
      expect(
        () => production(
          edited(
            (Map<Object?, Object?> e) =>
                (e['services']! as Map<Object?, Object?>)['backend'] =
                    <Object?, Object?>{'instance': 2},
          ),
        ),
        throwsFormatException,
      );
    });

    test('no hosts is refused', () {
      expect(
        () => production(
          edited((Map<Object?, Object?> e) => e['hosts'] = <Object?>[]),
        ),
        throwsFormatException,
      );
    });

    test('a host that would be interpreted by a shell is refused', () {
      for (final String host in <String>[
        'app-1.example.com; rm -rf /',
        'root@app-1',
        '-oProxyCommand=evil',
        r'$(id)',
      ]) {
        expect(
          () => production(
            edited((Map<Object?, Object?> e) => e['hosts'] = <Object?>[host]),
          ),
          throwsFormatException,
          reason: host,
        );
      }
    });

    test('an unknown adapter is refused', () {
      expect(
        () => production(
          edited((Map<Object?, Object?> e) => e['adapter'] = 'ansible'),
        ),
        throwsFormatException,
      );
    });

    test('a retention that is not days or hours is refused', () {
      for (final Object? retain in <Object?>['30', 'forever', 30, '0d']) {
        expect(
          () => production(
            edited(
              (Map<Object?, Object?> e) =>
                  ((e['database']! as Map<Object?, Object?>)['backup']!
                          as Map<Object?, Object?>)['retain'] =
                      retain,
            ),
          ),
          throwsFormatException,
          reason: '$retain',
        );
      }
    });

    test('TLS without a proxy is refused: nothing would terminate it', () {
      expect(
        () => production(
          edited((Map<Object?, Object?> e) => e.remove('proxy')),
        ),
        throwsFormatException,
      );
    });

    test('ssh defaults to the pinned known_hosts file in the project', () {
      final DVInfraManifest m = production();
      expect(m.ssh.knownHosts, 'infra/known_hosts');
      expect(m.ssh.port, 22);
      expect(m.ssh.user, 'root');
    });
  });

  group('the cron line becomes a timer that fires when cron would', () {
    test('daily at a fixed time', () {
      expect(dvCronToOnCalendar('0 3 * * *'), '*-*-* 03:00:00');
    });

    test('lists, ranges and steps', () {
      expect(dvCronToOnCalendar('15,45 */6 * * *'), '*-*-* 00/6:15,45:00');
      expect(dvCronToOnCalendar('0 2 1 * *'), '*-*-01 02:00:00');
      expect(dvCronToOnCalendar('30 4 * * 1-5'), 'Mon..Fri *-*-* 04:30:00');
    });

    test('Sunday is both 0 and 7, and neither becomes Monday', () {
      expect(dvCronToOnCalendar('0 3 * * 0'), 'Sun *-*-* 03:00:00');
      expect(dvCronToOnCalendar('0 3 * * 7'), 'Sun *-*-* 03:00:00');
    });

    test('day-of-month with day-of-week is refused: cron ORs them and '
        'systemd ANDs them', () {
      expect(() => dvCronToOnCalendar('0 3 1 * 1'), throwsFormatException);
    });

    test('nonsense is refused', () {
      for (final String line in <String>[
        '0 3 * *',
        '61 3 * * *',
        '0 24 * * *',
        '@daily',
        '0 3 * * mon',
      ]) {
        expect(() => dvCronToOnCalendar(line), throwsFormatException,
            reason: line);
      }
    });
  });

  group('the desired state', () {
    test('services are supervised units that come back after a reboot', () {
      final DVInfraDesiredState state = desired(production());
      final List<DVInfraResource> services = state.resources
          .where(
            (DVInfraResource r) =>
                r.kind == DVInfraResourceKind.unit && r.id.endsWith('.service'),
          )
          .toList();
      expect(
        services.map((DVInfraResource r) => r.id),
        containsAll(<String>[
          'shop-backend-1.service',
          'shop-backend-2.service',
          'shop-worker-default-1.service',
          'shop-worker-default-2.service',
          'shop-worker-mail-1.service',
          'shop-worker-mail-2.service',
          'shop-cron.service',
        ]),
      );
      for (final DVInfraResource unit in services) {
        if (unit.id == 'shop-backup.service') continue;
        if (unit.content == null) {
          // A unit its package ships (caddy, nftables): not written here,
          // but still enabled so it comes back at boot.
          expect(unit.enabled, isTrue, reason: unit.id);
          continue;
        }
        expect(unit.content, contains('Restart=always'), reason: unit.id);
        expect(unit.content, contains('WantedBy=multi-user.target'),
            reason: unit.id);
        expect(unit.enabled, isTrue, reason: unit.id);
      }
    });

    test('each backend instance gets its own port, and the proxy knows all',
        () {
      final DVInfraDesiredState state = desired(production());
      final String one = state.byId('shop-backend-1.service')!.content!;
      final String two = state.byId('shop-backend-2.service')!.content!;
      expect(one, contains('DARTVEL_PORT=8080'));
      expect(two, contains('DARTVEL_PORT=8081'));
      final String caddy = state.byId('/etc/caddy/Caddyfile')!.content!;
      expect(caddy, contains('api.example.com'));
      expect(caddy, contains('127.0.0.1:8080'));
      expect(caddy, contains('127.0.0.1:8081'));
      expect(caddy, contains('email ops@example.com'));
    });

    test('the firewall drops by default and opens only ssh, http and https',
        () {
      final DVInfraDesiredState state = desired(production());
      final DVInfraResource fw = state.resources.singleWhere(
        (DVInfraResource r) => r.kind == DVInfraResourceKind.firewall,
      );
      expect(fw.content, contains('policy drop'));
      expect(fw.firewall!.policy, 'drop');
      expect(fw.firewall!.tcpPorts, <int>{22, 80, 443});
      expect(fw.firewall!.udpPorts, isEmpty);
    });

    test('the firewall never closes the port the provisioner connects on',
        () {
      final DVInfraManifest m = production(
        edited(
          (Map<Object?, Object?> e) =>
              e['ssh'] = <Object?, Object?>{'port': 2222},
        ),
      );
      final DVInfraResource fw = desired(m).resources.singleWhere(
        (DVInfraResource r) => r.kind == DVInfraResourceKind.firewall,
      );
      expect(fw.firewall!.tcpPorts, contains(2222));
      expect(fw.firewall!.tcpPorts, isNot(contains(22)));
    });

    test('backend ports are not opened: the proxy is the way in', () {
      final DVInfraResource fw = desired(production()).resources.singleWhere(
        (DVInfraResource r) => r.kind == DVInfraResourceKind.firewall,
      );
      expect(fw.firewall!.tcpPorts, isNot(contains(8080)));
    });

    test('secrets are delivered as encrypted credentials, by name only', () {
      final DVInfraDesiredState state = desired(production());
      final List<DVInfraResource> creds = state.resources
          .where((DVInfraResource r) => r.kind == DVInfraResourceKind.credential)
          .toList();
      expect(
        creds.map((DVInfraResource r) => r.id),
        unorderedEquals(<String>['DATABASE_URL', 'PAYSTACK_SECRET']),
      );
      for (final DVInfraResource c in creds) {
        expect(c.content, isNull);
      }
      final String backend = state.byId('shop-backend-1.service')!.content!;
      expect(
        backend,
        contains(
          'LoadCredentialEncrypted=PAYSTACK_SECRET:'
          '/etc/credstore.encrypted/shop.PAYSTACK_SECRET',
        ),
      );
      // Never an EnvironmentFile: that is a plaintext secret on disk.
      expect(backend, isNot(contains('EnvironmentFile')));
    });

    test('a backup is a timer with the declared schedule and retention', () {
      final DVInfraDesiredState state = desired(production());
      final String timer = state.byId('shop-backup.timer')!.content!;
      expect(timer, contains('OnCalendar=*-*-* 03:00:00'));
      expect(timer, contains('Persistent=true'));
      final String script =
          state.byId('/usr/local/lib/dartvel/shop/backup.sh')!.content!;
      expect(script, contains('pg_dump'));
      expect(script, contains('-mtime +30'));
      final String service = state.byId('shop-backup.service')!.content!;
      // The connection string carries a password and pg_dump takes it as an
      // argument; other users must not be able to read the process list.
      expect(service, contains('ProtectProc=invisible'));
      expect(service, contains('LoadCredentialEncrypted=DATABASE_URL:'));
    });

    test('a backup with no DATABASE_URL secret is refused, not skipped', () {
      final DVInfraDesiredState state = desired(
        production(),
        secrets: const <String>{'PAYSTACK_SECRET'},
      );
      expect(state.unsupported, anyElement(contains('DATABASE_URL')));
      expect(state.byId('shop-backup.timer'), isNull);
    });

    test('what the generated backend cannot do is refused, not installed',
        () {
      final DVInfraDesiredState state = desired(
        production(),
        capabilities: beforeRoles,
      );
      // Two instances bind the same generated port; workers and a separate
      // cron have no entry point; and logs have nowhere to ship to.
      expect(state.unsupported, anyElement(contains('instances')));
      expect(state.unsupported, anyElement(contains('workers')));
      expect(state.unsupported, anyElement(contains('logs.ship')));
      expect(
        state.resources.map((DVInfraResource r) => r.id),
        isNot(contains('shop-worker-default-1.service')),
      );
    });

    test('with one instance and no cron role, schedules tick in the backend',
        () {
      final DVInfraManifest m = production(
        edited((Map<Object?, Object?> e) {
          final Map<Object?, Object?> services =
              e['services']! as Map<Object?, Object?>;
          services['backend'] = <Object?, Object?>{'instances': 1};
          services.remove('workers');
          e.remove('logs');
        }),
      );
      final DVInfraDesiredState state = desired(
        m,
        capabilities: beforeRoles,
      );
      expect(state.unsupported, isEmpty);
      expect(state.byId('shop-cron.service'), isNull);
      expect(state.notes, anyElement(contains('shop-backend-1.service')));
      // The generated backend binds its generated port and reads none from
      // the environment, so the unit must not pretend to set one.
      expect(
        state.byId('shop-backend-1.service')!.content,
        isNot(contains('DARTVEL_PORT')),
      );
    });

    test('only the ssh adapter is built', () {
      final DVInfraDesiredState state = desired(
        production(
          edited((Map<Object?, Object?> e) => e['adapter'] = 'container'),
        ),
      );
      expect(state.unsupported, anyElement(contains('container')));
    });

    test('the same manifest produces the same resources', () {
      final List<String> a = desired(production())
          .resources
          .map((DVInfraResource r) => '${r.id}:${r.content}')
          .toList();
      final List<String> b = desired(production())
          .resources
          .map((DVInfraResource r) => '${r.id}:${r.content}')
          .toList();
      expect(a, b);
    });
  });

  group('process roles', () {
    // Asserted through the runtime's own reading of each unit's environment,
    // so a unit that spells a role or a port the backend does not honour
    // fails here rather than crash looping on a host.
    Map<String, String> unitEnvironment(DVInfraResource unit) =>
        <String, String>{
          for (final String line in unit.content!.split('\n'))
            if (line.startsWith('Environment='))
              line
                  .substring('Environment='.length)
                  .split('=')
                  .first: line.substring('Environment='.length).split('=').skip(1).join('='),
        };

    Map<String, DVProcessConfiguration> processes(DVInfraDesiredState state) =>
        <String, DVProcessConfiguration>{
          for (final DVInfraResource r in state.resources)
            if (r.kind == DVInfraResourceKind.unit &&
                r.requiresRelease &&
                r.content != null)
              r.id: DVProcessConfiguration.resolve(
                environment: unitEnvironment(r),
                generatedPort: 8080,
              ),
        };

    DVInfraManifest services(Map<Object?, Object?> declared) => production(
          edited((Map<Object?, Object?> e) {
            e['services'] = declared;
            e.remove('logs');
          }),
        );

    List<String> upstreams(DVInfraDesiredState state) {
      final String caddy = state.byId('/etc/caddy/Caddyfile')!.content!;
      final List<String> lines = caddy
          .split('\n')
          .map((String l) => l.trim())
          .where((String l) => l.startsWith('reverse_proxy '))
          .toList();
      // One directive: two reverse_proxy lines in one site do not balance,
      // the first matching one takes every request.
      expect(lines, hasLength(1), reason: caddy);
      return lines.single
          .substring('reverse_proxy '.length)
          .replaceAll('{', '')
          .trim()
          .split(RegExp(r'\s+'));
    }

    test('the specification example provisions with the default backend',
        () {
      final DVInfraDesiredState state = dvInfraDesiredState(
        production(edited((Map<Object?, Object?> e) => e.remove('logs'))),
        appName: 'shop',
        backendPort: 8080,
        secretNames: const <String>{'DATABASE_URL', 'PAYSTACK_SECRET'},
      );
      expect(state.unsupported, isEmpty);
      expect(
        processes(state).keys,
        unorderedEquals(<String>[
          'shop-backend-1.service',
          'shop-backend-2.service',
          'shop-worker-default-1.service',
          'shop-worker-default-2.service',
          'shop-worker-mail-1.service',
          'shop-worker-mail-2.service',
          'shop-cron.service',
        ]),
      );
    });

    test('with a cron unit, it and only it ticks the schedules', () {
      final Map<String, DVProcessConfiguration> all =
          processes(desired(production()));
      expect(
        all.entries
            .where((MapEntry<String, DVProcessConfiguration> e) =>
                e.value.ticksSchedules)
            .map((MapEntry<String, DVProcessConfiguration> e) => e.key),
        <String>['shop-cron.service'],
      );
    });

    test('web instances bind distinct ports, and the proxy balances across '
        'exactly those', () {
      final DVInfraDesiredState state = desired(
        services(<Object?, Object?>{
          'backend': <Object?, Object?>{'instances': 3},
          'cron': <Object?, Object?>{'enabled': true},
        }),
      );
      final List<int> bound = <int>[
        for (final DVProcessConfiguration c in processes(state).values)
          if (c.servesHttp) c.port,
      ];
      expect(bound.toSet(), hasLength(3));
      expect(
        upstreams(state).toSet(),
        bound.map((int port) => '127.0.0.1:$port').toSet(),
      );
      final String caddy = state.byId('/etc/caddy/Caddyfile')!.content!;
      // Named rather than left to a default: `first` sends every request to
      // one instance while the others idle, and passive health is what takes
      // a stopped instance out of rotation.
      expect(caddy, contains('lb_policy round_robin'));
      expect(caddy, contains('fail_duration'));
    });

    test('workers work their queue, serve nothing and tick nothing', () {
      final Map<String, DVProcessConfiguration> all =
          processes(desired(production()));
      for (final String queue in <String>['default', 'mail']) {
        for (int i = 1; i <= 2; i++) {
          final DVProcessConfiguration worker =
              all['shop-worker-$queue-$i.service']!;
          expect(worker.role, DVProcessRole.worker);
          expect(worker.queues, <String>[queue]);
          expect(worker.servesHttp, isFalse);
          expect(worker.ticksSchedules, isFalse);
        }
      }
    });

    test('with cron unstated, one web instance ticks and the rest do not', () {
      final DVInfraDesiredState state = desired(
        services(<Object?, Object?>{
          'backend': <Object?, Object?>{'instances': 2},
        }),
      );
      expect(state.unsupported, isEmpty);
      expect(state.byId('shop-cron.service'), isNull);
      final Map<String, DVProcessConfiguration> all = processes(state);
      expect(all['shop-backend-1.service']!.ticksSchedules, isTrue);
      expect(all['shop-backend-2.service']!.ticksSchedules, isFalse);
      expect(all.values.where((DVProcessConfiguration c) => c.servesHttp),
          hasLength(2));
    });

    test('with cron enabled false, nothing ticks the schedules, and it says '
        'so', () {
      final DVInfraDesiredState state = desired(
        services(<Object?, Object?>{
          'backend': <Object?, Object?>{'instances': 2},
          'cron': <Object?, Object?>{'enabled': false},
        }),
      );
      expect(state.unsupported, isEmpty);
      expect(state.byId('shop-cron.service'), isNull);
      expect(
        processes(state).values.where(
              (DVProcessConfiguration c) => c.ticksSchedules,
            ),
        isEmpty,
      );
      expect(state.notes, anyElement(contains('cron.enabled: false')));
    });

    test('with one instance and no cron stated, the one process ticks', () {
      final DVInfraDesiredState state = desired(
        services(<Object?, Object?>{
          'backend': <Object?, Object?>{'instances': 1},
        }),
      );
      final Map<String, DVProcessConfiguration> all = processes(state);
      expect(all.keys, <String>['shop-backend-1.service']);
      expect(all.values.single.ticksSchedules, isTrue);
      expect(all.values.single.port, 8080);
    });

    test('without a proxy every instance port is opened', () {
      final DVInfraDesiredState state = desired(
        production(
          edited((Map<Object?, Object?> e) {
            e.remove('proxy');
            e.remove('tls');
            e.remove('logs');
          }),
        ),
      );
      final DVInfraResource fw = state.resources.singleWhere(
        (DVInfraResource r) => r.kind == DVInfraResourceKind.firewall,
      );
      expect(fw.firewall!.tcpPorts, containsAll(<int>[8080, 8081]));
    });
  });
}
