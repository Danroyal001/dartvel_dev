import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Ruby on Rails for Flutter',
  description: 'Ruby on Rails for Flutter: convention over configuration for '
      'a Flutter app. Pages are files, models generate their own client, '
      'forms and admin, and one command builds and deploys.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.9,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsRailsPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          glow: true,
          children: <Widget>[
            Eyebrow('RUBY ON RAILS FOR FLUTTER'),
            Heading(
              'Rails conventions, for an app that also runs on a phone.',
              level: 1,
            ),
            Body("Rails' bet was that most of the decisions in a web "
                'application are not worth making twice, so the framework '
                'makes them and you write the part that is yours. Dartvel '
                'takes the same bet for Flutter: where the file lives is the '
                'route, the model is the schema and the client and the form '
                'and the admin screen, and one command runs the generators.'),
            CodeBlock(<String>[
              'lib/pages/index.dart            ->  /',
              'lib/pages/articles/index.dart   ->  /articles',
              'lib/pages/articles/[slug].dart  ->  /articles/:slug',
              '',
              'dartvel dev     # generate, serve, hot reload, QR code',
              'dartvel build web-server   # one file to deploy',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('THE SAME IDEAS'),
            Heading('What you reach for in Rails, and what it is here.'),
            DocsTable(
              columns: <String>['', 'Rails', 'Dartvel'],
              rows: <List<String>>[
                <String>['Routing', 'config/routes.rb', 'The file path. Moving a page breaks every link to it'],
                <String>['Data models', 'Active Record', '@DVModel: schema, client, form and admin from one class'],
                <String>['Migrations', 'rails db:migrate', 'Generated from the model'],
                <String>['Generators', 'rails generate', 'dartvel dev regenerates on save'],
                <String>['Background jobs', 'Active Job, Sidekiq', 'DV.Jobs, DV.Queues, @DVJob'],
                <String>['Mail', 'Action Mailer', 'DV.Notifications.mail'],
                <String>['Auth', 'Devise', 'Sessions, passkeys, SAML, LDAP, second factors'],
                <String>['Admin', 'ActiveAdmin, Avo', 'Studio, in your own binary, free'],
                <String>['Views', 'ERB, Hotwire', 'Flutter pages: web, phone, desktop and TV'],
                <String>['Strong parameters', 'Controller filters', 'Typed function arguments, checked by the compiler'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('CONVENTION'),
            Heading('One class, and the boring files are already written.'),
            Body('A model declares fields. From that come the table, the '
                'typed client, a form with validation and error messages, a '
                'table widget, an admin screen and, if you ask for them, '
                'public pages with their own sitemap entries.'),
            CodeBlock(<String>[
              '@DVModel(generatePublicPages: true)',
              'class _Article {',
              '  final String slug;',
              '',
              '  @DVModel.pageTitle()',
              '  final String title;',
              '',
              '  @DVModel.mainContent()',
              '  final String body;',
              '',
              '  const _Article({',
              '    required this.slug,',
              '    required this.title,',
              '    required this.body,',
              '  });',
              '}',
            ]),
            Bullets(<String>[
              'The generated page is Article.Page(...), with .async, .signal '
                  'and .fromId variants.',
              'Records are offline-first and realtime by default, so a list '
                  'updates itself and survives a tunnel.',
              'Forms come from the fields: DVForm<Article> is the inputs, the '
                  'validation and the messages.',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where Rails is ahead today.'),
            Bullets(<String>[
              'Twenty years of gems, and a hiring pool to match.',
              'For a server-rendered website, ERB and Hotwire are far less '
                  'machinery than compiling a Flutter application.',
              'Rails runs on every host on earth. A Dartvel deployment is one '
                  'binary, which is simple but newer.',
              'Dartvel Cloud is not open yet; local builds and your own '
                  'server are free and work now.',
            ]),
            VersusFair('Rails is not a Flutter framework and does not claim '
                'to be. The comparison is here because "Rails for Flutter" is '
                'what people type when they mean: I want the conventions, the '
                'generators and the batteries, for the app I am actually '
                'building.'),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Start an app', '/docs'),
              GhostLink('Routing', '/docs/routing'),
              GhostLink('Forms', '/docs/forms'),
            ], spacing: 12),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/rails')]),
        SiteFooter(),
      ], spacing: 0),
    );
