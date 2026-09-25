import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Hasura for Flutter',
  description: 'Hasura for Flutter: a typed Dart client generated from your '
      'data models, set beside the GraphQL API Hasura DDN generates over your '
      'data sources, with where each one fits.',
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
            Body('Hasura DDN generates a GraphQL API over the data sources you '
                'already have, with subscriptions, row and column permissions '
                'and custom logic in TypeScript, Python or Go, and that is a '
                'genuinely good trade. What it hands your Flutter app is a '
                'GraphQL document: typed once a code generator reads it '
                'against the schema, and a runtime error when the schema moves '
                'and nobody regenerated. Dartvel generates the client from the '
                'data model instead, so there is no query language between '
                'your app and your data.'),
            CodeBlock(<String>[
              '// Hasura: a GraphQL document, typed by a code generator',
              'query { articles(where: {published: {_eq: true}}) { id title } }',
              '',
              '// Dartvel: the data model generates the client',
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
              columns: <String>['', 'Hasura DDN', 'Dartvel'],
              rows: <List<String>>[
                <String>['API', 'GraphQL, generated from your data sources', 'A typed Dart client generated from the model, plus GraphQL and OpenAPI endpoints'],
                <String>['Type safety', 'A codegen step over your GraphQL documents', 'The compiler. A renamed field fails the build'],
                <String>['Realtime', 'GraphQL subscriptions, generated for each model, in beta', 'Model change streams, also served as GraphQL subscriptions over SSE. Models do not sync to devices on their own yet'],
                <String>['Offline', 'Left to the client', 'An offline store with a replay log. Saving through it is still a separate call'],
                <String>['Permissions', 'ModelPermissions in metadata files, in your repository', 'DV.Auth.authorization in Dart, default deny'],
                <String>['Custom logic', 'Lambda connectors in TypeScript, Python or Go', '@DVBackendFunction, in the same repository as the app'],
                <String>['Data sources', 'Postgres, MySQL, SQL Server, Oracle, MongoDB, ClickHouse, Snowflake, BigQuery and more', 'SQLite, Postgres, MySQL'],
                <String>['The app', 'Not its job', 'Pages, forms, admin, and builds for every target'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('PERMISSIONS'),
            Heading('Both keep the rules in the repository.'),
            Body('In Hasura DDN a permission is a ModelPermissions object in '
                'an .hml metadata file: a filter over rows for each role, '
                'versioned with the project and built by the ddn CLI. Only '
                'the admin role gets access by default. A Dartvel policy is '
                'Dart beside the model it guards, so it is type-checked with '
                'the model, can call any function the backend can, and '
                'answers no for anything nobody registered.'),
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
              'A field marked @DVModel.sensitiveField() is kept out of logs '
                  'and search, and encrypted: true seals it at rest.',
              'The records layer under the adapters is built so a document '
                  'database can sit behind the same data models. MongoDB is '
                  'planned and not built.',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where Hasura is ahead today.'),
            Bullets(<String>[
              'Hasura points at databases and APIs you already have, many of '
                  'them Dartvel has no adapter for, and gives you one API over '
                  'all of them, including ones nobody wants to rewrite.',
              'Its subscriptions are a documented client path today. '
                  "Dartvel's generated data models do not yet sync changes "
                  'to devices on their own.',
              'GraphQL is a standard with a large ecosystem of clients in '
                  "every language. Dartvel's generated client is Dart only, "
                  'and its GraphQL endpoint covers data models and not '
                  'federation.',
              'Hasura DDN is a running hosted product. Dartvel Cloud is not '
                  'open yet.',
              'Federating several databases and services behind one '
                  "supergraph is Hasura's job and not Dartvel's.",
            ]),
            VersusFair('These are not the same kind of tool. Hasura is an API '
                'layer over data you already have; Dartvel is the whole '
                'application. The comparison is worth making because a '
                'Flutter team choosing Hasura is often choosing it for typed '
                'data access from the app, and that is a thing Dartvel gives '
                'them without a query language.'),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Data models', '/docs/models'),
              GhostLink('Authorization', '/docs/authorization'),
              GhostLink('Sync and realtime', '/docs/sync'),
            ], spacing: 12),
            VersusChecked('Hasura DDN',
                'https://hasura.io/docs/3.0/llms-full.txt', '2026-09-25'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/hasura')]),
        SiteFooter(),
      ], spacing: 0),
    );
