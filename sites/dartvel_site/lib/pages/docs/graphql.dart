import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel GraphQL and OpenAPI endpoints',
  description: 'Your models already have a GraphQL API and your backend '
      'functions already have an OpenAPI document. The generated '
      'backend serves both with no setup.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsGraphqlPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsgraphql,
      lead: <String>[
        'Your models already have a GraphQL API, and your backend functions '
            'already have an OpenAPI document.',
        'Both are served by the generated backend with no setup.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'endpoints',
          title: 'The endpoints',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Endpoint',
              'Serves',
            ], rows: <List<String>>[
              <String>['POST /api/graphql', 'Queries and mutations'],
              <String>['GET /api/graphql/schema', 'The schema as SDL'],
              <String>['POST /api/graphql/stream', 'Subscriptions as server-sent '
                  'events'],
              <String>['GET /api/openapi.json', 'OpenAPI 3.1 for your backend '
                  'functions'],
            ]),
          ],
        ),
        DocsSection(
          id: 'models',
          title: 'Query your models',
          children: <Widget>[
            Bullets(<String>[
              'Each model with a key gets a type, list and single queries, and '
                  'save and delete mutations.',
              'Sensitive fields are left out of the schema.',
              'Every resolver checks the model\'s policy.',
            ]),
          ],
        ),
        DocsSection(
          id: 'fields',
          title: 'Add your own fields',
          children: <Widget>[
            DocsCode('graphql-field'),
            DocsText('DVGraphQLField also takes args, cost, pageSize and '
                'policy.'),
          ],
        ),
        DocsSection(
          id: 'limits',
          title: 'Set limits',
          children: <Widget>[
            DocsYaml('yaml-graphql'),
            Bullets(<String>[
              'maxDepth and maxCost take a number or auto.',
              'introspection is development, never or authenticated.',
              'persistedQueries is off, prefer or require.',
            ]),
          ],
        ),
        DocsSection(
          id: 'import',
          title: 'Go the other way: generate a client from a spec',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel import openapi openapi.yaml --dry-run',
              'dartvel import postman collection.json',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('APIs'),
          ],
        ),
      ],
    );
