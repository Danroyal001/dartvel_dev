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
      expect(content, contains('Map<String, String> hdrs = '));
      expect(content, contains('Object? send = '));
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
        contains('_dvBackendFn0(String input) => f0.buildResponse(input);'),
      );
      expect(routes, contains('Object? result = await _dvBackendFn0('));
      expect(routes, isNot(contains('f0._handler(')));
      expect(functions, contains('Future<String> handler('));
      expect(functions, isNot(contains('_handler(')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('private block-bodied backend functions require body lowering',
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

      await expectLater(
        BackendGenerator.generate(
          root: root.path,
          backendDir: 'lib/backend',
          pkgName: 'backend_client_app',
          buildId: 'test-build',
          backendHost: '127.0.0.1',
          backendPort: 3000,
          apiBasePath: '/api',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('must use an expression body'),
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
