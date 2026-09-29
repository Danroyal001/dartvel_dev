import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Laravel for Flutter',
  description: 'Laravel for Flutter: data models, migrations, queues, mail, '
      'auth, policies and an admin panel, with the Flutter app that uses them '
      'in the same language and the same repository.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.9,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsLaravelPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          grain: true,
          children: <Widget>[
            Eyebrow('LARAVEL FOR FLUTTER'),
            Heading(
              'Laravel for Flutter, with the app in the same repository.',
              level: 1,
            ),
            Body('Laravel decided that a web framework should come with the '
                'boring parts already written: an ORM, migrations, queues, '
                'mail, scheduling, auth, policies and realtime broadcasting. '
                'Dartvel is that decision applied to Flutter. Because both '
                'ends are Dart, the client that calls your backend is '
                'generated from the backend instead of written twice.'),
            CodeBlock(<String>[
              '@DVModel()',
              'class const _Invoice({',
              '  required final String number,',
              '  required final double total,',
              '  required final DateTime issuedAt,',
              '  final DateTime? paidAt,',
              '});',
              '',
              '// generated: the table, the typed client, the form,',
              '// the admin screen and the migration',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('THE SAME IDEAS'),
            Heading('What you reach for in Laravel, and what it is here.'),
            DocsTable(
              columns: <String>['', 'Laravel', 'Dartvel'],
              rows: <List<String>>[
                <String>['Data models', 'Eloquent', '@DVModel: table, typed client, form, admin and a public page per record from one class'],
                <String>['Migrations', 'php artisan make:migration, written by hand, then migrate', 'Generated from the model. SQLite is migrated on start; PostgreSQL and MySQL with dartvel db migrate'],
                <String>['CLI', 'artisan', 'dartvel'],
                <String>['Queues and jobs', 'Queues with delays, retries, backoff, unique jobs and batches; Horizon', 'DV.Jobs, DV.Queues, @DVJob: priorities, retries and dead letters on seven adapters. No delayed jobs, growing backoff or unique jobs yet'],
                <String>['Scheduling', 'Task scheduling', '@DVBackendCron on the server, @DVClientCron in the app'],
                <String>['Mail', 'Mail, Mailable', 'DV.Notifications.mail'],
                <String>['Realtime', 'Event broadcasting over Reverb, its WebSocket server', 'Model change streams inside one process. Delivery to devices is not built yet'],
                <String>['Auth', 'Starter kits, Fortify with two-factor and passkeys, Sanctum, Passport; WorkOS AuthKit for SSO', 'Sessions, passkeys, OAuth sign-in, SAML, LDAP, second factors, API keys, and an OAuth 2.1 provider for your own API'],
                <String>['Policies', 'Gates and policies', 'DV.Auth.authorization, in Dart'],
                <String>['Admin', 'Nova (paid) or Filament', 'Studio, in your own binary, free'],
                <String>['Views and forms', 'Blade, Livewire, or Inertia with React, Vue or Svelte; forms written in the view', 'Flutter pages: the same code on the web and on a phone. Invoice.Form() creates a record and invoice.Form() edits one, generated from the model'],
                <String>['Deployment', 'Forge, Vapor, Laravel Cloud', 'One file from `dartvel build web-server`'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('ONE LANGUAGE'),
            Heading('The API client is generated, and nobody maintains it.'),
            Body('A Laravel API and a Flutter app are two codebases in two '
                'languages, with an API client between them that somebody '
                'writes by hand or generates from an OpenAPI description they '
                'keep up to date. Renaming a field is a deploy, a release and '
                'a week of both being true. Here the function and the call to '
                'it are compiled together.'),
            CodeBlock(<String>[
              '@DVBackendFunction()',
              'Future<int> _priceWithVat(int cents, String country) async =>',
              '    cents + cents * vatPercent(country) ~/ 100;',
              '',
              '// in a page: typed, generated, no route string',
              "final int total = await priceWithVat(cents: 1999, country: 'NG');",
            ]),
            Bullets(<String>[
              'Pages are files: lib/pages/invoices/[id].dart is '
                  '/invoices/:id, and moving the file breaks every link to it '
                  'at compile time.',
              'The same page renders on the web, Android, iOS, desktop and a '
                  'TV.',
              'A backend function cannot use the generated data models yet: '
                  'they import Flutter, and the server is pure Dart. The app '
                  'reads and writes them, and Studio and the data API serve '
                  'them.',
              'Data models run on SQLite, Postgres and MySQL today. A '
                  'storage-neutral records layer is under way, and MongoDB is '
                  'planned. Laravel reaches MongoDB today through the '
                  'mongodb/laravel-mongodb package, which MongoDB maintains.',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where Laravel is ahead today.'),
            Bullets(<String>[
              'Laravel is fifteen years old, with a package for everything '
                  'and a book for everything else.',
              'Forge, Vapor and Laravel Cloud are running services you can '
                  'pay for this afternoon. Dartvel Cloud is not open yet.',
              "Laravel's queues delay jobs, grow the wait between retries "
                  'and deduplicate jobs, and Reverb broadcasts events to '
                  "browsers and apps today. Dartvel's queues do none of those "
                  'three yet, and its model changes do not leave the process '
                  'they happen in.',
              'Forms are not the difference: every data model here has one, '
                  'with a typed builder when you want your own layout. What '
                  'the browser downloads is. A Blade page is HTML from the '
                  'server. A Dartvel page is its text in HTML, then a Flutter '
                  'app that has to arrive before the page is interactive: '
                  'about 4 MB on this site, most of it the compiled app and '
                  'the renderer. For a '
                  'site that has to be light on a slow phone, Blade and '
                  'Livewire send less.',
            ]),
            VersusFair('Dartvel is not trying to replace Laravel on the web. '
                'It is answering the question people ask when they have a '
                'Flutter app and want the batteries Laravel gave them, '
                'without running a second stack in a second language to get '
                'them.'),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Start an app', '/docs'),
              GhostLink('Data models', '/docs/models'),
              GhostLink('Backend functions', '/docs/backend-functions'),
            ], spacing: 12),
            VersusChecked('Laravel', 'https://laravel.com/docs/13.x',
                '2026-09-25'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/laravel')]),
        SiteFooter(),
      ], spacing: 0),
    );
