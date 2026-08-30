// The generated backend has its own multipart parser, separate from
// DVRequest.formData(). Teaching one about the binary envelope and not the
// other is how a flat-buffer field reached a live route and decoded to 0 while
// every unit test passed: the request succeeded, the answer was wrong, and
// nothing anywhere said so.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generatedRoutes() async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_flat_transport_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'backend', 'functions', 'sum.post.dart'))
      .writeAsStringSync('int sum(int a, int b) => a + b;\n');

  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'flat_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );

  return File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
      .readAsStringSync();
}

void main() {
  test('the generated multipart parser understands the binary envelope',
      () async {
    final String routes = await generatedRoutes();

    expect(routes, contains('dvFlatContentType'));
    expect(routes, contains('dvFlatDecode'));
  });

  test('a text field is still decoded as text', () async {
    // The envelope is opt-in per field; a client that has not adopted it must
    // keep working.
    final String routes = await generatedRoutes();

    expect(routes, contains('utf8.decodeStream(part)'));
  });
}
