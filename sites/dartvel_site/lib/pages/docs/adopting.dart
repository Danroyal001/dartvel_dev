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
        'dartvel init changes two things in pubspec.yaml and moves no files.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'init',
          title: 'Run dartvel init',
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
                'and use dart run dartvel_cli:dartvel.'),
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
              'A GoRoute path that matches a generated page stops dartvel routes '
                  'with DV-ADOPT-002 before it writes anything.',
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
              <String>['DV-ADOPT-005', 'dartvel create was pointed at a pubspec it '
                  'did not write. Use dartvel init'],
            ]),
            DocsShell(<String>['dartvel explain DV-ADOPT-003']),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Adoption', missing: <String>[
              'No bridges between signals and Riverpod providers or streams.',
              'No auth adapters for Firebase Auth or Supabase Auth.',
              'No mount for Navigator 1.0 or routers other than go_router.',
            ]),
          ],
        ),
      ],
    );
