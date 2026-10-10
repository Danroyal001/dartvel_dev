// Serving over TLS from PEM text: the certificate chain and the key are read
// by the native library, and a server that terminates TLS sends HSTS.
//
// The key is a SEC1 EC key ("BEGIN EC PRIVATE KEY"), the shape openssl and
// many ACME clients write, because the PKCS#8 path is the common one and the
// fallback is the one a parser change would break unnoticed. The native
// library keeps the first TLS configuration for the life of the process, so
// one server is started over TLS here and the refusals are checked before it.
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  late String certPem;
  late String keyPem;

  setUpAll(() async {
    final Directory dir = await Directory.systemTemp.createTemp('dv-tls-');
    addTearDown(() => dir.delete(recursive: true));
    final ProcessResult made = await Process.run('openssl', <String>[
      'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
      '-nodes', '-days', '1', '-subj', '/CN=localhost',
      '-keyout', '${dir.path}/key.pem', '-out', '${dir.path}/cert.pem',
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final ProcessResult sec1 = await Process.run('openssl', <String>[
      'ec', '-in', '${dir.path}/key.pem', '-out', '${dir.path}/sec1.pem',
    ]);
    expect(sec1.exitCode, 0, reason: '${sec1.stderr}');
    certPem = await File('${dir.path}/cert.pem').readAsString();
    keyPem = await File('${dir.path}/sec1.pem').readAsString();
    expect(keyPem, contains('BEGIN EC PRIVATE KEY'));
  });

  Future<Response> hello(Request request) async => Response.text('hello');

  test('text that holds no certificate is refused before binding', () async {
    await expectLater(
      serve(hello, port: 0,
          tls: TlsConfig(certPem: 'not a certificate', keyPem: keyPem)),
      throwsA(isA<StateError>()
          .having((StateError e) => e.message, 'message', contains('code=2'))),
    );
  });

  test('a certificate with no key beside it is refused', () async {
    await expectLater(
      serve(hello, port: 0, tls: TlsConfig(certPem: certPem, keyPem: certPem)),
      throwsA(isA<StateError>()
          .having((StateError e) => e.message, 'message', contains('code=3'))),
    );
  });

  test('a SEC1 key serves HTTPS, with HSTS on the response', () async {
    final ServerHandle server = await serve(hello,
        port: 0, tls: TlsConfig(certPem: certPem, keyPem: keyPem));
    addTearDown(server.stop);
    final HttpClient client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) =>
          cert.subject.contains('localhost');
    addTearDown(() => client.close(force: true));
    final HttpClientResponse response = await (await client
            .getUrl(Uri.parse('https://localhost:${server.port}/')))
        .close();
    expect(await response.transform(const SystemEncoding().decoder).join(),
        'hello');
    expect(response.headers.value('strict-transport-security'),
        dvDefaultStrictTransportSecurity);
  });
}
