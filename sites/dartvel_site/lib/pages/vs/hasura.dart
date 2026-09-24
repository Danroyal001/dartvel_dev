import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Hasura for Flutter',
  description: 'Hasura for Flutter: a typed Dart client generated from your '
      'models instead of GraphQL strings, realtime without writing a '
      'subscription, and authorization that answers no by default.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.9,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsHasuraPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          grain: true,
          children: <Widget>[
            Eyebrow('HASURA FOR FLUTTER'),
            Heading(
              'Hasura for Flutter, without the query language in the middle.',
              level: 1,
            ),
            Body('Hasura gives you an instant API over a database, live '
                'queries and row-level permissions, and that is a genuinely '
                'good trade. What it hands your Flutter app is a GraphQL '
                'string: untyped until a code generator looks at it, and '
                'wrong at runtime instead of at compile time when the schema '
                'moves. Dartvel generates the client from the model instead, '
                'so there is no query language between your app and your '
                'data.'),
            CodeBlock(<String>[
              '// Hasura: a string, checked by a generator, if you run one',
              'query { articles(where: {published: {_eq: true}}) { id title } }',
              '',
              '// Dartvel: the model generates the client',
              'final List<Article> all = await Article.all();',
              'final Article? one = await Article.find(slug);',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('SIDE BY SIDE'),
            Heading('The same jobs, done differently.'),
            DocsTable(
              columns: <String>['', 'Hasura', 'Dartvel'],
              rows: <List<String>>[
                <String>['API', 'GraphQL, generated from the schema', 'A typed Dart client, generated from the model'],
                <String>['Type safety', 'A codegen step over your documents', 'The compiler. A renamed field fails the build'],
                <String>['Realtime', 'GraphQL subscriptions you write', 'On by default. Turn it off at the model'],
                <String>['Offline', 'Your problem', 'On by default. Writes sync when the network returns'],
                <String>['Permissions', 'Row and column rules in the console', 'DV.Auth.authorization in Dart, default deny'],
                <String>['Custom logic', 'Actions, calling a service you wrote', '@DVBackendFunction, in the same repository'],
                <String>['Database', 'Postgres, and its other connectors', 'SQLite, Postgres, MySQL, through a records layer'],
                <String>['The app', 'Not its job', 'Pages, forms, admin, and builds for every target'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('PERMISSIONS'),
            Heading('Rules in code, reviewed like code.'),
            Body("Hasura's permissions live in its metadata and are edited in "
                'a console. That is fast, and it puts the rule that decides '
                'who reads a row somewhere your pull request does not. A '
                'Dartvel policy is Dart: it is diffed, reviewed, tested, and '
                'it answers no for anything nobody registered.'),
            CodeBlock(<String>[
              'DV.Auth.authorization.register<DVAuthUser, Article>(',
              "    'Article.publish',",
              '    (DVAuthUser user, Article article) =>',
              '        article.authorId == user.id,',
              ');',
              '',
              '// a policy nobody registered answers no',
            ]),
            Bullets(<String>[
              'Sensitive fields are marked on the model and are kept out of '
                  'logs, traces, analytics, AI context, search and the admin '
                  'by default.',
              'The records layer under the adapters is not SQL strings, which '
                  'is what makes MongoDB the next adapter instead of a '
                  'rewrite.',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where Hasura is ahead today.'),
            Bullets(<String>[
              'Hasura points at a database you already have and gives you an '
                  'API in minutes, including one nobody wants to rewrite.',
              'GraphQL is a standard with a large ecosystem; a generated Dart '
                  'client is Dart only.',
              'Hasura Cloud is a running product. Dartvel Cloud is not open '
                  'yet.',
              'Federating several databases and services behind one graph is '
                  "Hasura's job and not Dartvel's.",
            ]),
            VersusFair('These are not the same kind of tool. Hasura is an API '
                'layer over data you already have; Dartvel is the whole '
                'application. The comparison is worth making because a '
                'Flutter team choosing Hasura is usually choosing it for the '
                'realtime, typed data access. That is a thing they can have '
                'without a query language.'),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Data models', '/docs/models'),
              GhostLink('Authorization', '/docs/authorization'),
              GhostLink('Sync and realtime', '/docs/sync'),
            ], spacing: 12),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/hasura')]),
        SiteFooter(),
      ], spacing: 0),
    );
