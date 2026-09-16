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

      // The function is written into a library of its own, which imports
      // what its source file imports and reaches the file's public names
      // through it.
      final lowered = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_fn0.g.dart'),
      ).readAsStringSync();
      expect(
        lowered,
        contains(
          'import \'package:backend_client_app/backend/functions/task.post.dart\' as dvSource;',
        ),
      );
      expect(
        lowered,
        // `async` is kept. Dropping it, as this once asserted, breaks any
        // body whose expression is not already a Future.
        contains(
          'dvBackendFn0(String input) async => dvSource.buildResponse(input);',
        ),
      );
      expect(routes, contains("import 'dartvel_backend_fn0.g.dart' as bf0;"));
      expect(routes, contains('Object? result = await bf0.dvBackendFn0('));
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
      final lowered = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_fn0.g.dart'),
      ).readAsStringSync();
      expect(lowered, contains(r"return 'ok $input';"));
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

Future<Map<String, bool>> pay(DVContext context, String orderId) async =>
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
      // And its hooks run. The context is made per request and is not a
      // DV.transaction, so afterCommit and compensate on it filled lists that
      // nothing read: a receipt was never sent and a charge never refunded.
      expect(routes, contains('await core.dvCommitContext(_dvCtx);'));
      expect(routes, contains('await core.dvCompensateContext(_dvCtx)'));

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

Future<Map<String, bool>> ping(String id) async => <String, bool>{'ok': true};
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

  test('a function with an async expression body is found', () async {
    // Future<T> f() async => v; is how most of these are written, and every
    // pattern that looked for the function went straight from the parameter
    // list to => or {. So the function was not found, the file fell through
    // to the handler shape, and the generated router called f0.handler on a
    // file that has no handler -- a server that does not compile, from the
    // most ordinary way to write a backend function.
    final root = await Directory.systemTemp.createTemp('dartvel_async_body_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'total.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

Future<int> total(int a, int b) async => a + b;
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'async_body_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final routes = File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();

      expect(routes, contains('.total('));
      expect(routes, isNot(contains('handler(req)')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a comment in the parameter list stays out of the generated code',
      () async {
    // A comment beside a parameter is ordinary Dart. The parameter list was
    // copied as text and split on commas, so "// injected" became part of
    // the next parameter's type and swallowed the rest of its line: the
    // generated client did not compile, and nothing but a compile saw it,
    // because generated files are excluded from analysis.
    final root = await Directory.systemTemp.createTemp('dartvel_comment_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'pay.post.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, bool>> _pay(
  DVContext context, // injected, never sent by the client
  String orderId, /* the order */
  int cents,
) async =>
    <String, bool>{'ok': true};
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'comment_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final client = File(
        p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart'),
      ).readAsStringSync();
      expect(client, isNot(contains('injected')));
      expect(client, isNot(contains('the order')));
      expect(client, contains('pay({ required String orderId, required int cents,'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('an async function returning a map is typed without a mapper', () async {
    // The return type was converted with its Future still on it, so no
    // Future<...> matched a known shape and every async function's typed
    // wrapper demanded a fromJson, even for a String or a JSON map.
    final root = await Directory.systemTemp.createTemp('dartvel_future_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'greet.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _greeting(String name) async =>
    <String, Object?>{'greeting': name};
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'future_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      final client = File(
        p.join(root.path, 'lib', 'dartvel_client', 'functions.g.dart'),
      ).readAsStringSync();
      final String wrapper = client
          .split('\n')
          .firstWhere((String line) => line.contains(' greeting({'));
      expect(wrapper, isNot(contains('fromJson')));
      expect(client, contains('return Map<String, Object?>.from(r.data'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a function named like its own route is refused with both names',
      () async {
    // _getHello in hello.get.dart generates getHello, and so does the route
    // GET /hello. The client declared getHello twice and failed to compile,
    // in a generated file, with nothing pointing at the source.
    final root = await Directory.systemTemp.createTemp('dartvel_clash_');
    try {
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(p.join(root.path, 'lib', 'dartvel_client'))
          .createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'backend', 'functions'))
          .createSync(recursive: true);

      File(p.join(root.path, 'lib', 'backend', 'functions', 'hello.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _getHello(String name) async => name;
''');

      await expectLater(
        BackendGenerator.generate(
          root: root.path,
          backendDir: 'lib/backend',
          pkgName: 'clash_app',
          buildId: 'test-build',
          backendHost: '127.0.0.1',
          backendPort: 3000,
          apiBasePath: '/api',
        ),
        throwsA(isA<StateError>()
            .having((StateError e) => e.message, 'message', contains('_getHello'))
            .having((StateError e) => e.message, 'message', contains('GET /hello'))),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  group('a function named handler', () {
    // The router calls a raw handler with the request. A handler written
    // with the client's arguments, or with none, was taken for one anyway:
    // the routes called `f0.handler(req)`, and the server binary failed to
    // compile on "Too many positional arguments" inside a generated file,
    // with nothing pointing at the function. Only a handler that takes the
    // request is a raw handler; any other is called with its arguments.
    Future<String> routesFor(String source) async {
      final root = await Directory.systemTemp.createTemp('dartvel_handler_');
      try {
        Directory(p.join(root.path, '.dart_tool')).createSync();
        Directory(p.join(root.path, 'lib', 'dartvel_client'))
            .createSync(recursive: true);
        Directory(p.join(root.path, 'lib', 'backend', 'functions'))
            .createSync(recursive: true);
        File(p.join(root.path, 'lib', 'backend', 'functions', 'contact.dart'))
            .writeAsStringSync(source);
        await BackendGenerator.generate(
          root: root.path,
          backendDir: 'lib/backend',
          pkgName: 'handler_app',
          buildId: 'test-build',
          backendHost: '127.0.0.1',
          backendPort: 3000,
          apiBasePath: '/api',
        );
        return File(
          p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
        ).readAsStringSync();
      } finally {
        root.deleteSync(recursive: true);
      }
    }

    test('with named arguments is called with them', () async {
      final String routes = await routesFor('''
Future<Map<String, Object?>> handler(
    {required String name, required String email}) async {
  return <String, Object?>{'name': name, 'email': email};
}
''');
      expect(routes, isNot(contains('handler(req)')));
      expect(routes, contains('f0.handler(name: '));
      expect(routes, contains(', email: '));
    });

    test('with no parameters is called with none', () async {
      final String routes = await routesFor('''
Map<String, Object?> handler() => <String, Object?>{'status': 'ok'};
''');
      expect(routes, isNot(contains('handler(req)')));
      expect(routes, contains('f0.handler()'));
    });

    test('that takes the request is still a raw handler', () async {
      final String routes = await routesFor('''
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async => Res.notFound('no');
''');
      expect(routes, contains('f0.handler(req)'));
    });
  });
}
