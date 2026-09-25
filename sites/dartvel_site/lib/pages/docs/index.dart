import 'package:flutter/material.dart';

import '../../components/site.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel docs: install the CLI and run your first app',
  description: 'Install the dartvel command and run your first app. Every '
      'command on this page matches what dartvel --help prints.',
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
              '# npm: downloads the prebuilt binary, no Dart SDK needed',
              'npm install -g dartvel_dev',
              '',
              '# Homebrew: the same binary',
              'brew install Danroyal001/dartvel_dev/dartvel_dev',
              '',
              '# In a project, from its dev_dependencies',
              'dart run dartvel_cli:dartvel --help',
            ]),
            Bullets(<String>[
              'The command is dartvel, whichever way you install it.',
              'You can also download the binary from the GitHub releases '
                  'page. dartvel ensure-path adds it to your PATH if your shell '
                  'cannot find it.',
              'The Homebrew tap is updated after each release, so it can be a '
                  'version behind npm.',
              'dart pub global activate is not a supported install. Activating '
                  'dartvel_dev succeeds and every run then fails, because the '
                  'package depends on Flutter and pub will not run a global '
                  'command from a package that does.',
              'dart run works in a project that already lists dartvel_cli in '
                  'dev_dependencies, which dartvel create writes. The first '
                  'run compiles the CLI, so it is slower than the binary.',
              'dartvel update installs the latest release later.',
            ]),
            DocsNote('0.6.0 binaries are Linux only for now',
                'As of 2026-09-25, the 0.6.0 release has Linux binaries only, '
                'so npm install works on Linux. The macOS and Windows binaries '
                'follow when the release workflow can run again. Until then, '
                'install on a Linux machine or wait for those binaries.'),
            ExternalLink('Download a release', kReleasesUrl),
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
            DocsText('Each directory has a key of its own: pagesDir, modelsDir, '
                'backendDir, componentsDir, stylesDir and servicesDir. Leave one '
                'out and it keeps the path shown above.'),
            DocsSubheading('Keep the configuration in Dart'),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel: config/dartvel.dart',
            ]),
            DocsText('Point dartvel: at a Dart file instead of a map. The file '
                'must declare a public class that extends DartvelConfig.'),
            DocsSubheading('One package with every import'),
            DocsText('dartvel_dev re-exports the Dartvel packages as barrels: '
                'dartvel_ui.dart, dartvel_backend.dart, dartvel_auth.dart, '
                'dartvel_database.dart, dartvel_storage.dart, dartvel_ai.dart and '
                'more. A generated app imports its own dartvel_client.dart '
                'barrel.'),
            DocsStatus('Project Structure', missing: <String>[
              'Directory keys take one path each. Glob patterns are not read, '
                  'so pages cannot live in two directories.',
            ]),
            DocsStatus('Package Structure', missing: <String>[
              'The Rust bindings are DVRust and DVRustInt, one integer '
                  'type. They are types you construct, so there is no '
                  'DV.Rust to call.',
            ]),
          ],
        ),
        DocsSection(
          id: 'services',
          title: 'Choose your services at startup',
          children: <Widget>[
            DocsText('Set up auth and mail in main.dart, before runApp.'),
            DocsCode('start-configure'),
            DocsText('These are the in-memory versions for development. Each '
                'topic page shows the production adapters.'),
            DocsText('The database is configuration, not code. The generated '
                'backend opens DATABASE_URL for your data models and jobs.'),
            DocsShell(<String>[
              '# .env',
              'DATABASE_URL=sqlite:dartvel.db',
            ]),
          ],
        ),
        DocsSection(
          id: 'golden-path',
          title: 'Go from idea to production with one CLI',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel create shop',
              'dartvel dev',
              'dartvel db migrate',
              'dartvel test',
              'dartvel build web-server',
              'dartvel deploy',
              'dartvel upgrade --plan',
            ]),
            Bullets(<String>[
              'Every step is one command, from a new project to a deployed '
                  'server.',
              'upgrade --plan lists what a new Dartvel release would change in '
                  'your project, and dartvel migrate-code --apply rewrites the '
                  'source for you.',
            ]),
            DocsStatus('The Golden Path', missing: <String>[
              'dartvel upgrade does not apply an upgrade yet. It plans one, and '
                  'you make the changes it lists.',
            ]),
          ],
        ),
        DocsSection(
          id: 'inspect',
          title: 'Ask the CLI what your project contains',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel inspect routes',
              'dartvel inspect models',
              'dartvel explain DV-GEN-001',
            ]),
            Bullets(<String>[
              'inspect prints the routes, models, functions and jobs the build '
                  'found, from the same project graph Studio reads.',
              'explain tells you what a DV- error code means and how to fix it.',
            ]),
            DocsStatus('Unified Development, Transparency, and Contracts',
                missing: <String>[
              'There is no inspector yet for modules, transactions, the schema '
                  'or generated files.',
            ]),
          ],
        ),
        DocsSection(
          id: 'determinism',
          title: 'Generated code is the same on every machine',
          children: <Widget>[
            DocsShell(<String>['dartvel generate --check']),
            Bullets(<String>[
              'The same project generates byte-identical files on any machine '
                  'and in any folder, with no timestamps or absolute paths.',
              'generate --check fails your CI when the committed files are '
                  'stale, without touching the project.',
            ]),
            DocsStatus('Generated Code Determinism', missing: <String>[
              'Generated files are not run through dart format.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Check what is built before you depend on it',
          children: <Widget>[
            Bullets(<String>[
              'Dartvel is at 0.6. Some features are complete and some are '
                  'partial.',
              'Twenty-four sections are a frozen public contract with unfinished code '
                  'behind them.',
              'Pages in these docs mark partial features and say what is '
                  'missing.',
              'The full record is spec-status.json in the Dartvel repository.',
            ]),
            DocsPlatformIndex(),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('See what works today', '/features'),
              ExternalLink('Read spec-status.json', kSpecStatusUrl),
            ], spacing: 20, crossAlign: DVCrossAlign.center),
          ],
        ),
      ],
    );
