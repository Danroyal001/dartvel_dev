// A page's declared middleware reaches the router it was declared for.
//
// NEW_SPEC.md opens the Middleware section with the page form:
//
//     @DVUseMiddleware([DVMiddlewares.auth, ...])
//     @DVPage()
//     Widget _checkoutPage(BuildContext context) => Checkout.Page();
//
// and the router generator had never heard of the annotation. The only
// reader anywhere was the backend generator's spelling check, which walks
// every file under lib/ and so did validate the names on a page -- against
// the sets written for an HTTP chain. So a page declaring auth got a green
// build, a whitelisted key, and a route anybody could open.
//
// These assert on the generated router rather than on the parser. A correct
// parser with nothing calling it is the mistake this repository has already
// made twice, most recently with @DVPage(policy:).
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'generated_router.dart';

Future<String> _routerFor(Directory root) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'middleware_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Middleware App',
    seoTitle: 'Middleware App',
    seoDesc: 'Middleware App',
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
    dv: YamlMap.wrap(<String, Object?>{}),
  );
  return File(
    p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
  ).readAsStringSync();
}

Future<Directory> _project() async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dartvel_page_middleware_',
  );
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  return root;
}

void _page(Directory root, String name, String source) {
  File(p.join(root.path, 'lib', 'pages', name)).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

$source
''');
}

void main() {
  test('a page declaring middleware gets a route that runs it', () async {
    final Directory root = await _project();
    try {
      _page(root, 'checkout.dart', '''
@DVUseMiddleware([DVMiddlewares.auth])
@DVPage()
Widget checkoutPage(BuildContext context) => const SizedBox.shrink();
''');

      final String routes = await _routerFor(root);
      final String checkout = dvPageRouteSource(routes, '/checkout');

      expect(checkout, contains('redirect:'));
      expect(checkout, contains('DVPageMiddleware.check'));
      expect(checkout, contains("'auth'"));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a page declaring none carries no redirect at all', () async {
    // Without this the suite would pass just as well if every route ran an
    // empty middleware list, which is a different bug wearing this output.
    final Directory root = await _project();
    try {
      _page(root, 'about.dart', '''
@DVPage()
Widget aboutPage(BuildContext context) => const SizedBox.shrink();
''');

      expect(
        dvPageRouteSource(await _routerFor(root), '/about'),
        isNot(contains('redirect:')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('the declared order survives into the router', () async {
    // A maintenance check behind an auth check sends a signed-out visitor to
    // sign in to an application that is not serving anybody. The two orders
    // are different programs, so the list cannot be a set.
    final Directory root = await _project();
    try {
      _page(root, 'checkout.dart', '''
@DVUseMiddleware([DVMiddlewares.maintenance, DVMiddlewares.auth])
@DVPage()
Widget checkoutPage(BuildContext context) => const SizedBox.shrink();
''');

      expect(
        dvPageRouteSource(await _routerFor(root), '/checkout'),
        contains("<String>['maintenance', 'auth']"),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a page with middleware and a policy runs both, middleware first',
      () async {
    // Neither replaces the other. Middleware is the coarser check and runs
    // first, the way the backend chain wraps the policy gate: refusing a
    // signed-out visitor before asking an authorization surface who they
    // are saves the question, and asking it first would answer for a
    // visitor the application already knows nothing about.
    final Directory root = await _project();
    try {
      _page(root, 'admin.dart', '''
@DVUseMiddleware([DVMiddlewares.auth])
@DVPage(policy: DVPolicies.viewAdmin)
Widget adminPage(BuildContext context) => const SizedBox.shrink();
''');

      final String admin = dvPageRouteSource(await _routerFor(root), '/admin');

      expect(admin, contains('DVPageMiddleware.check'));
      expect(admin, contains('DVPagePolicy.check'));
      expect(
        admin.indexOf('DVPageMiddleware.check'),
        lessThan(admin.indexOf('DVPagePolicy.check')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a folder guard is not dropped by a page declaring middleware',
      () async {
    // The failure this shape invites: a page moved under a guarded folder,
    // carrying middleware of its own, quietly losing the folder's guard.
    final Directory root = await _project();
    try {
      Directory(p.join(root.path, 'lib', 'pages', 'admin'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'pages', 'admin', '_guard.dart'))
          .writeAsStringSync('''
import 'package:flutter/widgets.dart';

class AdminGuard {
  static Future<String?> guard(BuildContext context, Object? state) async =>
      null;
}
''');
      File(p.join(root.path, 'lib', 'pages', 'admin', 'users.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVUseMiddleware([DVMiddlewares.auth])
@DVPage()
Widget usersPage(BuildContext context) => const SizedBox.shrink();
''');

      final String users =
          dvPageRouteSource(await _routerFor(root), '/admin/users');

      // The guard is imported under a generated alias, so the call is what
      // there is to assert on. Its presence is the point: the folder's guard
      // still runs for a page that declared middleware of its own.
      expect(users, contains('.guard(context, state)'));
      expect(users, contains('DVPageMiddleware.check'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('the auth key is told who this application considers signed in',
      () async {
    // Without this the hook is null, and null default-denies -- so every
    // page declaring auth would be closed to everybody, including the
    // people who had just signed in. A guard that refuses the whole
    // application is not safer than one that works; it is a feature nobody
    // can use, which is how it stays broken.
    //
    // Assigned with ??= so an application that wired its own answer first
    // keeps it.
    final Directory root = await _project();
    try {
      _page(root, 'checkout.dart', '''
@DVUseMiddleware([DVMiddlewares.auth])
@DVPage()
Widget checkoutPage(BuildContext context) => const SizedBox.shrink();
''');

      final String routes = await _routerFor(root);

      expect(routes, contains('DVPageMiddleware.isSignedIn ??='));
      expect(routes, contains('DV.Auth.currentUser'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('an application with no page declaring auth is wired to nothing',
      () async {
    // The control. Installing the resolver unconditionally would make every
    // router touch DV.Auth, including applications that have no auth at all.
    final Directory root = await _project();
    try {
      _page(root, 'about.dart', '''
@DVPage()
Widget aboutPage(BuildContext context) => const SizedBox.shrink();
''');

      expect(
        await _routerFor(root),
        isNot(contains('DVPageMiddleware.isSignedIn')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a page behind middleware is kept out of the sitemap', () async {
    // NEW_SPEC.md: authenticated routes are excluded by default. The
    // guarded list is how the sitemap writer learns which those are, and it
    // was built from the directory guards and the policy only -- so a page
    // whose only guard was declared middleware was published to crawlers.
    final Directory root = await _project();
    try {
      _page(root, 'checkout.dart', '''
@DVUseMiddleware([DVMiddlewares.auth])
@DVPage()
Widget checkoutPage(BuildContext context) => const SizedBox.shrink();
''');
      _page(root, 'about.dart', '''
@DVPage()
Widget aboutPage(BuildContext context) => const SizedBox.shrink();
''');

      final String routes = await _routerFor(root);

      expect(dvGuardedRoutes(routes), contains('/checkout'));
      expect(dvGuardedRoutes(routes), isNot(contains('/about')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
