// dartvel.auth.pages read by the router generator: the routes the prebuilt
// account pages are served at, and the entries an application places.
//
// DV.Auth.SecurityPage, SessionsPage, ProfilePage, DeletePage and SignUpPage
// existed with nowhere to open them: an application wrote a page file per
// account page, and a file without a guard served the security page to
// somebody signed out. How the gate behaves in a router is dartvel_flutter's
// account_page_routes_test; the whole generated client compiling is
// generated_client_analyzes_test's. This pins the connections only the
// generator makes, and the refusals of a pubspec it cannot honour.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<Directory> _generate(
  Map<String, String> pages, {
  Object? auth,
}) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_account_routes_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  pages.forEach((String name, String source) {
    File(p.join(root.path, 'lib', 'pages', name))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'bank_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Bank',
    seoTitle: 'Bank',
    seoDesc: 'Bank',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: loadYaml(auth == null ? '{}' : 'auth:\n  pages: $auth\n') as YamlMap,
  );
  return root;
}

String _page(String name, String annotation) => '''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

$annotation
Widget ${name}Page(BuildContext context) => const SizedBox.shrink();
''';

String _router(Directory root) =>
    File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
        .readAsStringSync();

/// The route block for [path] in the generated router.
String _route(String router, String path) {
  final int at = router.indexOf("path: '$path'");
  expect(at, isNot(-1), reason: 'no route for $path');
  // The end of the route list, which is its own function now.
  final int list = router.indexOf('\n    ]);', at);
  final int next = router.indexOf('GoRoute(', at);
  final int end = next == -1 || (list != -1 && list < next) ? list : next;
  return router.substring(at, end == -1 ? router.length : end);
}

/// The generated navigation entries, as `page path` pairs.
List<String> _entries(String router) {
  final int at = router.indexOf('dartvelAccountPages');
  expect(at, isNot(-1), reason: 'no dartvelAccountPages');
  final int end = router.indexOf('];', at);
  return <String>[
    for (final RegExpMatch m in RegExp(
      r"DVAccountPageEntry\(DVAccountPage\.(\w+), DVRouteTarget\('([^']*)'\)\)",
    ).allMatches(router.substring(at, end)))
      '${m.group(1)} ${m.group(2)}',
  ];
}

List<String> _guarded(String router) {
  final int at = router.indexOf('dartvelGuardedRoutes');
  final int end = router.indexOf(';', at);
  return <String>[
    for (final RegExpMatch m
        in RegExp(r"'([^']*)'").allMatches(router.substring(at, end)))
      m.group(1)!,
  ];
}

const String _gate = 'DVAccountPages.requireSession(context, state)';

