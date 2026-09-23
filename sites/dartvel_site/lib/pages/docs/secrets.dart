import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel secrets and environments: keys that stay on the server',
  description: 'A backend secret that reaches client code stops the build '
      'before it can ship in an app bundle, and a deploy stops when '
      'its environment is missing one.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsSecretsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docssecrets,
      lead: <String>[
        'A backend secret that reaches client code stops the build, before it '
            'can ship in an app bundle.',
        'A deploy stops when a secret its environment needs is missing.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'declare',
          title: 'Declare your secrets',
          children: <Widget>[
            DocsYaml('yaml-secrets'),
            Bullets(<String>[
              'A secret is backend-only unless it says scope: client, and a '
                  'client secret must start with PUBLIC_. A name that breaks '
                  'either rule stops the build.',
              'required lists the environments it must be set in. dartvel '
                  'deploy --environment production refuses to start without '
                  'them.',
            ]),
          ],
        ),
        DocsSection(
          id: 'read',
          title: 'Read a secret on the server',
          children: <Widget>[
            DocsCode('secrets-read'),
            Bullets(<String>[
              'App code uses DV.Secrets. get throws when the name is unset, and '
                  'maybeGet, getOr and has do not.',
              'Values come from DVSecrets.configure, then the environment, then '
                  'systemd credentials, then your .env files.',
              'A value you have read is replaced with [redacted] in logs, crash '
                  'reports and analytics events, once it is 8 characters long.',
            ]),
          ],
        ),
        DocsSection(
          id: 'build-checks',
          title: 'What the build refuses',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Code',
              'Means',
            ], rows: <List<String>>[
              <String>['DV-SECRETS-001', 'Client code reads a backend secret'],
              <String>['DV-SECRETS-002', 'Code reads a name nobody declared'],
              <String>['DV-SECRETS-003', 'An env file has a PUBLIC_ variable '
                  'nobody declared, which would be compiled into the app'],
            ]),
            Bullets(<String>[
              'Client code means lib/ outside your backend directory.',
              'PUBLIC_ values are compiled into env.g.dart as Env.PUBLIC_NAME. '
                  'Anyone with the app can read them, so keep real keys out.',
            ]),
          ],
        ),
        DocsSection(
          id: 'tests',
          title: 'Give a test its own secrets',
          children: <Widget>[
            DocsCode('secrets-test'),
          ],
        ),
        DocsSection(
          id: 'app-key',
          title: 'Keep the application key in the OS keychain',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel key generate',
              'dartvel key status',
              'dartvel key rotate',
            ]),
            Bullets(<String>[
              'The key encrypts what your app stores on the device. generate '
                  'refuses to replace a key that exists.',
              'It is held by the Secret Service on Linux, the Keychain on macOS '
                  'and iOS, DPAPI on Windows and the Keystore on Android.',
              'rotate records the old and new fingerprints, so you can tell '
                  'which key wrote what.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Secrets and Environments', missing: <String>[
              'No Vault or cloud KMS adapter. A secrets manager feeds values in '
                  'through DVSecrets.configure.',
              'The build checks names written as literals only.',
              'The Android Keystore and iOS Keychain paths have not been checked '
                  'on real devices.',
            ]),
          ],
        ),
      ],
    );
