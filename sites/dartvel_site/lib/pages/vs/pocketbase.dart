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
          grain: true,
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
                'place from the other direction: `dartvel build web-server` '
                'produces one executable that creates its SQLite database '
                'beside itself on first run. PocketBase can serve a built '
                'frontend from its pb_public folder, and that frontend is '
                'still a separate project talking to its API. In Dartvel the '
                'app and its backend are one project, compiled into one '
                'file.'),
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
                <String>['Deployment', 'One Go binary', 'One binary from `dartvel build web-server`'],
                <String>['Database', 'SQLite, embedded', 'SQLite beside the binary; Postgres and MySQL adapters'],
                <String>['Admin', 'Built in', 'Studio, built in, and it edits your pages too'],
                <String>['Auth', 'Built in: password, one-time codes, OAuth2 and MFA', 'Sessions, passkeys, SAML, LDAP, second factors, OAuth'],
                <String>['Realtime', 'Subscriptions over SSE, in both SDKs', 'Model change streams in one process. Delivery to devices is not built yet'],
                <String>['Offline', 'Left to the client', 'An offline store with a replay log. Saving through it is still a separate call'],
                <String>['Custom logic', 'Go hooks, or JavaScript', '@DVBackendFunction, in Dart, in the same repository'],
                <String>['The client app', 'Official JavaScript and Dart SDKs, in a project you build separately', 'Generated and typed, and it is the same project'],
                <String>['Other targets', 'None. It is a backend', 'Android, iOS, desktop, TVs, browser extensions'],
                <String>['Maturity', 'v0.40, before 1.0. Its docs do not yet recommend it for production critical apps', 'v0.6. Most spec sections are Partial, each with what is missing'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('THE DIFFERENCE'),
            Heading('PocketBase is a backend. Dartvel is the application.'),
            Body('With PocketBase you still choose a frontend framework, wire '
                'up its JavaScript or Dart SDK, write the screens, and ship '
                'that separately. '
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
              'It is smaller and more focused. Download, run, done, with no '
                  'build step at all.',
              'Its admin has been used in anger by far more people than '
                  'Studio has.',
              'Its realtime subscriptions reach browsers and phones today, '
                  "through the SDKs. Dartvel's model changes do not reach a "
                  'device yet.',
              'If you want a backend for a React, Svelte or Flutter app you '
                  'already have, PocketBase and its Dart SDK are the answer '
                  'and Dartvel is not.',
            ]),
            VersusFair('PocketBase is excellent and the overlap is real: one '
                'file, SQLite, an admin, realtime. The honest split is that '
                'PocketBase serves an app you build elsewhere, and Dartvel '
                'builds the app.'),
            VersusChecked('PocketBase', 'https://pocketbase.io/docs/',
                '2026-09-25'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/pocketbase')]),
        SiteFooter(),
      ], spacing: 0),
    );
