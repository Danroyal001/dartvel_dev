// A browser client calling an API on another origin.
//
// The browser sends a fetch's cookies to its own origin and nowhere else
// unless the request says `credentials: 'include'`. The session cookie
// (__Host-dv_session) lives on the API's origin, so a Flutter web build served
// from app.example.com calling api.example.com was signed out on every call:
// the transport never asked for credentials.
//
// The fix must not become "include credentials everywhere". A generated call
// or a DV.Http call to a third party carrying the person's session cookie is
// the leak CORS exists to stop, so credentials go only to origins named
// exactly, and anything that is not an origin -- a wildcard, "null", a path,
// plain http off the loopback -- is refused when it is named.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late List<(Uri, bool)> clients;

  http.Client recording({required bool withCredentials}) => MockClient(
        (http.Request request) async {
          clients.add((request.url, withCredentials));
          return http.Response('ok', 200);
        },
      );

  setUp(() {
    clients = <(Uri, bool)>[];
    DVCredentialedOrigins.clear();
  });

  tearDown(DVCredentialedOrigins.clear);

  Future<bool> credentialedSend(String url) async {
    await DVBrowserHttpTransport(clientFor: recording)
        .send(DVHttpRequest(url: Uri.parse(url), method: 'GET'));
    return clients.last.$2;
  }

  Future<bool> credentialedStream(String url) async {
    final DVHttpStreamedResponse response =
        await DVBrowserHttpTransport(clientFor: recording)
            .stream(DVHttpRequest(url: Uri.parse(url), method: 'GET'));
    expect(await response.body.transform(utf8.decoder).join(), 'ok');
    return clients.last.$2;
  }

  group('a request to a named origin carries credentials', () {
    test('sent and streamed', () async {
      DVCredentialedOrigins.allow('https://api.example.com');
      expect(await credentialedSend('https://api.example.com/api/auth/session'), isTrue);
      expect(await credentialedStream('https://api.example.com/api/events'), isTrue);
    });

    test('an origin with its default port written out is the same origin', () async {
      DVCredentialedOrigins.allow('https://api.example.com:443');
      expect(await credentialedSend('https://api.example.com/api/x'), isTrue);
    });

    test('a loopback origin over http, for development', () async {
      DVCredentialedOrigins.allow('http://localhost:8080');
      expect(await credentialedSend('http://localhost:8080/api/x'), isTrue);
      DVCredentialedOrigins.allow('http://127.0.0.1:8080');
      expect(await credentialedSend('http://127.0.0.1:8080/api/x'), isTrue);
    });
  });

  group('a request anywhere else does not', () {
    setUp(() => DVCredentialedOrigins.allow('https://api.example.com'));

    for (final String url in <String>[
      'https://evil.example.com/api/x',
      'https://api.example.com.evil.test/api/x',
      'https://api.example.com:8443/api/x',
      'http://api.example.com/api/x',
      'https://example.com/api/x',
      'https://sub.api.example.com/api/x',
    ]) {
      test(url, () async {
        expect(await credentialedSend(url), isFalse);
        expect(await credentialedStream(url), isFalse);
      });
    }

    test('nor anything, when no origin was named', () async {
      DVCredentialedOrigins.clear();
      expect(await credentialedSend('https://api.example.com/api/x'), isFalse);
    });
  });

  group('the generated client names its own backend', () {
    test('an absolute backend URL: its origin, and only its origin', () async {
      expect(DVCredentialedOrigins.allowBackend('https://api.example.com/'), isNull);
      expect(DVCredentialedOrigins.origins, <String>{'https://api.example.com:443'});
      expect(await credentialedSend('https://api.example.com/api/x'), isTrue);
      expect(await credentialedSend('https://cdn.example.com/x'), isFalse);
    });

    test('a relative or empty one is the page\'s own origin, which needs '
        'nothing named', () {
      expect(DVCredentialedOrigins.allowBackend(''), isNull);
      expect(DVCredentialedOrigins.allowBackend('/'), isNull);
      expect(DVCredentialedOrigins.origins, isEmpty);
    });

    test('a plain http backend off the loopback is not named, and says why',
        () async {
      final String? why = DVCredentialedOrigins.allowBackend('http://api.example.com');
      expect(why, allOf(isNotNull, contains('http://api.example.com')));
      expect(DVCredentialedOrigins.origins, isEmpty);
      expect(await credentialedSend('http://api.example.com/api/x'), isFalse);
    });
  });

  group('naming something that is not one exact origin is refused', () {
    for (final String value in <String>[
      '*',
      'any',
      'null',
      '',
      'api.example.com',
      'https://*.example.com',
      'https://api.example.com/',
      'https://api.example.com/api',
      'https://api.example.com?x=1',
      'https://user@api.example.com',
      'http://api.example.com',
      'ftp://api.example.com',
    ]) {
      test('"$value"', () {
        expect(() => DVCredentialedOrigins.allow(value), throwsArgumentError);
        expect(DVCredentialedOrigins.origins, isEmpty);
      });
    }
  });
}
