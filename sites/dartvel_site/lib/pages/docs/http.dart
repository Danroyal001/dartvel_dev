import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel outbound HTTP: declared hosts, retries and timeouts',
  description: 'Declare each API your app calls once, with its timeout and '
      'retries. A call to a host you did not declare is refused '
      'before anything leaves the process.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsHttpPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docshttp,
      lead: <String>[
        'Declare each API your app calls once, with its timeout and retries.',
        'A call to a host you did not declare is refused before anything is '
            'sent.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'declare',
          title: 'Declare a host',
          children: <Widget>[
            DocsYaml('yaml-http'),
            Bullets(<String>[
              'auth: { bearer: SECRET_NAME } sends a secret as a bearer token.',
              'headers, circuitBreaker and pool: { maxConcurrent } are there '
                  'too.',
              'An unknown key stops the build.',
            ]),
          ],
        ),
        DocsSection(
          id: 'call',
          title: 'Call a declared host',
          children: <Widget>[
            DocsCode('http-host'),
            Bullets(<String>[
              'get, head and delete take a path. post, put and patch also take '
                  'json: or body:.',
              'Pass idempotencyKey: to retry a POST safely.',
              'The response is a standard Response with status, headers and '
                  'body.',
            ]),
          ],
        ),
        DocsSection(
          id: 'undeclared',
          title: 'Undeclared hosts are refused',
          children: <Widget>[
            DocsText('A literal URL no declared host covers stops '
                '`dartvel routes` with DV-HTTP-001. A URL built at run time is refused '
                'when the call runs.'),
            DocsCode('http-undeclared'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Outbound HTTP', missing: <String>[
              'The build checks literal URLs only.',
              'Bearer is the only auth scheme.',
              'Backend code uses const DVHttp(), because DV is not available '
                  'there.',
            ]),
          ],
        ),
      ],
    );
