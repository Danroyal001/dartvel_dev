import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel backend functions: typed endpoints in Dart', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsBackendFunctionsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsbackendfunctions,
      lead: <String>[
        'Write a Dart function under lib/backend/functions and it is an HTTP '
            'endpoint.',
        'Call it from your app as a typed function, with no client code to '
            'write.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'write',
          title: 'Write a backend function',
          children: <Widget>[
            DocsCode('backend-hello'),
            Bullets(<String>[
              'The file name sets the method: .get, .post, .put, .patch, '
                  '.delete, .head or .options. No suffix means POST.',
              'The path comes from the folders, with [id] as a parameter and '
                  'index as the folder itself.',
              'Every route is served under apiBasePath, /api by default.',
            ]),
            DocsNote('Backend files import dartvel_core',
                'The backend runs without Flutter. Import '
                'package:dartvel_core/dartvel.dart there, and leave DV and the '
                'generated client barrel to the app.'),
          ],
        ),
        DocsSection(
          id: 'call',
          title: 'Call it from the app',
          children: <Widget>[
            DocsCode('backend-client'),
            Bullets(<String>[
              'Parameters become required named arguments.',
              'String, int, double, bool, List and Map results decode for you. '
                  'Other types take a fromJson argument.',
              'The raw call is there too, named after the route: getHello(...) '
                  'returns the whole response.',
            ]),
            DocsNote('Keep the two names apart',
                'The raw call for hello.get.dart is getHello. A function named '
                '_getHello in that file would generate the same name, and the '
                'build stops and suggests another.'),
          ],
        ),
        DocsSection(
          id: 'parameters',
          title: 'Receive parameters',
          children: <Widget>[
            Bullets(<String>[
              'Each parameter is read from the path, then the query string, '
                  'then the body.',
              'String, int, double and bool values are converted for you.',
            ]),
          ],
        ),
        DocsSection(
          id: 'context',
          title: 'Use DVContext for the session and commit hooks',
          children: <Widget>[
            DocsCode('backend-context'),
            Bullets(<String>[
              'A first parameter of type DVContext is injected and left out of '
                  'the client call.',
              'context.session has the signed-in user, their tenant and claims.',
              'context.afterCommit runs once the function succeeds. '
                  'context.compensate runs if it fails.',
            ]),
          ],
        ),
        DocsSection(
          id: 'streams',
          title: 'Stream results with server-sent events',
          children: <Widget>[
            DocsCode('backend-stream'),
            DocsText('Return a Stream and the endpoint responds with '
                'text/event-stream. The client function returns a Stream you '
                'listen to.'),
            DocsStatus('Streaming Functions'),
          ],
        ),
        DocsSection(
          id: 'transactions',
          title: 'Undo partial work with a transaction',
          children: <Widget>[
            DocsCode('backend-transaction'),
            Bullets(<String>[
              'If the body throws, compensations run in reverse order and the '
                  'error is rethrown.',
              'In the app, the same call is DV.transaction((DVContext context) '
                  'async { ... }).',
              'A nested transaction joins the outer one unless you pass '
                  'isolated: true.',
            ]),
          ],
        ),
        DocsSection(
          id: 'background',
          title: 'Move slow work to a job',
          children: <Widget>[
            DocsText('Dispatch a job and return straight away. A worker runs it '
                'with retries.'),
            DocsCode('backend-background'),
            DocsText('See Queues and jobs for declaring the job and running '
                'workers.'),
          ],
        ),
        DocsSection(
          id: 'policies',
          title: 'Protect a function with a policy and MFA',
          children: <Widget>[
            Bullets(<String>[
              'policy: \'Order.update\' asks the OrderPolicy class. A refusal is '
                  '403, or 401 when nobody is signed in.',
              'mfa: DVMfa.required, or DVMfa.recent(duration), needs a recent '
                  'second factor.',
              'A policy nothing answers stops the build.',
            ]),
            DocsText('See Authorization for writing the policy.'),
          ],
        ),
        DocsSection(
          id: 'middleware',
          title: 'Add middleware',
          children: <Widget>[
            DocsCode('backend-middleware'),
            Bullets(<String>[
              'Middleware runs in the order you list it.',
              'CSRF checks run on every POST, PUT, PATCH and DELETE, and the '
                  'generated client sends the token.',
              'CORS and compression are set in pubspec.yaml under '
                  'dartvel.server.',
            ]),
            DocsStatus('Middleware', missing: <String>[
              'Page middleware cannot preload data or set SEO context.',
              'No layout, model or storage scopes, and no global middleware '
                  'setting.',
            ]),
          ],
        ),
        DocsSection(
          id: 'openapi',
          title: 'Get an OpenAPI document for free',
          children: <Widget>[
            DocsText('The backend serves an OpenAPI 3.1 description of your '
                'functions at /api/openapi.json.'),
          ],
        ),
      ],
    );
