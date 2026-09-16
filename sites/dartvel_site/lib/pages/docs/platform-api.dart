import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel platform API: API keys, scopes and OAuth', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsPlatformApiPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsplatformapi,
      lead: <String>[
        'Let other systems call your API with scoped keys or OAuth tokens.',
        'Scopes map to the same policy actions your own app uses.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'declare',
          title: 'Declare scopes and rate plans',
          children: <Widget>[
            DocsYaml('yaml-platform-api'),
            Bullets(<String>[
              'Each scope lists the policy actions it allows. An action no '
                  '@DVPolicy defines fails with DV-APIKEY-001.',
              'A rate plan is a number of requests per window.',
              'oauth: true turns on the OAuth authorization server.',
            ]),
          ],
        ),
        DocsSection(
          id: 'keys',
          title: 'Issue an API key',
          children: <Widget>[
            DocsCode('platform-api-keys'),
            Bullets(<String>[
              'Keys start dvk_ and OAuth access tokens start dvat_.',
              'list, rotate and revoke manage keys. rotate can keep the old key '
                  'working for an overlap.',
              'DV.Auth.oauthClients registers, lists and revokes OAuth clients.',
            ]),
          ],
        ),
        DocsSection(
          id: 'oauth',
          title: 'OAuth endpoints',
          children: <Widget>[
            DocsShell(<String>[
              '/oauth/authorize',
              '/oauth/token',
              '/oauth/introspect',
              '/oauth/revoke',
              '/.well-known/oauth-authorization-server',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Platform API: Keys, Scopes and OAuth Provider',
                missing: <String>[
                  'No generated ApiKey model. apiKeys takes the user and actor '
                      'explicitly.',
                  'No OpenID Connect or JWT tokens, and no developer portal.',
                  'Rate plans count per server instance.',
                ]),
          ],
        ),
      ],
    );
