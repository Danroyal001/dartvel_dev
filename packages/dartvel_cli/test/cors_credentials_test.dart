// dartvel.server.cors.allowCredentials: the server's half of a web build
// calling its API on another origin.
//
// The client sends the session cookie only to origins it names exactly
// (DVCredentialedOrigins). The server has to answer those origins, and only
// those, with Access-Control-Allow-Credentials -- a credentialed policy is a
// promise that every listed origin may act as the signed-in person.
//
// The silent failures this pins:
//  * a credentialed policy that can never work -- no origins, or a wildcard
//    method or header list, which a browser reads as a literal "*" once
//    credentials are on (and tower-http refuses at startup);
//  * a plain-http origin off the loopback, whose page anybody on the network
//    can rewrite into one that spends the session;
//  * a policy that answers the origin and not the CSRF header every
//    state-changing call carries, so every sign-in fails its preflight and
//    reads as CORS being broken.
import 'package:dartvel_cli/src/build/server_options.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Object? _dv(Map<String, Object?> cors) => YamlMap.wrap(<String, Object?>{
      'server': <String, Object?>{'cors': cors},
    });

Matcher _refusal(String mentions) => throwsA(isA<FormatException>().having(
    (FormatException e) => e.message, 'message', contains(mentions)));

void main() {
  test('credentials with named https origins are the policy', () {
    final DVServerOptions options = DVServerOptions.parse(_dv(<String, Object?>{
      'origins': <String>['https://app.example.com', 'http://localhost:5173'],
      'allowCredentials': true,
    }));
    expect(options.cors!.allowCredentials, isTrue);
    expect(options.cors!.allowAnyOrigin, isFalse);
    expect(options.corsSource, contains('allowCredentials: true'));
    expect(options.corsSource,
        contains("origins: <String>['https://app.example.com', 'http://localhost:5173']"));
  });

  test('the headers the generated client sends are answered', () {
    final DVCorsSettings bare = DVServerOptions.parse(_dv(<String, Object?>{
      'origins': <String>['https://app.example.com'],
      'allowCredentials': true,
    })).cors!;
    expect(bare.headers, containsAll(<String>['content-type', 'x-dartvel-csrf-token']));

    final DVCorsSettings listed = DVServerOptions.parse(_dv(<String, Object?>{
      'origins': <String>['https://app.example.com'],
      'headers': <String>['x-request-id'],
      'allowCredentials': true,
    })).cors!;
    expect(listed.headers,
        containsAll(<String>['x-request-id', 'content-type', 'x-dartvel-csrf-token']));
  });

  test('a policy without credentials is left as written', () {
    final DVCorsSettings cors = DVServerOptions.parse(_dv(<String, Object?>{
      'origins': <String>['https://app.example.com'],
    })).cors!;
    expect(cors.headers, isEmpty);
  });

  group('a credentialed policy is refused, naming the key,', () {
    test('with origins: any', () {
      expect(
          () => DVServerOptions.parse(
              _dv(<String, Object?>{'origins': 'any', 'allowCredentials': true})),
          _refusal('allowCredentials'));
    });

    test('with no origins at all', () {
      expect(() => DVServerOptions.parse(_dv(<String, Object?>{'allowCredentials': true})),
          _refusal('dartvel.server.cors.origins'));
    });

    for (final String key in <String>['methods', 'headers', 'exposeHeaders']) {
      test('with $key: any', () {
        expect(
            () => DVServerOptions.parse(_dv(<String, Object?>{
                  'origins': <String>['https://app.example.com'],
                  key: 'any',
                  'allowCredentials': true,
                })),
            _refusal('dartvel.server.cors.$key'));
      });
    }

    test('with a plain http origin off the loopback', () {
      expect(
          () => DVServerOptions.parse(_dv(<String, Object?>{
                'origins': <String>['https://app.example.com', 'http://app.example.com'],
                'allowCredentials': true,
              })),
          _refusal('http://app.example.com'));
    });
  });
}
