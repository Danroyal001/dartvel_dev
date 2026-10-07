import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The server answers a String result as text. A client that JSON-decoded it
// turned a String holding JSON (a serialized document, a config) into a Map,
// and the `as String` cast then threw in the app.
void main() {
  test('a String result is read as the response text, never JSON-decoded', () async {
    final root = await Directory.systemTemp.createTemp('dartvel_string_result_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
      File(p.join(root.path, 'lib', 'backend', 'functions', 'export_document.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _exportDocument({required String id}) async => '{"id": "\$id"}';
''');
      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'string_result_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );
      final content = File(p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart')).readAsStringSync();
      expect(content, contains('Future<String> exportDocument('));
      expect(content, contains('return r.body;'));
      expect(content, isNot(contains('r.data as String')));
    } finally {
      await root.delete(recursive: true);
    }
  });
}
