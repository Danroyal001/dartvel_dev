import 'package:flutter/material.dart';

import '../../components/site.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel docs: install the CLI and run your first app',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docs,
      lead: <String>[
        'Install the dartvel command and run a new app on your machine.',
        'Every command here matches what dartvel --help prints.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'install',
          title: 'Install the CLI',
          children: <Widget>[
            DocsText('You need Flutter 3.44 or newer, which ships Dart 3.12. '
                'Pick one install method.'),
            DocsShell(<String>[
              '# Homebrew: a prebuilt binary, no Dart SDK needed',
              'brew install Danroyal001/dartvel_dev/dartvel_dev',
              '',
              '# npm: downloads the same binary',
              'npm install -g dartvel_dev',
              '',
              '# pub: when you already have Dart',
              'dart pub global activate dartvel_cli',
            ]),
            Bullets(<String>[
              'The command is dartvel, whichever way you install it.',
              'dartvel ensure-path adds it to your PATH if your shell cannot '
                  'find it.',
              'dartvel update installs the latest release later.',
            ]),
          ],
        ),
        DocsSection(
          id: 'create',
          title: 'Create an app',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel create my_app',
              'cd my_app',
            ]),
            Bullets(<String>[
              'It runs flutter create, then adds pages, a backend and the '
                  'Dartvel dependencies.',
              'Web and mobile are on by default. Add --desktop for Windows, '
                  'macOS and Linux.',
              'dartvel init adds Dartvel to a Flutter project you already have.',
            ]),
          ],
        ),
        DocsSection(
          id: 'dev',
          title: 'Run it with dartvel dev',
          children: <Widget>[
            DocsShell(<String>['dartvel dev']),
            Bullets(<String>[
              'It generates the client, starts the backend and runs the '
                  'Flutter app.',
              'Edit a page and Flutter hot-reloads. Edit a backend function '
                  'and only the backend restarts.',
              'Pick a device with -d, for example dartvel dev -d chrome.',
            ]),
            DocsNote('Generated code is not committed',
                'dartvel dev and dartvel build write lib/dartvel_client for you. '
                'After a fresh clone, run dartvel routes once before your '
                'editor analyzes the project.'),
          ],
        ),
        DocsSection(
          id: 'first-page',
          title: 'Write your first page',
          children: <Widget>[
            DocsText('A file under lib/pages is a route. This is '
                'lib/pages/index.dart, served at /.'),
            DocsCode('start-index-page'),
            Bullets(<String>[
              'The annotated function is private. Dartvel generates the public '
                  'page and the DVRoutes target.',
              'Import the generated barrel, dartvel_client.dart. It exports '
                  'Dartvel and your generated code.',
            ]),
          ],
        ),
        DocsSection(
          id: 'structure',
          title: 'Project structure',
          children: <Widget>[
            DocsShell(<String>[
              'my_app/',
              '  pubspec.yaml            # dependencies and the dartvel: block',
              '  .env  .env.example      # values read at startup',
              '  lib/',
              '    main.dart',
              '    pages/                # one file per route',
              '      index.dart',
              '      index.loading.dart  # shown while the page loads',
              '      index.error.dart    # shown when it fails to load',
              '    models/               # @DVModel classes',
              '    components/           # your widgets',
              '    styles/  services/',
              '    backend/functions/    # one file per endpoint',
              '      health.get.dart',
              '      contact.dart',
              '    dartvel_client/       # generated, ignored by git',
              '  test/',
            ]),
            DocsSubheading('The dartvel block in pubspec.yaml'),
            DocsShell(<String>[
              'dartvel:',
              '  backendHost: 0.0.0.0',
              '  backendPort: 3000',
              '  devBackendHost: http://localhost:3000',
              '  prodBackendHost: https://api.my-app.com',
              '  pagesDir: lib/pages',
              '  backendDir: lib/backend',
              '  apiBasePath: /api',
              '  envFiles: [.env, .env.local]',
            ]),
            Bullets(<String>[
              'The app calls devBackendHost in development and prodBackendHost '
                  'in a release build.',
              'Backend functions are served under apiBasePath.',
            ]),
          ],
        ),
        DocsSection(
          id: 'services',
          title: 'Choose your services at startup',
          children: <Widget>[
            DocsText('Set up auth, the database and mail in main.dart, before '
                'runApp.'),
            DocsCode('start-configure'),
            DocsText('These are the in-memory versions for development. Each '
                'topic page shows the production adapters.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Check what is built before you depend on it',
          children: <Widget>[
            Bullets(<String>[
              'Dartvel is at 0.5. Some features are complete and some are '
                  'partial.',
              'Nineteen sections are a frozen public contract with unfinished code '
                  'behind them.',
              'Pages in these docs mark partial features and say what is '
                  'missing.',
              'The full record is spec-status.json in the Dartvel repository.',
            ]),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('See what works today', '/features'),
              ExternalLink('Read spec-status.json', kSpecStatusUrl),
            ], spacing: 20, crossAlign: DVCrossAlign.center),
          ],
        ),
      ],
    );
