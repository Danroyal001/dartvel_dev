import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'generated_router.dart';

void main() {
  test('every route runs inside the tenant the request named', () async {
    // Which middleware a route declared says nothing about whether its
    // handler reads a tenant-scoped model. Only the routes that listed
    // DVMiddlewares.tenant had the tenant made current, and that was done by
    // writing a process-wide field -- so a handler on any other route read
    // whichever tenant the last request to arrive happened to be for, and
    // returned that tenant's rows to this caller.
    //
    // Asserted per route rather than over the file, because the helper is
    // emitted into every generated router whether a route calls it or not.
    final Directory root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'order.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.securityHeaders])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'ping.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<Map<String, bool>> ping() async => <String, bool>{'ok': true};
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

      for (final String path in const <String>['/order', '/ping', '/feed']) {
        expect(
          dvRouteSource(routes, path),
          contains('core.dvWithRequestTenant(req,'),
          reason: '$path runs its handler outside any tenant scope',
        );
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('the tenant scope is outside the middleware chain', () async {
    // The chain is async too. A tenant read inside it -- the locale
    // middleware asking for this tenant's default language -- has the same
    // problem the handler had, so the scope has to be open before the chain
    // starts rather than only around what follows it.
    final Directory root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'order.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.tenant, DVMiddlewares.locale])
Future<Map<String, bool>> order() async => <String, bool>{'ok': true};
''');

      await _generate(root);

      final String route = dvRouteSource(
        File(
          p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
        ).readAsStringSync(),
        '/order',
      );

      final int scope = route.indexOf('core.dvWithRequestTenant(req,');
      final int chain = route.indexOf('_dvGuarded(req,');
      // Both looked up rather than compared straight: a missing scope is
      // an index of -1, which is less than everything, so the ordering
      // assertion on its own passes for a route that has no scope at all.
      expect(scope, isNonNegative);
      expect(chain, isNonNegative);
      expect(scope, lessThan(chain));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('the router the wrappers build still parses', () async {
    // Each wrapper around a handler adds a closing bracket counted
    // somewhere else, and getting that count wrong produces a generated
    // file that does not compile with an error naming a line nobody wrote.
    // Every combination in one project: traced, chained, both, neither,
    // and a raw handler.
    final Directory root = await _createProject();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'plain.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<Map<String, bool>> plain() async => <String, bool>{'ok': true};
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'traced.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.tracing])
Future<Map<String, bool>> traced() async => <String, bool>{'ok': true};
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'chained.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.securityHeaders])
Future<Map<String, bool>> chained() async => <String, bool>{'ok': true};
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'both.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVUseMiddleware([DVMiddlewares.tracing, DVMiddlewares.securityHeaders])
Future<Map<String, bool>> both() async => <String, bool>{'ok': true};
''');
      File(p.join(root.path, 'lib', 'backend', 'functions', 'raw.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;

Future<dv.Response> handler(dv.Request req) async => dv.Response.text('ok');
''');

      await _generate(root);

      final String routerPath =
          p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart');
      // The formatter parses and never resolves, so this says the brackets
      // balance without needing the generated file's imports to exist.
      final ProcessResult parsed = Process.runSync(
        Platform.resolvedExecutable,
        <String>['format', '--output=none', routerPath],
      );

      expect(
        parsed.exitCode,
        0,
        reason: 'the generated router does not parse:\n${parsed.stderr}',
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

Future<Directory> _createProject() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_tenant_scope_test_');
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
    pkgName: 'tenant_scope_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
}
