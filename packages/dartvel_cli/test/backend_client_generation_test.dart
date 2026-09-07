import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('backend client generation emits strongly typed wrappers', () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_backend_client_test_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'task.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, Object?>> handler(String title, int priority) async {
  return <String, Object?>{
    'title': title,
    'priority': priority,
  };
}
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'backend_client_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final content =
          File(p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart'))
              .readAsStringSync();
      expect(content, contains('Map<String, Object?>? query'));
      expect(content, contains('final fb = <String, Object?>{};'));
      expect(content, contains('const <String, Object?>{}'));
      expect(content, contains('String routePath = '));
      // The client sends through Dartvel's own transport; a generated client
      // that pulled in a third-party HTTP package made every app depend on it.
      expect(content, contains('dvSendHttpRequest('));
      expect(content, contains('dvStreamHttpRequest('));
      expect(content, isNot(contains('package:dio')));
      expect(content, contains('final hdrs = _dvPrepareHeaders('));
      expect(content, contains("String buffer = '';"));
      expect(content, contains('Map<String, Object?>.from'));
      expect(content, isNot(contains('Map<String, dynamic>')));
      expect(content, isNot(contains('<String, dynamic>')));
      expect(content, isNot(contains('<String,Object?>')));
      expect(content, isNot(contains('payload as dynamic')));
      expect(content, isNot(contains('var routePath')));
      expect(content, isNot(contains('var hdrs')));
      expect(content, isNot(contains('var send')));
      expect(content, isNot(contains('var buffer')));

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
      expect(routes, isNot(contains('Map<String, dynamic>')));
      expect(routes, isNot(contains('<String, dynamic>')));
      expect(routes, contains('f0.handler('));
      expect(routes, isNot(contains('f0._handler(')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('private expression-bodied backend functions generate route helpers',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_backend_private_test_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'task.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
@pragma('vm:entry-point')
Future<String> _handler(String input) async => buildResponse(input);

Future<String> buildResponse(String input) async => 'ok \$input';
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'backend_client_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
      final functions = File(
        p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart'),
      ).readAsStringSync();

      expect(
        routes,
        contains(
          'import \'package:backend_client_app/backend/functions/task.post.dart\' as f0;',
        ),
      );
      expect(
        routes,
        // `async` is kept. Dropping it, as this once asserted, breaks any
        // body whose expression is not already a Future.
        contains(
          '_dvBackendFn0(String input) async => f0.buildResponse(input);',
        ),
      );
      expect(routes, contains('Object? result = await _dvBackendFn0('));
      expect(routes, isNot(contains('f0._handler(')));
      expect(functions, contains('Future<String> handler('));
      expect(functions, isNot(contains('_handler(')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('private block-bodied backend functions are lowered into the route',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_backend_private_test_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'task.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _handler(String input) async {
  return 'ok \$input';
}
''');

      // This used to assert the generator refused a block body. That
      // restriction is gone, so it asserts what replaced it.
      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'backend_client_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
      expect(routes, contains(r"return 'ok $input';"));
      expect(routes, isNot(contains('f0._handler(')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a backend function taking a DVContext is given one', () async {
    // The public API rules say a backend function whose first parameter is a
    // DVContext receives it by injection and it is not a client-supplied
    // argument. The generator had never heard of DVContext -- the string
    // appears nowhere in the CLI -- so the parameter was treated as an
    // ordinary argument decoded from the request. The client got to supply
    // it, and context.lifecycle.request threw for want of a signal nothing
    // ever built.
    final root = await Directory.systemTemp.createTemp('dartvel_ctx_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'pay.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<Map<String, bool>> handler(DVContext context, String orderId) async =>
    <String, bool>{'ok': true};
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'ctx_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();

      // Injected, and first.
      expect(routes, contains('core.DVContext('));
      expect(routes, contains('requestLifecycle:'));
      // The request lifecycle has to change, or it is an enum that reports
      // one value forever.
      expect(routes, contains('DVRequestLifecycle.executing'));
      expect(routes, contains('DVRequestLifecycle.failed'));

      // And the client must not be asked for it. A context decoded from the
      // request body is the opposite of an injected one.
      final client = File(
        p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart'),
      ).readAsStringSync();
      expect(client, contains('orderId'));
      expect(client, isNot(contains('DVContext')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a function taking no context is unchanged', () async {
    // Without this the test above would pass just as well if every handler
    // built a context it never used, which is a cost on every request for
    // the functions that did not ask.
    final root = await Directory.systemTemp.createTemp('dartvel_noctx_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'ping.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<Map<String, bool>> handler(String id) async => <String, bool>{'ok': true};
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'noctx_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
      expect(routes, isNot(contains('core.DVContext(')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
