import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Add Dartvel to an existing Flutter app',
  description: 'Add Dartvel to the Flutter app you already have, one screen at '
      'a time. dartvel init changes two things in pubspec.yaml and '
      'moves none of your files.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsAdoptingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsadopting,
      lead: <String>[
        'Add Dartvel to the Flutter app you already have, one screen at a time.',
        '`dartvel init` changes two things in pubspec.yaml and moves no files.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'init',
          title: 'Run `dartvel init`',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel init --dry-run   # the report and the changes, nothing written',
              'dartvel init',
            ]),
            Bullets(<String>[
              'It adds dartvel_core, plus dartvel_flutter for a Flutter app, and '
                  'a dartvel: block. Every other line and comment stays.',
              'It reports first: your SDK constraint against Dart 3.13, and each '
                  'package you share with Dartvel against its constraint.',
              'When lib/pages or lib/backend already hold your files, it picks '
                  'other directories so nothing of yours is claimed.',
            ]),
            DocsNote('Add the CLI yourself',
                'init adds the runtime only. Run the generator from the dartvel '
                'binary you installed, or add dartvel_cli as a dev dependency '
                'and use `dart run dartvel_cli:dartvel`.'),
          ],
        ),
        DocsSection(
          id: 'mount',
          title: 'Keep your GoRouter',
          children: <Widget>[
            DocsShell(<String>[
              'GoRouter(routes: <RouteBase>[',
              '  ...myRoutes,',
              '  ...dartvelRoutes(at: \'/app\'),',
              '])',
            ]),
            Bullets(<String>[
              'dartvelRoutes(at:) mounts the generated pages under a prefix in '
                  'your own router.',
              'DVGoRoutes goes the other way and puts your GoRoute list inside '
                  'the generated router.',
              'A GoRoute path that matches a generated page stops `dartvel routes` '
                  'with DV-ADOPT-002 before it writes anything.',
            ]),
          ],
        ),
        DocsSection(
          id: 'other-routers',
          title: 'Keep your auto_route or Navigator',
          children: <Widget>[
            DocsText('Dartvel mounts into three routers: go_router, auto_route and '
                'Flutter\'s own Navigator. `dartvel init` says which one your app '
                'uses. Any other router is named, with these three.'),
            DocsShell(<String>[
              '// auto_route',
              'List<AutoRoute> get routes => <AutoRoute>[',
              '  ...myRoutes,',
              '  ...dartvelAutoRoutes(at: \'/app\'),',
              '];',
              '',
              '// Navigator 1.0',
              'MaterialApp(',
              '  onGenerateRoute: (RouteSettings settings) =>',
              '      dartvelOnGenerateRoute(settings, at: \'/app\') ?? myRoute(settings),',
              ');',
              'Navigator.pushNamed(context, dvHostedPath(DVRoutes.about.path, at: \'/app\'));',
              '',
              '// Navigator 2.0, in your RouterDelegate',
              'Navigator(pages: <Page<Object?>>[',
              '  ...myPages,',
              '  ?dartvelPageFor(location, at: \'/app\'),',
              '])',
            ]),
            Bullets(<String>[
              'Dartvel\'s pages run in a router of their own under the prefix, '
                  'with their own guards and redirects.',
              'Back goes through Dartvel\'s stack first, then yours. On the web '
                  'the address bar follows the Dartvel page.',
              'Deep links to /app/... open the page; a path that is not a '
                  'Dartvel page is left to your router.',
            ]),
          ],
        ),
        DocsSection(
          id: 'inventory',
          title: 'See what Dartvel manages',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel inspect adoption',
              'dartvel inspect adoption --json',
              'dartvel db pull --local',
            ]),
            Bullets(<String>[
              'inspect adoption counts routes, models, screens and functions as '
                  'managed or not, and says how it counted each.',
              'db pull --local prints @DVModel suggestions from drift tables, '
                  'isar collections and sqflite CREATE TABLE strings. It writes '
                  'nothing.',
              'It never marks a field sensitive for you. Decide that yourself.',
            ]),
          ],
        ),
        DocsSection(
          id: 'codes',
          title: 'Adoption errors',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Code',
              'Means',
            ], rows: <List<String>>[
              <String>['DV-ADOPT-001', 'Stated once by init: multi-tenancy '
                  'scopes only the models Dartvel manages'],
              <String>['DV-ADOPT-002', 'A route of yours has the same path as a '
                  'generated page'],
              <String>['DV-ADOPT-003', 'A @DVModel class also uses freezed, '
                  'json_serializable or dart_mappable'],
              <String>['DV-ADOPT-005', '`dartvel create` was pointed at a pubspec it '
                  'did not write. Use `dartvel init`'],
            ]),
            DocsShell(<String>['dartvel explain DV-ADOPT-003']),
          ],
        ),
        DocsSection(
          id: 'native-apps',
          title: 'Existing native apps (Android, iOS, desktop)',
          children: <Widget>[
            DocsText('Dartvel can be embedded into an existing native '
                'application the same way Flutter supports add-to-app: '
                'a Dartvel module hosts the screens and backend, and the '
                'native app hosts it through its embedder.'),
            Bullets(<String>[
              'The CLI supports `dartvel init` for native projects that '
              'already have a build system (Gradle, Xcode, CMake). It writes '
              'a `dartvel:` block pointing at the existing native source.',
              'Routing between native screens and Dartvel pages uses '
              '`dartvelRoutes(at:)` mounted at a prefix the native router '
              'reserves (e.g. `/app`).',
              'Shared auth and session pass through the same backend '
              'functions; the native app calls them through the same '
              'generated client (`dartvel_client/dartvel_client.dart`).',
              'Deep links open the native app at the Dartvel page; '
              'push notifications are delivered through the framework\'s '
              '`DV.Notifications` service.',
              'What exists today: `dartvel init` detects native build '
              'files; the module mount works; the generated backend '
              'serves the embedded app. What is planned: full add-to-app '
              'scaffold generation for Kotlin/Java (Android), Swift '
              '(iOS) and desktop embedder hosts.',
            ]),
            DocsStatus('Native App Embedding', missing: <String>[
              'No full Kotlin/Java, Swift/Objective-C or desktop-native '
              'scaffold generator yet. The framework supports module '
              'mounts and shared auth; native-side routing and '
              'embedding templates are planned.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Adoption', missing: <String>[
              'No bridges between signals and Riverpod providers or streams.',
              'No auth adapters for Firebase Auth or Supabase Auth.',
              'No mount for routers other than go_router, auto_route and '
                  'Flutter\'s Navigator.',
            ]),
          ],
        ),
      ],
    );
