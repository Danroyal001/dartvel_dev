// Middleware declared on the annotation itself:
//
//     @DVBackendFunction(middleware: [DVMiddlewares.rateLimit])
//     @DVPage(title: 'Account', middleware: [DVMiddlewares.auth])
//
// is the same declaration `@DVUseMiddleware([...])` was, written where the
// route is declared. Every test here generates a project and reads what was
// generated, and the comparisons are against the deprecated form run through
// the same generator: a field that parsed and was then dropped would leave a
// route with no chain at all, which is the failure this repository has
// already shipped twice.
import 'dart:io';

import 'package:dartvel_cli/src/build/static_seo.dart';
import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'generated_router.dart';

void main() {
  group('backend function', _backendTests);
  group('page', _pageTests);
  group('both forms on one declaration', _mergeTests);
}

void _backendTests() {
  test('middleware: generates the chain @DVUseMiddleware generates', () async {
    final String viaField = await _backendRoute('''
@DVBackendFunction(middleware: [DVMiddlewares.securityHeaders, DVMiddlewares.rateLimit])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');
    final String viaAnnotation = await _backendRoute('''
@DVUseMiddleware([DVMiddlewares.securityHeaders, DVMiddlewares.rateLimit])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

    // The chain itself, in declaration order, and not an empty one.
    expect(
      viaField,
      contains(
        "_dvGuarded(req, const <String>['securityHeaders', 'rateLimit'],",
      ),
    );
    // And the whole route, not only the line this test thought to look at.
    expect(viaField, viaAnnotation);
  });

  test('a typed const list beside other arguments is read', () async {
    // The shapes a formatter and a careful author produce: a type argument,
    // `const`, a trailing comma, and an argument after the list. The reader
    // that wanted `[` straight after `(` lost the first of these once.
    final String route = await _backendRoute('''
@DVBackendFunction(
  middleware: const <DVMiddlewareKey>[
    DVMiddlewares.auth,
    DVMiddlewares.rateLimit,
  ],
  aiTool: DVAITool(description: 'Orders (all of them)'),
)
Future<List<String>> order() async => <String>['2026-08'];
''');

    expect(
      route,
      contains("_dvGuarded(req, const <String>['auth', 'rateLimit'],"),
    );
  });

  test('an unknown key fails the build with the same reason', () async {
    final String viaField = await _backendRefusal('''
@DVBackendFunction(middleware: [DVMiddlewares.auth, DVMiddlewares.notARealMiddleware])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');
    final String viaAnnotation = await _backendRefusal('''
@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.notARealMiddleware])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

    expect(viaField, contains('DVMiddlewares.notARealMiddleware'));
    expect(viaField, viaAnnotation);
  });

  test(
    'a key nothing implements fails the build with the same reason',
    () async {
      final String viaField = await _backendRefusal('''
@DVBackendFunction(middleware: [DVMiddlewares.rateLimitCheckout])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');
      final String viaAnnotation = await _backendRefusal('''
@DVUseMiddleware([DVMiddlewares.rateLimitCheckout])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

      expect(viaField, contains('not implemented'));
      expect(viaField, viaAnnotation);
    },
  );

  test(
    'a list the build cannot read fails rather than guarding nothing',
    () async {
      // A variable is legal Dart and a perfectly good constant, and the build
      // reads source: it cannot see what `_chain` holds. Serving the route
      // unguarded while its author believes it is limited is the one answer
      // that is never right.
      final String message = await _backendRefusal('''
const List<DVMiddlewareKey> _chain = <DVMiddlewareKey>[DVMiddlewares.rateLimit];

@DVBackendFunction(middleware: _chain)
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

      expect(message, contains('middleware:'));
      expect(message, contains('DVMiddlewares'));
    },
  );

  test('the deprecated annotation alone still builds the chain', () async {
    final String route = await _backendRoute('''
@DVBackendFunction()
@DVUseMiddleware([DVMiddlewares.requestLogging, DVMiddlewares.rateLimit])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

    expect(
      route,
      contains(
        "_dvGuarded(req, const <String>['requestLogging', 'rateLimit'],",
      ),
    );
  });
}

void _pageTests() {
  test(
    'middleware: reaches the router the way @DVUseMiddleware does',
    () async {
      final String viaField = await _pageRoute('''
@DVPage(title: 'Account', middleware: [DVMiddlewares.maintenance, DVMiddlewares.auth])
Widget accountPage(BuildContext context) => const SizedBox.shrink();
''');
      final String viaAnnotation = await _pageRoute('''
@DVUseMiddleware([DVMiddlewares.maintenance, DVMiddlewares.auth])
@DVPage(title: 'Account')
Widget accountPage(BuildContext context) => const SizedBox.shrink();
''');

      expect(viaField, contains('DVPageMiddleware.check'));
      expect(viaField, contains("<String>['maintenance', 'auth']"));
      expect(viaField, viaAnnotation);
    },
  );

  test('a page guarded only by its field is kept out of the sitemap', () async {
    final Directory root = await _project();
    try {
      _write(root, 'lib/pages/account.dart', _pageImports, '''
@DVPage(title: 'Account', middleware: [DVMiddlewares.auth])
Widget accountPage(BuildContext context) => const SizedBox.shrink();
''');
      final String routes = await _router(root);
      expect(dvGuardedRoutes(routes), contains('/account'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'a key a page cannot run fails the build with the same reason',
    () async {
      final String viaField = await _pageRefusal('''
@DVPage(title: 'Upload', middleware: [DVMiddlewares.bodyLimit])
void uploadPage() {}
''');
      final String viaAnnotation = await _pageRefusal('''
@DVUseMiddleware([DVMiddlewares.bodyLimit])
@DVPage(title: 'Upload')
void uploadPage() {}
''');

      expect(viaField, contains('cannot be page middleware'));
      expect(viaField, contains('@DVBackendFunction'));
      expect(viaField, viaAnnotation);
    },
  );

  test('a page field is judged as a page even outside lib/pages', () async {
    // rateLimit is fine on a backend function and refused on a page, so this
    // is the key that tells the two scopes apart.
    final Directory root = await _project();
    try {
      _write(root, 'lib/checkout_page.dart', _coreImport, '''
@DVPage(middleware: [DVMiddlewares.rateLimit])
void checkoutPage() {}
''');
      final String message = await _refusal(() => _backend(root));
      expect(message, contains('DVMiddlewares.rateLimit'));
      expect(message, contains('cannot be page middleware'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a page and a function in one file are judged one at a time', () async {
    final Directory root = await _project();
    try {
      _write(root, 'lib/mixed.dart', _coreImport, '''
@DVPage(middleware: [DVMiddlewares.auth])
void checkoutPage() {}

@DVBackendFunction(middleware: [DVMiddlewares.bodyLimit])
Future<Map<String, bool>> up() async => <String, bool>{'ok': true};
''');
      await _backend(root);
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

void _mergeTests() {
  test('the two lists run as one, the field first, each key once', () async {
    final String route = await _backendRoute('''
@DVBackendFunction(middleware: [DVMiddlewares.securityHeaders, DVMiddlewares.rateLimit])
@DVUseMiddleware([DVMiddlewares.rateLimit, DVMiddlewares.requestLogging])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

    expect(
      route,
      contains(
        "_dvGuarded(req, const <String>["
        "'securityHeaders', 'rateLimit', 'requestLogging'],",
      ),
    );
  });

  test('which annotation is written first does not change the order', () async {
    final String route = await _backendRoute('''
@DVUseMiddleware([DVMiddlewares.requestLogging])
@DVBackendFunction(middleware: [DVMiddlewares.securityHeaders])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

    expect(
      route,
      contains(
        "_dvGuarded(req, const <String>['securityHeaders', 'requestLogging'],",
      ),
    );
  });

  test('a page merges the same way', () async {
    final String route = await _pageRoute('''
@DVUseMiddleware([DVMiddlewares.auth])
@DVPage(middleware: [DVMiddlewares.maintenance, DVMiddlewares.auth])
Widget accountPage(BuildContext context) => const SizedBox.shrink();
''');

    expect(route, contains("<String>['maintenance', 'auth']"));
  });

  test('the same keys in opposite orders fail the build', () async {
    // A rate limit before the headers and one after are different programs,
    // and the source says both. Picking one would be a guess about which the
    // author meant.
    final String message = await _backendRefusal('''
@DVBackendFunction(middleware: [DVMiddlewares.securityHeaders, DVMiddlewares.rateLimit])
@DVUseMiddleware([DVMiddlewares.rateLimit, DVMiddlewares.securityHeaders])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

    expect(message, contains('lib/backend/functions/order.post.dart'));
    expect(message, contains('DVMiddlewares.securityHeaders'));
    expect(message, contains('DVMiddlewares.rateLimit'));
    expect(message, contains('@DVUseMiddleware'));
  });

  test('a page key refused in either list fails the merged page', () async {
    final String message = await _pageRefusal('''
@DVUseMiddleware([DVMiddlewares.csrf])
@DVPage(middleware: [DVMiddlewares.auth])
void accountPage() {}
''');

    expect(message, contains('DVMiddlewares.csrf'));
  });
}

const String _coreImport = "import 'package:dartvel_core/dartvel.dart';";
const String _pageImports =
    "import 'package:dartvel_core/dartvel.dart';\n"
    "import 'package:flutter/widgets.dart';";

/// The `/order` route of a project whose only function is [declaration].
Future<String> _backendRoute(String declaration) async {
  final Directory root = await _project();
  try {
    _write(
      root,
      'lib/backend/functions/order.post.dart',
      _coreImport,
      declaration,
    );
    await _backend(root);
    final String routes = File(
      p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
    ).readAsStringSync();
    return dvRouteSource(routes, '/order');
  } finally {
    root.deleteSync(recursive: true);
  }
}

Future<String> _backendRefusal(String declaration) async {
  final Directory root = await _project();
  try {
    _write(
      root,
      'lib/backend/functions/order.post.dart',
      _coreImport,
      declaration,
    );
    return await _refusal(() => _backend(root));
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// The `/account` route of a project whose only page is [declaration].
Future<String> _pageRoute(String declaration) async {
  final Directory root = await _project();
  try {
    _write(root, 'lib/pages/account.dart', _pageImports, declaration);
    return dvPageRouteSource(await _router(root), '/account');
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Pages are validated by the backend generator, which walks every file
/// under lib/ -- the router generator only reads what passed.
Future<String> _pageRefusal(String declaration) async {
  final Directory root = await _project();
  try {
    _write(root, 'lib/pages/upload.dart', _coreImport, declaration);
    return await _refusal(() => _backend(root));
  } finally {
    root.deleteSync(recursive: true);
  }
}

Future<String> _refusal(Future<void> Function() build) async {
  try {
    await build();
  } on StateError catch (error) {
    return error.message;
  }
  fail('the build succeeded and was expected to refuse');
}

void _write(Directory root, String rel, String imports, String body) {
  final File file = File(p.joinAll(<String>[root.path, ...rel.split('/')]));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$imports\n\n$body');
}

Future<Directory> _project() async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dartvel_middleware_field_',
  );
  Directory(p.join(root.path, '.dart_tool')).createSync();
  for (final String dir in <String>[
    'lib/dartvel_client',
    'lib/backend/functions',
    'lib/pages',
  ]) {
    Directory(p.joinAll(<String>[root.path, ...dir.split('/')]))
        .createSync(recursive: true);
  }
  return root;
}

Future<void> _backend(Directory root) => BackendGenerator.generate(
  root: root.path,
  backendDir: 'lib/backend',
  pkgName: 'middleware_app',
  buildId: 'test-build',
  backendHost: '127.0.0.1',
  backendPort: 3000,
  apiBasePath: '/api',
);

Future<String> _router(Directory root) async {
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
    ota: false,
    dv: YamlMap.wrap(<String, Object?>{}),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
      .readAsStringSync();
}
