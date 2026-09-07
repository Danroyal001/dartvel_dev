import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('backend generator accepts typed middleware constants', () async {
    final root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'pages', 'checkout.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.tenant, DVMiddlewares.rateLimit])
@DVPage()
void checkoutPage() {}
''');

      await _generate(root);

      expect(
        File(p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart'))
            .existsSync(),
        isTrue,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('backend generator rejects unsupported middleware constants', () async {
    final root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'order.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.notARealMiddleware])
Future<Map<String, bool>> handler() async => <String, bool>{'ok': true};
''');

      // Awaited: _generate is async, and the finally below deletes the
      // fixture the generator is still reading.
      await expectLater(
        () => _generate(root),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('DVMiddlewares.notARealMiddleware'),
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a declared middleware is wrapped around the route', () async {
    // The whole point. @DVUseMiddleware had one reader -- a spelling check
    // that threw the list away -- so this asserts on the generated router
    // rather than on the parser, which is the mistake this repository has
    // already made twice.
    final root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'order.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.securityHeaders, DVMiddlewares.rateLimit])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'ping.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<Map<String, bool>> ping() async => <String, bool>{'ok': true};
''');

      await _generate(root);

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();

      // Declaration order is preserved: a rate limit that runs before the
      // headers and one that runs after are different programs.
      expect(
        routes,
        contains("_dvGuarded(req, const <String>["
            "'securityHeaders', 'rateLimit'],"),
      );
      // And the chain has to be able to refuse and to decorate, or half of
      // it is still a comment.
      expect(routes, contains('core.dvRunMiddlewares('));
      expect(routes, contains('mw.headers.forEach(response.headers.set)'));

      // A route declaring nothing is not wrapped. Without this the test
      // would pass just as well if every route were guarded by an empty
      // list, which is a different bug wearing the same output.
      final pingAt = routes.indexOf("'/ping'");
      expect(pingAt, greaterThan(-1));
      final nextRoute = routes.indexOf('router.', pingAt);
      expect(
        routes.substring(pingAt, nextRoute == -1 ? routes.length : nextRoute),
        isNot(contains('_dvGuarded')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a middleware nothing implements fails the build and says why',
      () async {
    // rateLimitCheckout was accepted by the old whitelist and implemented
    // nowhere -- not even as a preset of rateLimit. The first test in this
    // file used to declare it and assert the build succeeded, which is
    // exactly the guarantee that was worth nothing.
    final root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'pay.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.rateLimitCheckout])
Future<Map<String, bool>> pay() async => <String, bool>{'ok': true};
''');

      await expectLater(
        () => _generate(root),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('DVMiddlewares.rateLimitCheckout'),
              contains('DVMiddlewares.rateLimit'),
            ),
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a redundant middleware is accepted rather than refused', () async {
    // CSRF is validated in the request prelude on every state-changing
    // method whether or not the key is declared, so declaring it is
    // redundant and not an error. Refusing it would make the honest
    // declaration the one that fails.
    final root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'note.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.csrf])
Future<Map<String, bool>> note() async => <String, bool>{'ok': true};
''');

      await _generate(root);

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
      expect(routes, contains('_dvValidateCsrf'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a route that declares a body limit checks before it reads', () async {
    // A limit that arrives after the read is not a limit, so the check
    // cannot live in the chain -- the chain runs around the handler and the
    // body is in memory by then. It is emitted where the reading happens,
    // and only for a route that asked.
    final root = await Directory.systemTemp.createTemp('dartvel_body_limit_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'note.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.bodyLimit])
Future<Map<String, bool>> note(String text) async => <String, bool>{'ok': true};
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'open.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<Map<String, bool>> open(String text) async => <String, bool>{'ok': true};
''');

      await _generate(root);

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();

      // The announced size is refused without reading a byte, and the read
      // itself is capped for a sender that announced nothing.
      expect(routes, contains('core.dvDeclaredTooLarge('));
      expect(routes, contains('core.dvReadCapped(req.body.stream'));
      expect(routes, contains('_dvTooLarge('));
      expect(routes, contains('dv.Response(413'));

      // A route that did not ask still reads the body the ordinary way. A
      // limit on every route would refuse the upload endpoint nobody
      // limited.
      final openAt = routes.indexOf("'/open'");
      expect(openAt, greaterThan(-1));
      final nextRoute = routes.indexOf('router.', openAt);
      expect(
        routes.substring(openAt, nextRoute == -1 ? routes.length : nextRoute),
        isNot(contains('dvReadCapped')),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('declaring both limits gives each shape its own number', () async {
    // Which is the point of there being two. A JSON body of several
    // megabytes is a mistake; an upload of several megabytes is the feature.
    final root = await Directory.systemTemp.createTemp('dartvel_both_limits_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'upload.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.bodyLimit, DVMiddlewares.uploadLimit])
Future<Map<String, bool>> upload(String name) async => <String, bool>{'ok': true};
''');

      await _generate(root);

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();

      expect(routes, contains('core.DVBodyLimits.upload'));
      expect(routes, contains('core.DVBodyLimits.body'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a declared tracing key wraps the whole handler', () async {
    // dvTraced existed, was tested, and was wired to nothing: the key named
    // it and the generator had never heard of either. It wraps rather than
    // joins the chain, and it wraps the chain too -- a request refused by a
    // rate limit is still a request, and a trace covering only the ones that
    // got through is a latency graph with the slow half missing.
    final root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'quote.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.tracing, DVMiddlewares.securityHeaders])
Future<Map<String, bool>> quote() async => <String, bool>{'ok': true};
''');

      await _generate(root);

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();

      expect(routes, contains('core.dvTraced(core.DVObservability.tracer'));
      // Outside the chain, not inside it.
      final traceAt = routes.indexOf('core.dvTraced(');
      final guardAt = routes.indexOf('_dvGuarded(', traceAt);
      expect(guardAt, greaterThan(traceAt));
      // And tracing is not handed to the chain, which has no middleware for
      // it and would refuse the request.
      expect(routes, isNot(contains("<String>['tracing'")));
      expect(routes, contains("<String>['securityHeaders']"));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('tracing on its own still closes its brackets', () async {
    // The wrappers nest, and the closing brackets are counted rather than
    // written out for each combination. A miscount is a generated file that
    // does not parse, reported against a line nobody wrote.
    final root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'ping.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.tracing])
Future<Map<String, bool>> ping() async => <String, bool>{'ok': true};
''');

      await _generate(root);

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();

      expect(routes, contains('core.dvTraced('));
      expect(routes, isNot(contains('_dvGuarded(')));
      // One wrapper: the closure's brace, dvTraced's bracket, the router's.
      expect(routes, contains('  }));'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

Future<Directory> _createProject() async {
  final root =
      await Directory.systemTemp.createTemp('dartvel_middleware_test_');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  return root;
}

Future<void> _generate(Directory root) {
  return BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'middleware_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
}
