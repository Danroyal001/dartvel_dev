import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel vs PocketBase',
  description: 'Dartvel vs PocketBase: both are one file with SQLite beside '
      'it and an admin built in. Dartvel puts your app inside the same '
      'binary, and builds it for phones, desktops and TVs as well.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsPocketbasePage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          glow: true,
          children: <Widget>[
            Eyebrow('DARTVEL VS POCKETBASE'),
            Heading(
              'One binary, SQLite beside it, an admin built in, and your '
              'app inside it.',
              level: 1,
            ),
            Body('PocketBase is the nicest answer in its category: download '
                'one file, run it, and you have a database, an admin panel, '
                'auth, file storage and realtime. Dartvel arrives at the same '
                'place from the other direction: dartvel build web-server '
                'produces one executable that creates its SQLite database '
                'beside itself on first run. The difference is that your '
                'application is in that file too, instead of a separate '
                'frontend talking to it.'),
            CodeBlock(<String>[
              'dartvel build web-server',
              'scp build/server user@host:/srv/app',
              'ssh user@host /srv/app/server',
              '# the site, the API and Studio, on one port',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('SIDE BY SIDE'),
            Heading('What is in the box.'),
            DocsTable(
              columns: <String>['', 'PocketBase', 'Dartvel'],
              rows: <List<String>>[
                <String>['Deployment', 'One Go binary', 'One binary from dartvel build web-server'],
                <String>['Database', 'SQLite, embedded', 'SQLite beside the binary; Postgres and MySQL adapters'],
                <String>['Admin', 'Built in', 'Studio, built in, and it edits your pages too'],
                <String>['Auth', 'Built in, with OAuth providers', 'Sessions, passkeys, SAML, LDAP, second factors, OAuth'],
                <String>['Realtime', 'Subscriptions over SSE', 'On by default on models. Turn it off at the model'],
                <String>['Offline', 'Your problem', 'On by default. Writes sync when the network returns'],
                <String>['Custom logic', 'Go hooks, or JavaScript', '@DVBackendFunction, in Dart, in the same repository'],
                <String>['The client app', 'A JS SDK you wire up yourself', 'Generated and typed, and it is the same project'],
                <String>['Other targets', 'None. It is a backend', 'Android, iOS, desktop, TVs, browser extensions'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('THE DIFFERENCE'),
            Heading('PocketBase is a backend. Dartvel is the application.'),
            Body('With PocketBase you still choose a frontend framework, wire '
                'up the SDK, write the screens, and ship that separately. '
                'That is a real choice and sometimes the right one. In '
                'Dartvel the page and the function it calls are compiled '
                'together, so a renamed field is a build failure instead of a '
                'support ticket, and the same page renders on the web and '
                'on a phone.'),
            Bullets(<String>[
              'Studio covers more than records: it has a page builder, a frontend '
                  'function builder, a backend function builder and a Deploy '
                  'menu that lists every target with its status.',
              'The page builder writes to the same running binary, so a page '
                  'edited there is served immediately.',
              'Deploy to phones only and the website keeps its compiled page.',
            ]),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('See Studio', '/studio'),
              GhostLink('The web-server binary', '/docs/web-hosting'),
            ], spacing: 12),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where PocketBase is ahead today.'),
            Bullets(<String>[
              'It is a smaller, older, more finished thing. Download, run, '
                  'done, with no build step at all.',
              'Its admin has been used in anger by far more people than '
                  'Studio has.',
              'If you want a backend for a React or Svelte app you already '
                  'have, PocketBase is the answer and Dartvel is not.',
            ]),
            VersusFair('PocketBase is excellent and the overlap is real: one '
                'file, SQLite, an admin, realtime. The honest split is that '
                'PocketBase serves an app you build elsewhere, and Dartvel '
                'builds the app.'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/pocketbase')]),
        SiteFooter(),
      ], spacing: 0),
    );
