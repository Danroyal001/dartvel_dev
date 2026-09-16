// Config routes through the generator: lib/routes.dart read for its paths,
// checked against the pages, and mounted into the generated router with a
// typed target each.
//
// These read the emitted text. That the text compiles, and that the router
// it builds navigates, is generated_client_analyzes_test.dart and the example
// application's own widget tests.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _pubspec = '''
name: config_probe
publish_to: none
environment:
  sdk: ^3.12.0
dartvel:
  prodBackendHost: https://example.com
''';

String _page(String name) =>
    '''
import 'package:flutter/widgets.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: '$name')
@pragma('vm:entry-point')
Widget _${name}Page(BuildContext context) => const DVText('$name');
''';

const String _routes = '''
import 'package:flutter/widgets.dart';
import 'dartvel_client/dartvel_client.dart';

// A comment naming DVRoute(path: '/commented') is not a route.
final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(
    path: '/settings',
    title: 'Settings',
    builder: (context, state) => const Text('settings'),
  ),
  DVRoute(
    path: '/orders',
    builder: (context, state) => const Text('orders'),
    routes: <DVRouteNode>[
      DVRoute(
        path: ':id',
        name: 'order',
        builder: (context, state) => Text(state.params['id']!),
      ),
    ],
  ),
  DVShellRoute(
    redirect: (context, state) => null,
    builder: (context, state, child) => child,
    routes: <DVRouteNode>[
      DVRoute(path: '/admin/reports', builder: (c, s) => const Text('r')),
    ],
  ),
  DVStatefulShellRoute(
    builder: (context, state, shell) => shell,
    branches: <DVShellBranch>[
      DVShellBranch(routes: <DVRouteNode>[
        DVRoute(path: '/feed', builder: (c, s) => const Text('feed')),
      ]),
      DVShellBranch(routes: <DVRouteNode>[
        DVRoute(path: '/inbox', builder: (c, s) => const Text('inbox')),
      ]),
    ],
  ),
  DVGoRoutes(<RouteBase>[]),
];
''';

late Directory root;

void write(String rel, String contents) {
  File(p.join(root.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

String router() => File(
  p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
).readAsStringSync();

String routesClass() {
  final String source = router();
  final int start = source.indexOf('class DVRoutes {');
  return source.substring(start, source.indexOf('\n}', start));
}

Future<void> expectBuildError(String code, List<String> mentions) async {
  Object? error;
  try {
    await routes.generate(root_: root.path);
  } on Object catch (e) {
    error = e;
  }
  expect(error, isNotNull, reason: 'the build should have failed with $code');
  expect(error.toString(), contains(code));
  for (final String mention in mentions) {
    expect(error.toString(), contains(mention));
  }
  expect(
    File(
      p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
    ).existsSync(),
    isFalse,
    reason: 'a build that is going to fail must not write a router',
  );
}

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dartvel_config_routes_');
    write('pubspec.yaml', _pubspec);
    write('lib/pages/index.page.dart', _page('index'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('a routes file', () {
    test(
      'is imported and mounted beside the pages, in one ordered list',
      () async {
        write('lib/routes.dart', _routes);
        await routes.generate(root_: root.path);
        final String source = router();

        expect(
          source,
          contains("import 'package:config_probe/routes.dart' as dv_config;"),
        );
        expect(source, contains('_dartvelRouteList() => dvOrderGoRoutes(<RouteBase>['));
        expect(source, contains('...dvConfigRoutes(\n'));
        expect(source, contains('dv_config.routes,'));
        expect(source, contains('seo: _defaultSeo,'));
        expect(source, contains('transition: _projectDefaultTransition,'));
      },
    );

    test('gives every readable route a typed target', () async {
      write('lib/routes.dart', _routes);
      await routes.generate(root_: root.path);
      final String targets = routesClass();

      expect(
        targets,
        contains("static const settings = DVRouteTarget('/settings');"),
      );
      expect(
        targets,
        contains("static const orders = DVRouteTarget('/orders');"),
      );
      expect(
        targets,
        contains(
          "static DVRouteTarget order({required String id}) => "
          "DVRouteTarget('/orders/\$id');",
        ),
      );
      expect(
        targets,
        contains(
          "static const adminreports = DVRouteTarget('/admin/reports');",
        ),
      );
      expect(targets, contains("static const feed = DVRouteTarget('/feed');"));
      expect(
        targets,
        contains("static const inbox = DVRouteTarget('/inbox');"),
      );
      // The page is still there beside them.
      expect(targets, contains("static const index = DVRouteTarget('/');"));
      expect(targets, isNot(contains('commented')));
    });

    test('lists config routes in the manifest the web build reads', () async {
      write('lib/routes.dart', _routes);
      await routes.generate(root_: root.path);
      final String source = router();
      final String manifest = source.substring(
        source.indexOf('dartvelRouteManifest'),
      );

      for (final String path in <String>[
        '/settings',
        '/orders',
        '/orders/:id',
        '/admin/reports',
        '/feed',
        '/inbox',
      ]) {
        expect(manifest, contains("path: '$path',"), reason: path);
      }
      expect(manifest, contains("directory: 'lib/routes.dart',"));
    });

    test(
      'a route behind a redirect is guarded, and so out of the sitemap',
      () async {
        write('lib/routes.dart', _routes);
        await routes.generate(root_: root.path);
        final String source = router();
        final String guarded = source.substring(
          source.indexOf('dartvelGuardedRoutes'),
          source.indexOf('];', source.indexOf('dartvelGuardedRoutes')),
        );

        expect(guarded, contains("'/admin/reports'"));
        expect(guarded, isNot(contains("'/settings'")));
      },
    );

    test('the application guard covers config routes', () async {
      write('lib/routes.dart', _routes);
      write('lib/pages/_guard.dart', '''
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

