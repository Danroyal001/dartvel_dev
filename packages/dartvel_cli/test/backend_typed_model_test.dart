import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'generated_router.dart';

void main() {
 test('generated data model results need no mapper and arguments use JSON', () async {
  final root = await _createProject();
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib/models')).createSync();
  File(p.join(root.path, 'lib/models/receipt.dart')).writeAsStringSync('@DVModel() class const _Receipt({required final String id});');
  File(p.join(root.path, 'lib/backend/functions/echo.post.dart')).writeAsStringSync("import '../../dartvel_client/dartvel_client.dart';\n@DVBackendFunction()\nFuture<Receipt> _echo(Receipt receipt) async => receipt;");
  File(p.join(root.path, 'lib/backend/functions/receipts.get.dart')).writeAsStringSync("import '../../dartvel_client/dartvel_client.dart';\n@DVBackendFunction()\nFuture<List<Receipt>> _receipts() async => [];\n");
  await _generate(root);
  final client = File(p.join(root.path, 'lib/dartvel_client/functions.g.dart')).readAsStringSync();
  expect(client, isNot(contains('required Receipt Function(Object?) fromJson')));
  expect(client, isNot(contains('required List<Receipt> Function(Object?) fromJson')));
  expect(client, contains('ReceiptParser.fromJson'));
  expect(client, contains('final reqPayload = body ?? fb;'));
  final server=File(p.join(root.path,'.dart_tool/dartvel_backend_routes.g.dart')).readAsStringSync();
  expect(server, contains('ReceiptParser.fromJson'));
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
