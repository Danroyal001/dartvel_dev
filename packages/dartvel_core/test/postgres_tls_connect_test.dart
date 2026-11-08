// The TLS negotiation over a real socket, against a scripted server.
//
// Every path out of the SSLRequest except "declined under prefer" hung
// forever: each one awaited `close()` on the relay stream controller, and the
// future `close()` returns completes only once a listener has received the
// done event. Nothing had listened yet, so a server that said `S` (proceed
// under TLS), a server that said `N` under `require`, and a server that
// answered with an error all left the caller waiting -- TLS could not be used
// at all, and the refusal meant to stop a plaintext downgrade never surfaced.
//
// The certificate is a throwaway self-signed one for localhost, made by
// openssl into a temporary directory when the suite starts and deleted when it
// ends. Nothing is committed: this repository is public, and a private key in
// it trips every secret scanner whether or not it guards anything. Without
// openssl the TLS cases skip, saying why; the refusal cases still run.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:dartvel_core/src/database/postgres.dart';
import 'package:dartvel_core/src/database/postgres_socket_io.dart';
import 'package:test/test.dart';

const Duration _quick = Duration(seconds: 5);

/// Where the generated certificate and key live while the suite runs.
Directory? _certificates;

SecurityContext _serverContext() => SecurityContext()
  ..useCertificateChain('${_certificates!.path}/server.pem')
  ..usePrivateKey('${_certificates!.path}/server.key.pem');

/// Why the TLS cases cannot run here, or null when they can.
Future<String?> _whyNoOpenssl() async {
  try {
    final ProcessResult result = await Process.run('openssl', <String>[
      'version',
    ]);
    if (result.exitCode == 0) return null;
    return 'openssl version exited ${result.exitCode}: ${result.stderr}';
  } on ProcessException catch (error) {
    return 'openssl is not installed (${error.message}); it makes the '
        'throwaway certificate these TLS cases need';
  }
}

/// A self-signed certificate for localhost, valid for a day, in a fresh
/// directory under the system temp directory (which honours TMPDIR).
Future<Directory> _makeCertificate() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'dartvel-pg-tls-',
  );
  final ProcessResult result = await Process.run('openssl', <String>[
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
    'subjectAltName=DNS:localhost,IP:127.0.0.1',
    '-keyout',
    '${directory.path}/server.key.pem',
    '-out',
    '${directory.path}/server.pem',
  ]);
  if (result.exitCode != 0) {
    await directory.delete(recursive: true);
    throw StateError('openssl could not make a certificate: ${result.stderr}');
  }
  return directory;
}

/// A server that answers the SSLRequest with [reply]. On `S` it completes a
/// TLS handshake and then echoes what it receives, so a test can see bytes
/// cross the encrypted channel in both directions.
Future<(int, Future<void> Function())> _server(int reply) async {
  final ServerSocket server = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final List<Socket> open = <Socket>[];
  server.listen((Socket socket) {
    open.add(socket);
    // ignore: cancel_subscriptions -- destroyed with the socket.
    late StreamSubscription<List<int>> sub;
    sub = socket.listen((List<int> request) async {
      socket.add(<int>[reply]);
      if (reply != 0x53) return;
      // Hand the raw socket to TLS: stop reading it here first.
      sub.pause();
      try {
        final SecureSocket secure = await SecureSocket.secureServer(
          socket,
          _serverContext(),
          bufferedData: null,
        );
        open.add(secure);
        secure.listen(secure.add, onError: (Object _) {});
      } on Object {
        // The client refused the certificate; that is a test's expectation.
      }
    });
  });
  return (
    server.port,
    () async {
      for (final Socket socket in open) {
        socket.destroy();
      }
      await server.close();
    },
  );
}

Future<List<int>> _echo(DVPostgresConnection connection) async {
  final Completer<List<int>> got = Completer<List<int>>();
  final List<int> received = <int>[];
  connection.input.listen((List<int> chunk) {
    received.addAll(chunk);
    if (received.length >= 3 && !got.isCompleted) got.complete(received);
  });
  connection.write(<int>[7, 8, 9]);
  return got.future.timeout(_quick);
}

void main() async {
  final String? noOpenssl = await _whyNoOpenssl();

  setUpAll(() async {
    if (noOpenssl == null) _certificates = await _makeCertificate();
  });
  tearDownAll(() async {
    final Directory? directory = _certificates;
    _certificates = null;
    if (directory != null && directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  group('a server that says S', skip: noOpenssl, () {
    test('prefer: a server that says S is spoken to under TLS', () async {
      final (int port, Future<void> Function() close) = await _server(0x53);
      addTearDown(close);

      final DVPostgresConnection connection = await dvConnectPostgres(
        'localhost',
        port,
        sslMode: DVSslMode.prefer,
      ).timeout(_quick);
      addTearDown(connection.close);

      expect(await _echo(connection), <int>[7, 8, 9]);
    });

    test(
      'require: a self-signed certificate is accepted, as libpq does',
      () async {
        final (int port, Future<void> Function() close) = await _server(0x53);
        addTearDown(close);

        final DVPostgresConnection connection = await dvConnectPostgres(
          'localhost',
          port,
          sslMode: DVSslMode.require,
        ).timeout(_quick);
        addTearDown(connection.close);

        expect(await _echo(connection), <int>[7, 8, 9]);
      },
    );

    test(
      'verifyFull: an untrusted certificate is refused, never downgraded',
      () async {
        final (int port, Future<void> Function() close) = await _server(0x53);
        addTearDown(close);

        await expectLater(
          dvConnectPostgres(
            'localhost',
            port,
            sslMode: DVSslMode.verifyFull,
          ).timeout(_quick),
          throwsA(isA<HandshakeException>()),
        );
      },
    );

    test('verifyCa: an untrusted certificate is refused too', () async {
      // verify-ca promises a certificate that chains to a trusted root. A
      // self-signed one does not, and accepting it would make verifyCa no
      // stronger than require.
      final (int port, Future<void> Function() close) = await _server(0x53);
      addTearDown(close);

      await expectLater(
        dvConnectPostgres(
          'localhost',
          port,
          sslMode: DVSslMode.verifyCa,
        ).timeout(_quick),
        throwsA(isA<HandshakeException>()),
      );
    });
  });

  test('require: a server that declines TLS is refused at once', () async {
    final (int port, Future<void> Function() close) = await _server(0x4E);
    addTearDown(close);

    await expectLater(
      dvConnectPostgres(
        '127.0.0.1',
        port,
        sslMode: DVSslMode.require,
      ).timeout(_quick),
      throwsA(
        isA<DVPostgresException>().having(
          (DVPostgresException e) => e.message,
          'message',
          contains('refused TLS'),
        ),
      ),
    );
  });

  test('an error answer to the TLS request fails at once', () async {
    final (int port, Future<void> Function() close) = await _server(0x45);
    addTearDown(close);

    await expectLater(
      dvConnectPostgres(
        '127.0.0.1',
        port,
        sslMode: DVSslMode.prefer,
      ).timeout(_quick),
      throwsA(isA<DVPostgresException>()),
    );
  });
}
