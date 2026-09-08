// CORS and compression are two of the specification's built-in middlewares,
// and declaring either as a route middleware fails the build. That refusal
// is right -- both are decided once, when the server starts, so a per-route
// declaration cannot change anything -- but the reason it gave was
// unreachable advice: "pass cors: to the serve call". Nobody using Dartvel
// writes a serve call. The generated startBackend does, and it read no
// configuration at all, so a Dartvel application could not set a CORS policy
// and could not turn compression off.
//
// dartvel.server is where a server-wide decision belongs, next to the host
// and port that were already there.
import 'dart:io';

import 'package:dartvel_cli/src/build/server_options.dart';
import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Object? _dv(Map<String, Object?> server) =>
    YamlMap.wrap(<String, Object?>{'server': server});

void main() {
  group('what dartvel.server says about CORS', () {
    test('a project that says nothing gets no CORS headers', () {
      // Not "allow everything". A server that answers every origin is the
      // one setting most likely to be wrong, and defaulting to it would put
      // it on every application that never thought about the question.
      final DVServerOptions options =
          DVServerOptions.parse(YamlMap.wrap(<String, Object?>{}));

      expect(options.cors, isNull);
      expect(options.corsSource, isNull);
    });

    test('the origins a project names reach the emitted options', () {
      final DVServerOptions options = DVServerOptions.parse(
        _dv(<String, Object?>{
          'cors': <String, Object?>{
            'origins': <String>['https://app.example.com'],
            'methods': <String>['GET', 'POST'],
            'allowCredentials': true,
            'maxAge': 600,
          },
        }),
      );

      expect(options.cors?.origins, <String>['https://app.example.com']);
      expect(options.cors?.methods, <String>['GET', 'POST']);
      expect(options.cors?.allowCredentials, isTrue);
      expect(options.cors?.maxAgeSeconds, 600);
      expect(
        options.corsSource,
        allOf(
          contains("origins: <String>['https://app.example.com']"),
          contains('allowCredentials: true'),
          contains('maxAge: Duration(seconds: 600)'),
        ),
      );
    });

    test('origins: any is the wildcard, written as one word', () {
      final DVServerOptions options = DVServerOptions.parse(
        _dv(<String, Object?>{
          'cors': <String, Object?>{'origins': 'any'},
        }),
      );

      expect(options.cors?.allowAnyOrigin, isTrue);
      expect(options.corsSource, contains('allowAnyOrigin: true'));
    });

    test('credentials from any origin is refused at build time', () {
      // The browser refuses this combination itself: Access-Control-Allow-
      // Origin: * with credentials is not a policy, it is a request that is
      // never sent. Refused here, naming the two keys, rather than emitted
      // as an assertion that fires somewhere in a generated file.
      expect(
        () => DVServerOptions.parse(
          _dv(<String, Object?>{
            'cors': <String, Object?>{
              'origins': 'any',
              'allowCredentials': true,
            },
          }),
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            allOf(contains('allowCredentials'), contains('origins')),
          ),
        ),
      );
    });

    test('an origin that is not an origin is refused', () {
      // A path or a trailing slash never matches: the browser compares the
      // Origin header, which is scheme, host and port and nothing else. A
      // policy that silently matches nothing reads as CORS being broken.
      expect(
        () => DVServerOptions.parse(
          _dv(<String, Object?>{
            'cors': <String, Object?>{
              'origins': <String>['https://app.example.com/'],
            },
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('what dartvel.server says about compression', () {
    test('it is on unless the project turns it off', () {
      expect(
        DVServerOptions.parse(YamlMap.wrap(<String, Object?>{})).compression,
        isTrue,
      );
    });

    test('false is honoured', () {
      // A server behind a proxy that compresses already, or one serving
      // bytes that are compressed to begin with.
      expect(
        DVServerOptions.parse(_dv(<String, Object?>{'compression': false}))
            .compression,
        isFalse,
      );
    });

    test('a value that is not a boolean is refused rather than ignored', () {
      // compression: "false" is a string and a string is not false. Ignoring
      // it leaves compression on for somebody who wrote down that they
      // wanted it off.
      expect(
        () => DVServerOptions.parse(_dv(<String, Object?>{
          'compression': 'false',
        })),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('what the generated backend actually serves with', () {
    Future<String> routesFor(String pubspec) async {
      final Directory root = await Directory.systemTemp.createTemp(
        'dartvel_server_options_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, '.dart_tool')).createSync();
      Directory(
        p.join(root.path, 'lib', 'dartvel_client'),
      ).createSync(recursive: true);
      Directory(
        p.join(root.path, 'lib', 'backend', 'functions'),
      ).createSync(recursive: true);
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
      File(p.join(root.path, 'lib', 'backend', 'functions', 'ping.get.dart'))
          .writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> handler() async => 'pong';
''');

      await BackendGenerator.generate(
        root: root.path,
        backendDir: 'lib/backend',
        pkgName: 'server_options_app',
        buildId: 'test-build',
        backendHost: '127.0.0.1',
        backendPort: 3000,
        apiBasePath: '/api',
      );

      // .dart_tool, which is where BackendGenerator writes it -- the
      // generated server is not application source.
      return File(
        p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'),
      ).readAsStringSync();
    }

    test('a configured policy reaches the serve call', () async {
      // The whole point: the constant is emitted *and* passed. An earlier
      // feature emitted a correct value into a generated file that the
      // serve call never read, and the unit test for the value passed.
      final String routes = await routesFor('''
name: server_options_app
dartvel:
  server:
    cors:
      origins: [https://app.example.com]
      allowCredentials: true
    compression: false
''');

      expect(
        routes,
        contains(
          "const dv.CorsOptions? dartvelConfiguredCors = "
          "dv.CorsOptions(origins: <String>['https://app.example.com'], "
          'allowCredentials: true);',
        ),
      );
      expect(routes, contains('const bool dartvelCompression = false;'));
      expect(routes, contains('cors: cors ?? dartvelConfiguredCors'));
      expect(
        routes,
        contains('compression: compression ?? dartvelCompression'),
      );
    });

    test('a project that configured nothing sends no CORS headers', () async {
      final String routes = await routesFor('name: server_options_app\n');

      expect(
        routes,
        contains('const dv.CorsOptions? dartvelConfiguredCors = null;'),
      );
      expect(routes, contains('const bool dartvelCompression = true;'));
    });

    test('a configuration the build cannot honour stops the build', () async {
      // Rather than generating a server that ignores it. Somebody wrote
      // this down deliberately, and the quiet failure is a CORS policy that
      // is not applied on an application that looks built.
      await expectLater(
        routesFor('''
name: server_options_app
dartvel:
  server:
    cors:
      origins: any
      allowCredentials: true
'''),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