FutureOr<String?> guard(BuildContext context, GoRouterState state) => null;
''');
      await routes.generate(root_: root.path);
      final String source = router();

      expect(source, contains('inheritedRedirect: g0.guard,'));
      final String guarded = source.substring(
        source.indexOf('dartvelGuardedRoutes'),
        source.indexOf('];', source.indexOf('dartvelGuardedRoutes')),
      );
      expect(guarded, contains("'/settings'"));
    });

    test('dartvel.routes moves it', () async {
      write('pubspec.yaml', '$_pubspec  routes: lib/app/nav.dart\n');
      write('lib/app/nav.dart', _routes);
      await routes.generate(root_: root.path);

      expect(
        router(),
        contains("import 'package:config_probe/app/nav.dart' as dv_config;"),
      );
    });
  });

  test('without a routes file the generated routes are still ordered', () async {
    // `[id].dart` sorts before `new.dart`, so file order alone hid /users/new.
    write('lib/pages/users/[id].page.dart', _page('user'));
    write('lib/pages/users/new.page.dart', _page('newUser'));
    await routes.generate(root_: root.path);
    final String source = router();

    expect(source, contains('_dartvelRouteList() => dvOrderGoRoutes(<RouteBase>['));
    expect(source, isNot(contains('dvConfigRoutes(')));
    expect(source, isNot(contains('dv_config')));
  });

  group('build errors', () {
    test('DV-ROUTE-001: a config route at a page\'s path', () async {
      write('lib/pages/settings.page.dart', _page('settings'));
      write('lib/routes.dart', _routes);
      await expectBuildError('DV-ROUTE-001', <String>[
        '/settings',
        'lib/pages/settings.page.dart',
        'lib/routes.dart:',
      ]);
    });

    test('DV-ROUTE-001: the same shape twice in config', () async {
      write('lib/routes.dart', '''
final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(path: '/users/:id', builder: (c, s) => const Text('a')),
  DVRoute(path: '/users/:slug', name: 'user', builder: (c, s) => const Text('b')),
];
''');
      await expectBuildError('DV-ROUTE-001', <String>[
        '/users/:id',
        '/users/:slug',
      ]);
    });

    test('DV-ROUTE-002: two routes with one typed target', () async {
      write('lib/routes.dart', '''
final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(
    path: '/orders',
    builder: (c, s) => const Text('a'),
    routes: <DVRouteNode>[
      DVRoute(path: ':id', builder: (c, s) => const Text('b')),
    ],
  ),
];
''');
      await expectBuildError('DV-ROUTE-002', <String>[
        'DVRoutes.orders',
        'name:',
      ]);
    });

    test('DV-ROUTE-002: a config name taken by a page', () async {
      write('lib/routes.dart', '''
final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(path: '/home', name: 'index', builder: (c, s) => const Text('a')),
];
''');
      await expectBuildError('DV-ROUTE-002', <String>['DVRoutes.index']);
    });

    test('DV-ROUTE-003: a path that is not a plain literal', () async {
      write('lib/routes.dart', r'''
const String base = '/x';
final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(path: '$base/y', builder: (c, s) => const Text('a')),
];
''');
      await expectBuildError('DV-ROUTE-003', <String>['lib/routes.dart:3']);
    });

    test('DV-ROUTE-003: a spread the build cannot see into', () async {
      write('lib/routes.dart', '''
final List<DVRouteNode> more = <DVRouteNode>[];
final List<DVRouteNode> routes = <DVRouteNode>[...more];
''');
      await expectBuildError('DV-ROUTE-003', <String>['...more']);
    });

    test('DV-ROUTE-003: a child path written absolute', () async {
      write('lib/routes.dart', '''
final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(
    path: '/orders',
    builder: (c, s) => const Text('a'),
    routes: <DVRouteNode>[
      DVRoute(path: '/orders/:id', name: 'order', builder: (c, s) => const Text('b')),
    ],
  ),
];
''');
      await expectBuildError('DV-ROUTE-003', <String>["'/orders/:id'"]);
    });

    test('DV-ROUTE-003: a routes file with no top-level routes', () async {
      write('lib/routes.dart', 'final List<Object> other = <Object>[];\n');
      await expectBuildError('DV-ROUTE-003', <String>['routes']);
    });

    test(
      'DV-ROUTE-003: dartvel.routes naming a file that is not there',
      () async {
        write('pubspec.yaml', '$_pubspec  routes: lib/missing.dart\n');
        await expectBuildError('DV-ROUTE-003', <String>['lib/missing.dart']);
      },
    );

    test('DV-ROUTE-004: groups that cannot be ordered', () async {
      write('lib/routes.dart', '''
final List<DVRouteNode> routes = <DVRouteNode>[
  DVShellRoute(builder: (c, s, child) => child, routes: <DVRouteNode>[
    DVRoute(path: '/a/:x', name: 'ax', builder: (c, s) => const Text('a')),
    DVRoute(path: '/b/new', name: 'bnew', builder: (c, s) => const Text('b')),
  ]),
  DVShellRoute(builder: (c, s, child) => child, routes: <DVRouteNode>[
    DVRoute(path: '/a/new', name: 'anew', builder: (c, s) => const Text('c')),
    DVRoute(path: '/b/:x', name: 'bx', builder: (c, s) => const Text('d')),
  ]),
];
''');
      await expectBuildError('DV-ROUTE-004', <String>['/a/new', '/b/new']);
    });
  });
}
