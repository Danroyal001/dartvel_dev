import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Add Dartvel to an existing Flutter app',
  description:
      'Add Dartvel to the Flutter app you already have, one screen at '
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
        DocsNote(
          'Add the CLI yourself',
          'init adds the runtime only. Run the generator from the dartvel '
              'binary you installed, or add dartvel_cli as a dev dependency '
              'and use `dart run dartvel_cli:dartvel`.',
        ),
      ],
    ),
    DocsSection(
      id: 'routers',
      title: 'Keep your router',
      children: <Widget>[
        DocsText(
          'Dartvel works with five kinds of routing: go_router, '
          'auto_route, Navigator 1.0, Navigator 2.0, and '
          'MaterialApp.router or CupertinoApp.router with a RouterConfig. '
          '`dartvel init` says which one your app uses.',
        ),
        DocsText(
          'Each one works the same way. You pass your existing '
          'routes or handler as `existing:`, in its own type. Dartvel '
          'answers its own paths under the mount, such as /app. Every '
          'other path goes to your handler, as it did before.',
        ),
        Bullets(<String>[
          'On a path both declare, Dartvel\'s page wins. `dartvel routes` '
              'also stops with DV-ADOPT-002 when a GoRoute of yours has '
              'the path of a generated page.',
          'Dartvel\'s routes stay typed: open one with '
              '`dvHostedPath(DVRoutes.users(id: \'7\').path, at: \'/app\')` '
              'or `DV.Navigation.navigate(DVRoutes.about)`. Your routes keep '
              'their own argument types.',
          'Dartvel\'s guards and redirects run on Dartvel\'s paths. Back '
              'goes through Dartvel\'s stack first, then yours.',
        ]),
      ],
    ),
    DocsSection(
      id: 'go-router',
      title: 'go_router',
      children: <Widget>[
        DocsShell(<String>[
          'final GoRouter router = dartvelGoRouter(',
          '  at: \'/app\',',
          '  existing: myRoutes,        // List<RouteBase>',
          '  redirect: myRedirect,      // GoRouterRedirect',
          ');',
          'MaterialApp.router(routerConfig: router);',
        ]),
        Bullets(<String>[
          'One GoRouter holds Dartvel\'s routes and yours. '
              'DV.Navigation is attached to it.',
          'Your redirect runs only on your paths. Dartvel\'s paths keep '
              'Dartvel\'s guards.',
          'Building the GoRouter yourself still works: '
              '`GoRouter(routes: [...myRoutes, ...dartvelRoutes(at: \'/app\')])`, '
              'then `DVNavigation.attach(router)`.',
        ]),
      ],
    ),
    DocsSection(
      id: 'auto-route',
      title: 'auto_route',
      children: <Widget>[
        DocsShell(<String>[
          'class AppRouter extends RootStackRouter {',
          '  @override',
          '  List<AutoRoute> get routes => dartvelAutoRoutes(',
          '        at: \'/app\',',
          '        existing: <AutoRoute>[',
          '          AutoRoute(page: HomeRoute.page, path: \'/\', initial: true),',
          '          AutoRoute(page: ProfileRoute.page, path: \'/profile\'),',
          '        ],',
          '      );',
          '}',
        ]),
        Bullets(<String>[
          'dartvelAutoRoutes is generated when your project depends on '
              'auto_route. It adds one route for each Dartvel path under '
              '/app, before yours.',
          'Your pages keep their generated route classes and typed '
              'arguments.',
          'auto_route and go_router both define RouteData and RouteMatch. '
              'Import the Dartvel client with '
              '`hide RouteData, RouteMatch` in files that use auto_route.',
        ]),
      ],
    ),
    DocsSection(
      id: 'navigator-1',
      title: 'Navigator 1.0',
      children: <Widget>[
        DocsShell(<String>[
          'MaterialApp(',
          '  onGenerateRoute: dartvelRouteFactory(',
          '    at: \'/app\',',
          '    existing: myOnGenerateRoute, // RouteFactory',
          '  ),',
          ');',
          'Navigator.pushNamed(context, dvHostedPath(DVRoutes.about.path, at: \'/app\'));',
        ]),
        Bullets(<String>[
          'A route name that is a Dartvel path gets the Dartvel page. '
              'Any other name goes to your onGenerateRoute, with its '
              'arguments.',
          'A name that neither handles goes to onUnknownRoute, as '
              'before.',
        ]),
      ],
    ),
    DocsSection(
      id: 'navigator-2',
      title: 'Navigator 2.0',
      children: <Widget>[
        DocsText(
          'If you wrote your own RouterDelegate, keep your routes in '
          'one table and spread Dartvel\'s into it. '
          'dartvelNavigator2_0Routes returns all of Dartvel\'s routes '
          'as a list:',
        ),
        DocsShell(<String>[
          'late final List<DVNavigatorRoute> table = <DVNavigatorRoute>[',
          '  DVNavigatorRoute(\'/settings\', (uri) => const MaterialPage(child: SettingsScreen())),',
          '  ...dartvelNavigator2_0Routes(at: \'/app\', onLocationChanged: go),',
          '];',
          '',
          '@override',
          'Widget build(BuildContext context) => Navigator(',
          '  key: navigatorKey,',
          '  pages: <Page<Object?>>[',
          '    const MaterialPage(child: HomeScreen()),',
          '    ...dvNavigatorPages(location, table),',
          '  ],',
          '  onDidRemovePage: (_) {},',
          ');',
        ]),
        Bullets(<String>[
          'Your delegate stays in charge: it keeps the location and the '
              'stack, and asks the table which page a location is. The '
              'first entry that matches answers.',
          'Every Dartvel route is an entry, under the prefix. Guards, '
              'parameters, the query and back work as in a Dartvel app.',
          'Under a prefix there is one more entry, /app/**, so an unknown '
              'path under /app gets Dartvel\'s not-found page.',
          'All of Dartvel\'s entries build the same page, so moving between '
              'two Dartvel paths keeps that page and its state.',
          'When someone navigates inside Dartvel, onLocationChanged gets '
              'the new location, such as /app/users/7. Store it, so your '
              'currentConfiguration and the address bar stay correct.',
          'You can also keep your delegate and parser unchanged, and pass '
              'them to dartvelRouterConfig (next section).',
        ]),
      ],
    ),
    DocsSection(
      id: 'router-config',
      title: 'MaterialApp.router and CupertinoApp.router',
      children: <Widget>[
        DocsShell(<String>[
          'MaterialApp.router(',
          '  routerConfig: dartvelRouterConfig(at: \'/app\', existing: myConfig),',
          ');',
          '',
          '// A delegate and a parser of your own:',
          'dartvelRouterConfig(',
          '  at: \'/app\',',
          '  existing: RouterConfig<MyConfiguration>(',
          '    routerDelegate: myDelegate,',
          '    routeInformationParser: myParser,',
          '  ),',
          ');',
        ]),
        Bullets(<String>[
          'Your RouterConfig can come from go_router, auto_route or your '
              'own delegate and parser. Its configuration type stays '
              'its own.',
          'A Dartvel path is handled by Dartvel. Every other location goes '
              'to your parser and delegate.',
          'Your screens stay loaded while a Dartvel page shows. Back from '
              'the first Dartvel page returns to them.',
          'With no existing config, dartvelRouterConfig() is the app\'s '
              'own Dartvel router.',
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
        DocsTable(
          columns: <String>['Code', 'Means'],
          rows: <List<String>>[
            <String>[
              'DV-ADOPT-001',
              'Stated once by init: multi-tenancy '
                  'scopes only the models Dartvel manages',
            ],
            <String>[
              'DV-ADOPT-002',
              'A route of yours has the same path as a '
                  'generated page',
            ],
            <String>[
              'DV-ADOPT-003',
              'A @DVModel class also uses freezed, '
                  'json_serializable or dart_mappable',
            ],
            <String>[
              'DV-ADOPT-005',
              '`dartvel create` was pointed at a pubspec it '
                  'did not write. Use `dartvel init`',
            ],
          ],
        ),
        DocsShell(<String>['dartvel explain DV-ADOPT-003']),
      ],
    ),
    DocsSection(
      id: 'native-apps',
      title: 'Existing native hosts',
      children: <Widget>[
        DocsText(
          'init adopts Flutter projects. Dartvel module mounts '
          'and backend generation are built; they do not create a '
          'Kotlin, Swift or desktop host integration.',
        ),
        DocsNote(
          'Planned',
          'Not yet implemented: native add-to-app '
              'artifact and host scaffold generation. See Existing native '
              'apps for the draft design.',
        ),
      ],
    ),
    DocsSection(
      id: 'status',
      title: 'Status',
      children: <Widget>[
        DocsStatus(
          'Adoption',
          missing: <String>[
            'No bridges between signals and Riverpod providers or streams.',
            'No auth adapters for Firebase Auth or Supabase Auth.',
            'Routing packages other than go_router and auto_route are not '
                'tested. They can only join through dartvelRouterConfig.',
          ],
        ),
      ],
    ),
  ],
);
