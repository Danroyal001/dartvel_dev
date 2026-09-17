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
          id: 'raw-paths',
          title: 'Serve a webhook at a fixed path',
          children: <Widget>[
            DocsCode('backend-raw-path'),
            Bullets(<String>[
              'rawPath serves the function at exactly that path, outside '
                  'apiBasePath. rawPathSuffix adds to the generated path '
                  'instead, and you can use only one of the two.',
              'A raw path reads no session cookie and asks for no CSRF token, '
                  'so a payment provider can POST to it. An API key or OAuth '
                  'token sent to it is still checked.',
              'Both take plain segments. A path parameter in one stops the '
                  'build, and so do two functions on the same address.',
            ]),
          ],
        ),
        DocsSection(
          id: 'lifecycle',
          title: 'Watch a request move through its stages',
          children: <Widget>[
            DocsCode('backend-lifecycle'),
            Bullets(<String>[
              'context.lifecycle.request is read-only. You observe it, and the '
                  'framework moves it.',
              'Before your code runs, the body is read and the MFA and policy '
                  'checks pass, with the CSRF check first on a generated path.',
              'An error thrown by the function answers 500, runs its '
                  'compensations and is recorded as a server crash.',
            ]),
            DocsStatus('Backend Function Request Lifecycle', missing: <String>[
              'Four stages are set today: received, executing, '
                  'preparingResponse and failed.',
              'transaction, authentication and rateLimit are not parameters of '
                  '@DVBackendFunction yet.',
              'The generated client does not send the binary flat-buffer '
                  'format, though the server decodes it.',
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
            DocsStatus('Background and Durable Work', missing: <String>[
              'background: and durable: are not parameters of '
                  '@DVBackendFunction yet. Dispatch a job as shown here.',
            ]),
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
              'Middleware runs in the order you list it. The keys that run are '
                  'auth, tenant, rateLimit, requestLogging, securityHeaders, '
                  'locale, idempotency, featureFlags, maintenance and csp.',
              'bodyLimit and uploadLimit cap the request body at 1 MiB and 16 '
                  'MiB, and answer 413 past it. tracing starts a trace for the '
                  'request.',
              'A key that does nothing yet, such as cors or cacheTags, stops the '
                  'build and says why.',
            ]),
            DocsSubheading('Set limits for the whole server'),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  server:',
              '    maxBodyBytes: 2097152',
              '    compression: true',
              '    trustedProxies: [10.0.0.0/8]',
            ]),
            DocsText('CORS sits in the same server block. Every key there is '
                'checked when dartvel routes runs.'),
            DocsStatus('Middleware', missing: <String>[
              'Page middleware cannot preload data or set SEO context.',
              'No layout, model or storage scopes, and no global middleware '
                  'setting.',
            ]),
          ],
        ),
        DocsSection(
          id: 'csrf',
          title: 'CSRF protection is on for every function',
          children: <Widget>[
            Bullets(<String>[
              'A POST, PUT, PATCH or DELETE to a generated function needs the '
                  'x-dartvel-csrf-token header, or it gets 403.',
              'The generated client sends the token for you, so there is '
                  'nothing to add to your app.',
              'Writing your own client? DV.CSRF.token() makes a token and '
                  'DVCSRF.headerName names the header.',
            ]),
            DocsStatus('CSRF Protection'),
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
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Backend', missing: <String>[
              'Functions are served over HTTP. WebSocket and polling '
                  'transports are not generated.',
            ]),
          ],
        ),
      ],
    );