void main() {
  test('with nothing declared, every account page is served, behind sign-in '
      'but sign-up, and listed for navigation', () async {
    final String router = _router(await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
    }));
    final Map<String, String> pages = <String, String>{
      '/account/profile': 'DV.Auth.ProfilePage()',
      '/account/security': 'DV.Auth.SecurityPage()',
      '/account/sessions': 'DV.Auth.SessionsPage()',
      '/account/delete': 'DV.Auth.DeletePage()',
    };
    pages.forEach((String path, String widget) {
      expect(_route(router, path), contains(_gate), reason: path);
      expect(_route(router, path), contains(widget), reason: path);
    });
    expect(_route(router, '/sign-up'), contains('DV.Auth.SignUpPage()'));
    expect(_route(router, '/sign-up'), isNot(contains('redirect')));
    // Where the gate sends somebody signed out, so it lands on a page: an
    // application with no sign-in page of its own sent them to not-found.
    expect(_route(router, '/login'),
        contains("DV.Auth.SignInWithEmailAndPasswordPage(from: state.uri.queryParameters['from'])"));
    expect(_route(router, '/login'), isNot(contains('redirect')));
    expect(router, contains("dvSignInRoute = '/login';"));
    expect(_route(router, '/'), isNot(contains(_gate)));
    expect(_entries(router), <String>[
      'profile /account/profile',
      'security /account/security',
      'sessions /account/sessions',
      'delete /account/delete',
      'signUp /sign-up',
      'signIn /login',
    ]);
    expect(_guarded(router), containsAll(pages.keys));
    expect(_guarded(router), isNot(contains('/sign-up')));
  });

  test('a configured path moves the route and its entry, and false leaves a '
      'page out', () async {
    final String router = _router(await _generate(
      <String, String>{'index.dart': _page('home', '@DVPage()')},
      auth: '{security: /settings/security, delete: false, signUp: /join, signIn: /enter}',
    ));
    expect(_route(router, '/settings/security'), contains(_gate));
    expect(router, isNot(contains("path: '/account/security'")));
    expect(router, isNot(contains('DV.Auth.DeletePage()')));
    expect(_route(router, '/join'), contains('DV.Auth.SignUpPage()'));
    expect(_route(router, '/enter'), contains('DV.Auth.SignInWithEmailAndPasswordPage('));
    expect(router, contains("dvSignInRoute = '/enter';"));
    expect(router, isNot(contains("path: '/login'")));
    expect(_entries(router), <String>[
      'profile /account/profile',
      'security /settings/security',
      'sessions /account/sessions',
      'signUp /join',
      'signIn /enter',
    ]);
  });

  test('pages: false serves none of them', () async {
    final String router = _router(await _generate(
      <String, String>{'index.dart': _page('home', '@DVPage()')},
      auth: 'false',
    ));
    for (final String widget in <String>[
      'ProfilePage',
      'SecurityPage',
      'SessionsPage',
      'DeletePage',
      'SignUpPage',
      'SignInWithEmailAndPasswordPage',
    ]) {
      expect(router, isNot(contains('DV.Auth.$widget(')));
    }
    expect(_entries(router), isEmpty);
    expect(router, isNot(contains('dvSignInRoute =')));
  });

  test('a page the application put at the same path is the application\'s',
      () async {
    final String router = _router(await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
      'account/profile.dart': _page('profile', '@DVPage()'),
    }));
    final String routeList = router.substring(
        router.indexOf('_dartvelRouteList() => dvOrderGoRoutes('),
        router.indexOf('redirect: _globalRedirect'));
    expect(RegExp("path: '/account/profile'").allMatches(routeList), hasLength(1));
    expect(router, isNot(contains('DV.Auth.ProfilePage()')));
    expect(_entries(router), contains('profile /account/profile'));
  });

  test('an application with its own sign-in page keeps it, and the gate sends '
      'people there', () async {
    final String router = _router(await _generate(<String, String>{
      'index.dart': _page('home', '@DVPage()'),
      'login.dart': _page('login', '@DVPage()'),
    }));
    expect(router, isNot(contains('DV.Auth.SignInWithEmailAndPasswordPage(')));
    expect(router, contains("dvSignInRoute = '/login';"));
  });

  group('a declaration the generator cannot honour stops the build, naming the '
      'key', () {
    final Map<String, String> refused = <String, String>{
      '{secruity: /settings}': 'dartvel.auth.pages.secruity',
      '{security: settings/security}': 'dartvel.auth.pages.security',
      '{security: true}': 'dartvel.auth.pages.security',
      '{profile: "/users/:id"}': 'dartvel.auth.pages.profile',
      '{profile: /me, security: /me}': '/me',
      '{signUp: /second-factor}': 'dartvel.auth.pages.signUp',
      'yes': 'dartvel.auth.pages',
    };
    refused.forEach((String declared, String named) {
      test(declared, () async {
        await expectLater(
          _generate(<String, String>{'index.dart': _page('home', '@DVPage()')},
              auth: declared),
          throwsA(isA<StateError>()
              .having((StateError e) => e.message, 'message', contains(named))),
        );
      });
    });
  });

  test('dartvel routes refuses one before writing anything', () async {
    final Directory root =
        await Directory.systemTemp.createTemp('dartvel_account_routes_cli_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: refused_pages
environment:
  sdk: ^3.12.0
dartvel:
  auth:
    pages:
      secruity: /settings/security
''');
    final String cli = p.normalize(p.join(Directory.current.path, 'bin', 'routes.dart'));
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(Directory.current.path, '.dart_tool', 'package_config.json')}',
        cli,
      ],
      workingDirectory: root.path,
    );
    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect('${result.stdout}${result.stderr}', contains('dartvel.auth.pages.secruity'));
    expect(Directory(p.join(root.path, 'lib', 'dartvel_client')).existsSync(), isFalse);
  });
}
