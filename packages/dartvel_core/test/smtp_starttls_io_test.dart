// STARTTLS on the dart:io connection, against a local server with a real
// certificate.
//
// The upgrade verified the certificate against the socket's address rather
// than the host the caller asked for, so a server whose certificate names its
// host (every real one) failed the handshake when reached through that host.
// The failure was then hidden: close() cancelled the line queue startTls had
// already cancelled, and "Bad state: Already cancelled" replaced the TLS error.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/src/mail/smtp_client.dart';
import 'package:dartvel_core/src/mail/smtp_socket_io.dart';
import 'package:test/test.dart';

late Directory certificates;
late SecurityContext serverContext;
late SecurityContext clientContext;

/// A server that greets, advertises STARTTLS, upgrades, and then answers EHLO.
Future<ServerSocket> startServer() async {
  final ServerSocket server = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((Socket socket) async {
    final StreamIterator<String> plain = StreamIterator<String>(
      utf8.decoder.bind(socket).transform(const LineSplitter()),
    );
    socket.write('220 test ESMTP\r\n');
    while (await plain.moveNext()) {
      final String line = plain.current;
      if (line.startsWith('EHLO')) {
        socket.write('250-test\r\n250 STARTTLS\r\n');
      } else if (line == 'STARTTLS') {
        socket.write('220 go ahead\r\n');
        await socket.flush();
        break;
      }
    }
    try {
      final SecureSocket secured = await SecureSocket.secureServer(
        socket,
        serverContext,
      );
      await for (final String line
          in utf8.decoder.bind(secured).transform(const LineSplitter())) {
        if (line.startsWith('EHLO')) secured.write('250 secured\r\n');
        if (line == 'QUIT') {
          secured.write('221 bye\r\n');
          await secured.close();
        }
      }
    } on Object {
      socket.destroy();
    }
  });
  return server;
}

Future<void> greetAndAskForTls(DVSmtpConnection connection) async {
  expect(await connection.readLine(), startsWith('220'));
  await connection.write('EHLO client\r\n');
  expect(await connection.readLine(), '250-test');
  expect(await connection.readLine(), '250 STARTTLS');
  await connection.write('STARTTLS\r\n');
  expect(await connection.readLine(), startsWith('220'));
}

void main() {
  setUpAll(() async {
    certificates = await Directory.systemTemp.createTemp('dv-smtp-tls-');
    final ProcessResult made = await Process.run('openssl', <String>[
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=DNS:localhost',
      '-keyout',
      '${certificates.path}/key.pem',
      '-out',
      '${certificates.path}/cert.pem',
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    serverContext = SecurityContext()
      ..useCertificateChain('${certificates.path}/cert.pem')
      ..usePrivateKey('${certificates.path}/key.pem');
    clientContext = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('${certificates.path}/cert.pem');
  });
  tearDownAll(() => certificates.delete(recursive: true));

  test(
    'STARTTLS verifies the certificate against the host asked for',
    () async {
      final ServerSocket server = await startServer();
      final DVSmtpConnection plain = await dvConnectSmtp(
        'localhost',
        server.port,
        secure: false,
        context: clientContext,
      );
      await greetAndAskForTls(plain);
      final DVSmtpConnection secured = await plain.startTls();
      await secured.write('EHLO client\r\n');
      expect(await secured.readLine(), '250 secured');
      await secured.write('QUIT\r\n');
      expect(await secured.readLine(), startsWith('221'));
      await secured.close();
      await server.close();
    },
  );

  test('a failed upgrade reports the TLS error, and closing afterwards is harmless', () async {
    final ServerSocket server = await startServer();
    // Reached by address: the certificate names localhost, so verification must fail.
    final DVSmtpConnection plain = await dvConnectSmtp(
      '127.0.0.1',
      server.port,
      secure: false,
      context: clientContext,
    );
    await greetAndAskForTls(plain);
    await expectLater(plain.startTls(), throwsA(isA<HandshakeException>()));
    await plain.close();
    await server.close();
  });
}
