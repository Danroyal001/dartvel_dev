import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Run and deploy a Dartvel backend', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsDeployingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsdeploying,
      lead: <String>[
        'Run the generated backend as a web server, a job worker or a cron '
            'process.',
        'Deploy it with dartvel deploy, or provision your own servers with '
            'dartvel infra.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'web-server',
          title: 'Build one file with dartvel build web-server',
          children: <Widget>[
            DocsText('dartvel build web-server writes build/server: one '
                'executable with your backend, the native server and the web '
                'app inside it.'),
            DocsShell(<String>[
              r'$ dartvel build web-server',
              r'$ scp build/server you@host:/srv/shop/',
              r'$ ssh you@host "cd /srv/shop && ./server"',
            ]),
            Bullets(<String>[
              'With no DATABASE_URL, the first run creates '
                  '/srv/shop/dartvel_data/data.db next to the binary, with your '
                  'models\' tables in it. Back up that one folder.',
              'DARTVEL_DATA_DIR moves dartvel_data somewhere else, such as a '
                  'mounted volume.',
              'Set DATABASE_URL to use PostgreSQL or MySQL. The binary does '
                  'not migrate those on start.',
            ]),
            DocsNote('Linux x64 only',
                'The server binary embeds a native library that ships for '
                'linux-x64, so build it for a Linux x64 host.'),
          ],
        ),
        DocsSection(
          id: 'roles',
          title: 'Run as web, worker or cron',
          children: <Widget>[
            DocsText('The generated backend reads its role and port from the '
                'environment.'),
            DocsTable(columns: <String>[
              'Variable',
              'Effect',
            ], rows: <List<String>>[
              <String>['DARTVEL_ROLE', 'web, worker or cron. With none, it '
                  'serves HTTP and runs schedules'],
              <String>['DARTVEL_PORT', 'The HTTP port. Defaults to '
                  'dartvel.backendPort'],
              <String>['DARTVEL_QUEUE', 'The queues a worker works, comma '
                  'separated'],
              <String>['DARTVEL_HEALTH_PORT', '/healthz for a worker or cron '
                  'process'],
              <String>['DATABASE_URL', 'The shared job queue and schedule '
                  'leases'],
            ]),
            DocsText('A value it cannot use, such as a port that is not a '
                'number, stops the process at startup.'),
          ],
        ),
        DocsSection(
          id: 'deploy',
          title: 'Deploy with dartvel deploy',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel deploy --target web --provider vercel',
              'dartvel deploy --environment staging',
              'dartvel deploy --functions --function-target cloud-run',
            ]),
            Bullets(<String>[
              'It builds first, unless you pass --no-build.',
              'Secrets required for the environment must resolve before '
                  'anything ships.',
              '--functions writes a deployment artifact per backend function, '
                  'such as a Dockerfile and fly.toml, into build/deploy.',
            ]),
            DocsStatus('Deployment', missing: <String>[
              'dartvel deploy calls each cloud\'s own CLI. It holds no cloud '
                  'credentials itself.',
            ]),
          ],
        ),
        DocsSection(
          id: 'infra',
          title: 'Provision servers with dartvel infra',
          children: <Widget>[
            DocsYaml('yaml-infra'),
            DocsShell(<String>[
              'dartvel infra plan production --out plan.json',
              'dartvel infra provision production --plan plan.json',
              'dartvel infra check production',
            ]),
            Bullets(<String>[
              'It connects over ssh and sets up Caddy, a firewall and a systemd '
                  'unit per backend instance, worker and cron process.',
              'An unknown key under dartvel.infra is refused.',
              'provision asks before it removes anything, unless you pass '
                  '--confirm-destructive.',
            ]),
            DocsStatus('Server Provisioning', missing: <String>[
              'It does not install the backend binary. Services stay stopped '
                  'until something puts the server on the host.',
              'Only the ssh adapter works, and it has not been run against a '
                  'real host.',
            ]),
          ],
        ),
      ],
    );
