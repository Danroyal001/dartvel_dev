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

  group('what dartvel.server says about trusted proxies', () {
    // Every per-source limit counts the client address, and a header naming
    // a client is believed only from a proxy listed here. The silent failures
    // are a list that did not reach the server -- every client behind the
    // proxy counted as the proxy -- and a range the build accepted but the
    // runtime could not read, or read as something wider.
    test('a project that says nothing trusts no proxy', () {
      final DVServerOptions options =
          DVServerOptions.parse(YamlMap.wrap(<String, Object?>{}));
      expect(options.trustedProxies, isEmpty);
      expect(options.forwardedHeader, isNull);
    });

    test('the ranges and the header a project names are read', () {
      final DVServerOptions options = DVServerOptions.parse(
        _dv(<String, Object?>{
          'trustedProxies': <String>['127.0.0.1/32', '::1', '10.0.0.0/8'],
          'forwardedHeader': 'forwarded',
        }),
      );
      expect(options.trustedProxies, <String>['127.0.0.1/32', '::1', '10.0.0.0/8']);
      expect(options.forwardedHeader, 'forwarded');
    });

    test('a range that is not one is refused, naming it', () {
      for (final Object bad in <Object>[
        <String>['10.0.0.0/33'],
        <String>['10.0.0.1/8'],
        <String>['caddy'],
        <Object>[8],
        '10.0.0.0/8',
        true,
      ]) {
        expect(
          () => DVServerOptions.parse(
              _dv(<String, Object?>{'trustedProxies': bad})),
          throwsA(isA<FormatException>().having((FormatException e) => e.message,
              'message', contains('dartvel.server.trustedProxies'))),
          reason: '$bad',
        );
      }
    });

    test('a header no proxy writes is refused', () {
      expect(
        () => DVServerOptions.parse(_dv(<String, Object?>{
          'trustedProxies': <String>['127.0.0.1'],
          'forwardedHeader': 'x-real-ip',
        })),
        throwsA(isA<FormatException>().having((FormatException e) => e.message,
            'message', contains('dartvel.server.forwardedHeader'))),
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

    test('the trusted proxies reach the resolver the server installs',
        () async {
      // Emitted and installed, before serve: a list emitted into a constant
      // nothing reads leaves every client behind the proxy counted as it.
      final String routes = await routesFor('''
name: server_options_app
dartvel:
  server:
    trustedProxies: [127.0.0.1/32, "::1/128"]
    forwardedHeader: forwarded
''');

      expect(
        routes,
        contains("const List<String> dartvelTrustedProxies = "
            "<String>['127.0.0.1/32', '::1/128'];"),
      );
      expect(routes,
          contains("const String? dartvelForwardedHeader = 'forwarded';"));
      final int install = routes.indexOf(
          'core.DVClientAddress.install(core.DVClientAddress.fromConfiguration('
          'trustedProxies: dartvelTrustedProxies, '
          'forwardedHeader: dartvelForwardedHeader, '
          'environment: Platform.environment));');
      expect(install, isNot(-1));
      expect(install, lessThan(routes.indexOf('return dv.serve(')),
          reason: 'installed before the first request can arrive');
    });

    test('a project that names no proxy trusts none', () async {
      final String routes = await routesFor('name: server_options_app\n');
      expect(routes,
          contains('const List<String> dartvelTrustedProxies = <String>[];'));
      expect(routes, contains('const String? dartvelForwardedHeader = null;'));
      expect(routes, contains('core.DVClientAddress.install('));
    });

    test('a trusted proxy range the runtime cannot read stops the build',
        () async {
      await expectLater(
        routesFor('''
name: server_options_app
dartvel:
  server:
    trustedProxies: [10.0.0.0/33]
'''),
        throwsA(isA<FormatException>()),
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
