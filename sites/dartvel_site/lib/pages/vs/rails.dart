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
          grain: true,
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
                <String>['Migrations', 'Written by rails generate model, applied by rails db:migrate', 'Generated from the model class'],
                <String>['Generators', 'rails generate, including scaffold: model, migration, controller, views and forms', '`dartvel dev` regenerates on save'],
                <String>['Background jobs', 'Active Job on Solid Queue, the default since Rails 8', 'DV.Jobs, DV.Queues, @DVJob'],
                <String>['Mail', 'Action Mailer', 'DV.Notifications.mail'],
                <String>['Auth', 'bin/rails generate authentication, built in since Rails 8', 'Sessions, passkeys, SAML, LDAP, second factors'],
                <String>['Admin', 'None built in; ActiveAdmin or Avo', 'Studio, in your own binary, free'],
                <String>['Views', 'ERB and Hotwire', 'Flutter pages: web, phone, desktop and TV'],
                <String>['Strong parameters', 'params.expect and permit in the controller', 'Typed function arguments, checked by the compiler'],
                <String>['Deployment', 'Kamal, set up by rails new, to any server with Docker', 'One binary from `dartvel build web-server`'],
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
                'public pages with their own sitemap entries. rails generate '
                'scaffold writes much of the same once, as files you then '
                'own and edit; here they are regenerated from the class '
                'whenever it changes.'),
            CodeBlock(<String>[
              '@DVModel(generatePublicPages: true)',
              'class const _Article({',
              '  required final String slug,',
              '  @DVModel.pageTitle() required final String title,',
              '  @DVModel.mainContent() required final String body,',
              '});',
            ]),
            Bullets(<String>[
              'The generated page is Article.Page(...), with .async, .signal '
                  'and .fromId variants.',
              'Models publish change streams to watchers in the same '
                  'process. Carrying a change to another server or a phone '
                  'is not built yet.',
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
              'Over twenty years of gems, and a hiring pool to match.',
              'A new Rails 8 app comes with authentication, Solid Queue, '
                  'Solid Cache, Solid Cable and Kamal, so jobs, caching, '
                  'WebSockets and deployment need no extra service.',
              'For a server-rendered website, ERB and Hotwire are far less '
                  'machinery than compiling a Flutter application.',
              'Rails runs on every host on earth, and Kamal deploys it to '
                  'any server with Docker. A Dartvel deployment is one '
                  'binary, which is simple and newer.',
              'Rails reaches phones too, through Hotwire Native, which wraps '
                  'the web app in native iOS and Android shells.',
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
            VersusChecked('Rails', 'https://guides.rubyonrails.org/',
                '2026-09-25'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/rails')]),
        SiteFooter(),
      ], spacing: 0),
    );
