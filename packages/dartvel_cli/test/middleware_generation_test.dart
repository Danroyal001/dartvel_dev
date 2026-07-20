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

@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.tenant, DVMiddlewares.rateLimitCheckout])
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

      expect(
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
