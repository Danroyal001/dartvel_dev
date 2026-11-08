// Every route runs inside the request's metering scope, whether or not it
// asked to.
//
// A handler that records a meter with no scope around it has no key to
// deduplicate by and throws -- or, if somebody "fixes" that with a fresh id,
// counts every retry. So the scope is asserted per route rather than left to
// whichever routes remembered it.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'generated_router.dart';

void main() {
  test('every route runs inside the request metering scope', () async {
    final Directory root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'order.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'feed.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;

Future<dv.Response> handler(dv.Request req) async => dv.Response.text('ok');
''');

      await _generate(root);

      final String routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();

      for (final String path in const <String>['/order', '/feed']) {
        expect(
          dvRouteSource(routes, path),
          contains('core.dvWithRequestMeterKey(req,'),
          reason: '$path records usage with no request key',
        );
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('the scope is open before the route middleware runs', () async {
    // A route's middleware can meter too (an API key's usage is recorded in
    // the chain), and it has to record under this request's key.
    final Directory root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'order.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.securityHeaders])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

      await _generate(root);

      final String route = dvRouteSource(
        File(
          p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
        ).readAsStringSync(),
        '/order',
      );

      final int scope = route.indexOf('core.dvWithRequestMeterKey(req,');
      final int chain = route.indexOf('_dvGuarded(req,');
      // Both looked up rather than compared straight: a missing scope is an
      // index of -1, which is less than everything, so an ordering assertion
      // on its own passes for a route that has no scope at all.
      expect(scope, isNonNegative);
      expect(chain, isNonNegative);
      expect(scope, lessThan(chain));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('the routes that are not backend functions get it too', () async {
    // GraphQL, the crash endpoint, OpenAPI and health go through one staging
    // helper rather than the layer list, and each of them was registered bare
    // once already.
    final Directory root = await _createProject();
    try {
      await _generate(root);

      final String routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
      final int staged = routes.indexOf('Future<dv.Response> _dvStaged(');
      expect(staged, isNonNegative);

      final String body = routes.substring(staged, staged + 400);
      expect(body, contains('core.dvWithRequestMeterKey(req,'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

Future<Directory> _createProject() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_meter_scope_test_');
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
    pkgName: 'meter_scope_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
}
