// What the generated backend and client do with a refusal and a failure.
//
// Server: a DVRefusal thrown by a function answers with its own status and
// {"error": message}; anything else stays a bare 500 so internals do not
// leak. Client: a typed function checks the answer before decoding it, so a
// failure throws DVBackendFunctionException instead of returning the error
// page's text as the result (Payseal navigated to /tip/Internal%20Server%20Error).
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'generated_router.dart';

void main() {
  late Directory root;
  late String server;
  late String client;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('dartvel_refusal_test_');
    Directory(p.join(root.path, '.dart_tool')).createSync();
    Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
    File(p.join(root.path, 'lib/backend/functions/create_creator.post.dart')).writeAsStringSync(
        "import '../../dartvel_client/dartvel_client.dart';\n@DVBackendFunction()\nFuture<String> _createCreator(String handle) async => handle;\n");
    File(p.join(root.path, 'lib/backend/functions/creator.get.dart')).writeAsStringSync(
        "import '../../dartvel_client/dartvel_client.dart';\n@DVBackendFunction()\nFuture<Map<String, Object?>> _creator(String handle) async => <String, Object?>{};\n");
    await BackendGenerator.generate(
      root: root.path,
      backendDir: 'lib/backend',
      pkgName: 'refusal_app',
      buildId: 'test-build',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );
    server = File(p.join(root.path, '.dart_tool/dartvel_backend_routes.g.dart')).readAsStringSync();
    client = File(p.join(root.path, 'lib/dartvel_client/functions.g.dart')).readAsStringSync();
  });
  tearDownAll(() => root.deleteSync(recursive: true));

  test('a refusal answers with its own status and message as JSON', () {
    final String route = dvRouteSource(server, '/create_creator');
    expect(route, contains('on core.DVRefusal catch'));
    expect(route, contains('dv.Response(refusal.responseStatus'));
    expect(route, contains('refusal.responseBody'));
    expect(route, contains("'content-type': 'application/json; charset=utf-8'"));
  });

  test('any other exception is still a bare 500 that names nothing', () {
    final String route = dvRouteSource(server, '/create_creator');
    final int refusal = route.indexOf('on core.DVRefusal catch');
    final int generic = route.indexOf('} catch (e, st)');
    expect(refusal, greaterThan(-1));
    expect(generic, greaterThan(refusal),
        reason: 'the refusal has to be caught before the catch-all');
    expect(route.substring(generic), contains("'Internal Server Error'"));
  });

  test('a refusal is not recorded as a server crash', () {
    final String route = dvRouteSource(server, '/create_creator');
    final String refusalArm = route.substring(
        route.indexOf('on core.DVRefusal catch'), route.indexOf('} catch (e, st)'));
    expect(refusalArm, isNot(contains('DVServerCrashes.record')));
  });

  test('a typed client function checks the answer before decoding it', () {
    for (final String name in <String>['createCreator', 'creator']) {
      final int start = client.indexOf(' $name(');
      expect(start, greaterThan(-1), reason: name);
      final String body = client.substring(start, client.indexOf('\n}\n', start));
      final int check = body.indexOf('DVBackendFunctionException.throwUnlessSuccess(r)');
      final int decode = body.indexOf('return ');
      expect(check, greaterThan(-1), reason: '$name must check the status');
      expect(check, lessThan(decode), reason: '$name checks before it decodes');
    }
  });
}
