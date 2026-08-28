/// Socket-backed Postgres connection for platforms with `dart:io`.
library dartvel_core.database.postgres_socket_io;

import 'dart:async';
import 'dart:io';

import 'postgres.dart';
import 'postgres_tls.dart';

/// Open a connection, negotiating TLS first where the mode asks for it.
///
/// Postgres does not start TLS on a separate port. The client connects in the
/// clear, sends an eight-byte SSLRequest before any protocol message, and the
/// server answers with one byte: `S` to continue under TLS, `N` to decline.
/// Only then does the protocol begin, on whichever socket came out of that.
///
/// This is what a managed endpoint needs. Aurora, Neon, Supabase, Cloud SQL
/// and PlanetScale all require TLS and most refuse plaintext, so without this
/// the adapter reached a local server and nothing else.
Future<DVPostgresConnection> dvConnectPostgres(
  String host,
  int port, {
  DVSslMode sslMode = DVSslMode.prefer,
}) async {
  // ignore: close_sinks — ownership passes to the connection, which closes it.
  Socket socket = await Socket.connect(host, port);

  if (dvPostgresShouldRequestTls(sslMode)) {
    socket.add(dvPostgresSslRequest());
    await socket.flush();

    // Exactly one byte, and it must be read before anything else is sent.
    final Completer<int> answer = Completer<int>();
    late StreamSubscription<List<int>> waiting;
    waiting = socket.listen(
      (List<int> chunk) {
        if (chunk.isNotEmpty && !answer.isCompleted) {
          answer.complete(chunk.first);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!answer.isCompleted) answer.completeError(error, stack);
      },
      onDone: () {
        if (!answer.isCompleted) {
          answer.completeError(
            const DVPostgresException(
              'The server closed the connection during TLS negotiation.',
            ),
          );
        }
      },
    );

    final DVPostgresSslReply reply;
    try {
      reply = dvPostgresSslReply(await answer.future);
    } finally {
      // Cancelled before the socket is upgraded: a subscription left on the
      // raw socket would swallow the first bytes of the encrypted stream.
      await waiting.cancel();
    }

    switch (reply) {
      case DVPostgresSslReply.proceed:
        socket = await SecureSocket.secure(
          socket,
          host: host,
          // verify-ca proves the certificate chains to a trusted root and
          // does not prove you reached the host you asked for, so only
          // verify-full checks the name. Below that, the certificate is not
          // checked at all: encrypted against a passive listener, and not
          // against an active one.
          onBadCertificate: dvPostgresChecksHostname(sslMode)
              ? null
              : (X509Certificate certificate) => true,
        );
      case DVPostgresSslReply.refused:
        if (dvPostgresRefusalIsFatal(sslMode)) {
          await socket.close();
          throw DVPostgresException(
            'The server refused TLS and sslMode is '
            '${sslMode.name}. Carrying on would send the password in the '
            'clear while the connection looked encrypted.',
          );
        }
      case DVPostgresSslReply.error:
        await socket.close();
        throw const DVPostgresException(
          'The server answered the TLS request with an error rather than a '
          'yes or a no.',
        );
    }
  }

  return _SocketPostgresConnection(socket);
}

class _SocketPostgresConnection implements DVPostgresConnection {
  final Socket _socket;

  _SocketPostgresConnection(this._socket);

  @override
  Stream<List<int>> get input => _socket;

  @override
  void write(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
