// A backend function parameter cannot take a name the generated client
// already uses for its own transport arguments: query, body and headers.
// The client function would declare the name twice and not compile, with
// the error pointing into a generated file instead of at the function.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  for (final String name in <String>['body', 'query', 'headers']) {
    test('a parameter named $name is refused, naming the file and the parameter', () async {
      final Directory root = await _project();
      try {
        File(p.join(root.path, 'lib', 'backend', 'functions', 'post_note.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<bool> _postNote(String title, String $name) async => true;
''');
        await expectLater(
          () => _generate(root),
          throwsA(isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            allOf(contains('lib/backend/functions/post_note.dart'), contains('"$name"'), contains('Rename')),
          )),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  }

  test('other names still generate a client that names them', () async {
    final Directory root = await _project();
    try {
      File(p.join(root.path, 'lib', 'backend', 'functions', 'post_note.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<bool> _postNote(String title, String noteText) async => true;
''');
      await _generate(root);
      final String client = File(p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart')).readAsStringSync();
      expect(client, contains('required String noteText'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

Future<Directory> _project() async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_reserved_param_test_');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  return root;
}

Future<void> _generate(Directory root) => BackendGenerator.generate(
      root: root.path,
      backendDir: 'lib/backend',
      pkgName: 'reserved_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );
