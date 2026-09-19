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
                'executable with your backend, the native server, the web app '
                'and the admin dashboard inside it.'),
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
              'With dartvel.admin.enabled on, the binary serves the admin at '
                  '/__studio. dartvel.admin.path moves it.',
            ]),
            DocsText('Nobody can open the admin until you grant access. Being '
                'signed in is not enough, because every customer who signs up '
                'is signed in. Grant access to your own account, by the user '
                'id you sign in as, in the database the binary uses:'),
            DocsShell(<String>[
              r'$ dartvel admin grant <user-id> --database /srv/shop/dartvel_data/data.db',
              r'$ dartvel admin list --database /srv/shop/dartvel_data/data.db',
              r'$ dartvel admin revoke <user-id> --database /srv/shop/dartvel_data/data.db',
            ]),
            Bullets(<String>[
              'With DATABASE_URL set, leave out --database. Add --tenant when '
                  'the account signs in on a tenant other than default.',
              'Anyone without a grant gets the same answer as a page that does '
                  'not exist.',
              'If your app already knows who its operators are, register your '
                  'own rule instead: DV.Auth.authorization.registerAction('
                  '\'Studio.access\', (caller, _) => ...). It replaces the '
                  'grants.',
              'A --profile development build serves the admin to anyone who '
                  'can reach it, for local work. Never deploy one.',
            ]),
            DocsNote('Build it on the kind of machine it runs on',
                'build/server runs on the operating system and CPU it was '
                'built on. CI builds and runs it on Linux x64 and arm64, '
                'macOS arm64 and x64, and Windows x64 and arm64, where the '
                'file is build/server.exe. To deploy to a Linux arm64 server, '
                'build on Linux arm64.'),
            DocsNote('macOS signing',
                'The macOS binary has only the ad-hoc signature the Dart '
                'compiler gives it. CI runs a copy of it on the Mac that built '
                'it. A copy downloaded through a browser has not been tested.'),
          ],
        ),
        DocsSection(
          id: 'rendering',
          title: 'Serve each page with its data and head tags',
          children: <Widget>[
            Bullets(<String>[
              'The server resolves the route, loads the page\'s data and writes '
                  'the title, description, image, canonical link and JSON-LD '
                  'before the app starts, so crawlers and link previews see '
                  'the real page.',
              'A hidden or unpublished record answers 404, and one the visitor '
                  'may not see answers 401, without its data.',
              'Page data can be awaited, cached for a while, served stale and '
                  'refreshed, or left to the app. With a shared cache such as '
                  'Redis, every instance serves what one of them resolved.',
            ]),
            DocsStatus('Web Server Rendering', missing: <String>[
              'Widgets are not rendered to HTML. Crawlers get the head tags '
                  'and text written from the page\'s data.',
            ]),
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
              'dartvel deploy --target web --provider firebase-hosting',
              'dartvel deploy --target server --environment staging',
              'dartvel deploy --functions --function-target cloud-run',
            ]),
            DocsTable(columns: <String>[
              '--provider',
              'Runs',
            ], rows: <List<String>>[
              <String>['firebase-hosting', 'firebase deploy, from the firebase CLI'],
              <String>['vercel', 'vercel --prod'],
              <String>['netlify', 'netlify deploy --prod --dir=build/web'],
              <String>['cloudflare', 'wrangler pages publish build/web'],
              <String>['custom', 'Nothing. It builds, and you ship build/ yourself'],
            ]),
            Bullets(<String>[
              '--target is web, server or all. server builds web-server first.',
              'It builds first, unless you pass --no-build.',
              'Secrets the environment requires must resolve before anything '
                  'ships.',
              '--functions writes a deployment artifact per backend function '
                  'into build/deploy: lambda, cloud-run, container, edge, fly, '
                  'railway or bare-metal.',
            ]),
            DocsText('Uploads to Google Play, the App Store, TestFlight and '
                'Firebase App Distribution use dartvel deploy --store. See App '
                'stores.'),
            DocsStatus('Deployment', missing: <String>[
              'dartvel deploy calls each host\'s own CLI. It holds no cloud '
                  'credentials itself.',
              'There is no plan or rollback step for dartvel deploy yet.',
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
