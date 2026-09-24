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
                'mail, scheduling, auth, policies, an admin. Dartvel is that '
                'decision applied to Flutter. Because both ends are Dart, the '
                'client that calls your backend is generated from the '
                'backend instead of written twice.'),
            CodeBlock(<String>[
              '@DVModel()',
              'class _Invoice {',
              '  final String number;',
              '  final double total;',
              '  final DateTime issuedAt;',
              '  final DateTime? paidAt;',
              '',
              '  const _Invoice({',
              '    required this.number,',
              '    required this.total,',
              '    required this.issuedAt,',
              '    this.paidAt,',
              '  });',
              '}',
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
                <String>['Data models', 'Eloquent', '@DVModel, offline-first and realtime by default'],
                <String>['Migrations', 'php artisan migrate', 'Generated from the model, run on start'],
                <String>['CLI', 'artisan', 'dartvel'],
                <String>['Queues and jobs', 'Queue, Horizon', 'DV.Jobs, DV.Queues, @DVJob'],
                <String>['Scheduling', 'Task scheduling', '@DVSchedule'],
                <String>['Mail', 'Mail, Mailable', 'DV.Notifications.mail'],
                <String>['Auth', 'Breeze, Fortify, Sanctum', 'Sessions, passkeys, SAML, LDAP, second factors'],
                <String>['Policies', 'Gate, Policy', 'DV.Auth.authorization; a policy nobody registered answers no'],
                <String>['Admin', 'Nova, Filament', 'Studio, in your own binary, free'],
                <String>['Views', 'Blade', 'Flutter pages: the same code on the web and on a phone'],
                <String>['Deployment', 'Forge, Vapor', 'One file from dartvel build web-server'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('ONE LANGUAGE'),
            Heading('The API client is generated, and nobody maintains it.'),
            Body('A Laravel API and a Flutter app are two repositories, two '
                'languages and a hand-written client between them. Renaming a '
                'field is a deploy, a release and a week of both being true. '
                'Here the function and the call to it are compiled together.'),
            CodeBlock(<String>[
              '@DVBackendFunction()',
              'Future<List<Invoice>> _unpaid(DVContext context) async => <Invoice>[',
              '      for (final Invoice i in await Invoice.all())',
              '        if (i.paidAt == null) i,',
              '    ];',
              '',
              '// in a page: typed, generated, no route string',
              'final List<Invoice> owing = await unpaid();',
            ]),
            Bullets(<String>[
              'Pages are files: lib/pages/invoices/[id].dart is '
                  '/invoices/:id, and moving the file breaks every link to it '
                  'at compile time.',
              'The same page renders on the web, Android, iOS, desktop and a '
                  'TV.',
              'The backend is not tied to SQL: there is a records layer under '
                  'the adapters, and MongoDB is the next one.',
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
              'Forge, Vapor and Cloud are running services you can pay for '
                  'this afternoon. Dartvel Cloud is not open yet.',
              'If your product is a website with forms, Blade and Livewire '
                  'are less machinery than shipping a Flutter application.',
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
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/laravel')]),
        SiteFooter(),
      ], spacing: 0),
    );
