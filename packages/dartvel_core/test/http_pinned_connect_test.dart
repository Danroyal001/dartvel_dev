// A request pinned to an address connects to that address and nowhere else.
//
// The webhook address check resolves a customer's host and refuses private
// addresses. If the connection then resolves the host again, a name with a
// short TTL can answer a public address to the check and 127.0.0.1 to the
// connection: DNS rebinding. Pinning closes that window by connecting to the
// address the check approved, while TLS still verifies the certificate
// against the original name and the Host header still names it.
//
// The hosts here (`*.acme.test`) do not resolve anywhere, so a request that
// reached the local server can only have got there through the pin.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/http/pinned_connect_io.dart';
import 'package:test/test.dart';

// A throwaway self-signed certificate for hooks.acme.test, made for this test
// and valid only here. It is not a credential for anything.
const String _certificate = '''
-----BEGIN CERTIFICATE-----
MIIBpzCCAU2gAwIBAgIUaQhUYL3N0ytJfnXsNGLRWugzDVcwCgYIKoZIzj0EAwIw
GjEYMBYGA1UEAwwPaG9va3MuYWNtZS50ZXN0MCAXDTI2MDkxNjEyNTIwNVoYDzIx
MjYwODIzMTI1MjA1WjAaMRgwFgYDVQQDDA9ob29rcy5hY21lLnRlc3QwWTATBgcq
hkjOPQIBBggqhkjOPQMBBwNCAAT0vRXF8+5SrCXuh7fsR2bxJ6d+otnfGlvkiDaB
qBGq6Uqzj7SN/vdF5rJWU6BN+zJjU42OohEXFzHHQnq18xaeo28wbTAdBgNVHQ4E
FgQUBWPTTduQDERdio6sa/0J1rd4ELowHwYDVR0jBBgwFoAUBWPTTduQDERdio6s
a/0J1rd4ELowGgYDVR0RBBMwEYIPaG9va3MuYWNtZS50ZXN0MA8GA1UdEwEB/wQF
MAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhAKPbm9Ggu1w0OR5OzdZInqdVemYyrvtd
5yt4vw8I6+uIAiBkteAPzALf0UJhY4aEGGH5kBaRKhdurp1IS+XLjM8W3w==
-----END CERTIFICATE-----
''';

const String _privateKey = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQguqltbrRxLwwOYjv/
rCglkz0LxCUv3VR7zOu61XmDvMOhRANCAAT0vRXF8+5SrCXuh7fsR2bxJ6d+otnf
GlvkiDaBqBGq6Uqzj7SN/vdF5rJWU6BN+zJjU42OohEXFzHHQnq18xae
-----END PRIVATE KEY-----
''';

SecurityContext _clientTrust() => SecurityContext(withTrustedRoots: false)
  ..setTrustedCertificatesBytes(utf8.encode(_certificate));

class _Seen {
  _Seen(this.host, this.path, this.body);
  final String? host;
  final String path;
  final String body;
}

Future<String> _read(DVHttpStreamedResponse response) =>
    utf8.decodeStream(response.body);

void main() {
  late HttpServer server;
  late List<_Seen> seen;
  late int Function(HttpRequest request) status;

  Future<void> answer(HttpRequest request) async {
    final String body = await utf8.decodeStream(request);
    seen.add(_Seen(
        request.headers.value(HttpHeaders.hostHeader), request.uri.path, body));
    final int code = status(request);
    request.response.statusCode = code;
    if (code >= 300 && code < 400) {
      request.response.headers
          .set(HttpHeaders.locationHeader, 'https://169.254.169.254/latest');
    }
    request.response.write('ok');
    await request.response.close();
  }

  setUp(() {
    seen = <_Seen>[];
    status = (_) => 200;
  });

  tearDown(() => server.close(force: true));

  group('over TLS', () {
    setUp(() async {
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChainBytes(utf8.encode(_certificate))
          ..usePrivateKeyBytes(utf8.encode(_privateKey)),
      );
      server.listen(answer);
    });

    test('connects to the pinned address, verifies the certificate against '
        'the name, and sends the name as Host', () async {
      final DVHttpStreamedResponse response = await dvPinnedStreamHttpRequest(
        DVHttpRequest(
          url: Uri.parse('https://hooks.acme.test:${server.port}/in'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: utf8.encode('{"id":1}'),
          connectAddress: '127.0.0.1',
        ),
        context: _clientTrust(),
      );

      expect(response.statusCode, 200);
      expect(await _read(response), 'ok');
      expect(seen, hasLength(1));
      expect(seen.single.host, 'hooks.acme.test:${server.port}');
      expect(seen.single.path, '/in');
      expect(seen.single.body, '{"id":1}');
    });

    test('a certificate for another name is refused even at the pinned '
        'address, so the pin cannot be used to skip verification', () async {
      await expectLater(
        dvPinnedStreamHttpRequest(
          DVHttpRequest(
            url: Uri.parse('https://other.acme.test:${server.port}/in'),
            connectAddress: '127.0.0.1',
          ),
          context: _clientTrust(),
        ),
        throwsA(isA<HandshakeException>()),
      );
      expect(seen, isEmpty);
    });

    test('a redirect is returned, not followed: following it would resolve '
        'the new host with no check and no pin', () async {
      status = (_) => 302;
      final DVHttpStreamedResponse response = await dvPinnedStreamHttpRequest(
        DVHttpRequest(
          url: Uri.parse('https://hooks.acme.test:${server.port}/in'),
          connectAddress: '127.0.0.1',
        ),
        context: _clientTrust(),
      );
      await _read(response);

      expect(response.statusCode, 302);
      expect(response.headers['location'], 'https://169.254.169.254/latest');
      expect(seen, hasLength(1));
    });
  });

  group('through the default wire', () {
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(answer);
    });

    test('dvStreamHttpRequest honours connectAddress', () async {
      final DVHttpStreamedResponse response = await dvStreamHttpRequest(
        DVHttpRequest(
          url: Uri.parse('http://hooks.acme.test:${server.port}/in'),
          connectAddress: '127.0.0.1',
        ),
      );
      expect(response.statusCode, 200);
      await _read(response);
      expect(seen.single.host, 'hooks.acme.test:${server.port}');
    });

    test('DV.Http.send passes connectAddress to the wire, and the redirect '
        'comes back to the caller', () async {
      DVHttp.reset();
      addTearDown(DVHttp.reset);
      status = (_) => 307;
      final Response response = await const DVHttp().send(
        'POST',
        Uri.parse('http://hooks.acme.test:${server.port}/in'),
        body: 'x',
        attempts: 1,
        connectAddress: '127.0.0.1',
        // As a webhook delivery sends it: the subscriber's URL is not a declared
        // host, and the pinned address is what its caller checked instead.
        allowUndeclaredHost: true,
      );
      expect(response.status, 307);
      expect(seen, hasLength(1));
    });
  });
}
