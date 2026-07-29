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

  test('backend generation rejects private annotated backend functions',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dartvel_backend_public_test_');
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
Future<String> _handler() async => 'ok';
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
            contains('backend function inputs are private in the spec'),
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
