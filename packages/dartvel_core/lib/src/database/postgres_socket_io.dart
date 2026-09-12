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
    //
    // Everything after that byte is the protocol's, so it is relayed rather
    // than dropped: a server may put its answer and its first protocol bytes
    // in one segment, and this listener is the only reader at the time.
    final Completer<int> answer = Completer<int>();
    final StreamController<List<int>> relay = StreamController<List<int>>();
    late StreamSubscription<List<int>> waiting;
    waiting = socket.listen(
      (List<int> chunk) {
        if (!answer.isCompleted) {
          if (chunk.isEmpty) return;
          answer.complete(chunk.first);
          if (chunk.length > 1) relay.add(chunk.sublist(1));
          return;
        }
        relay.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (!answer.isCompleted) {
          answer.completeError(error, stack);
        } else if (!relay.isClosed) {
          relay.addError(error, stack);
        }
      },
      onDone: () {
        if (!answer.isCompleted) {
          answer.completeError(
            const DVPostgresException(
              'The server closed the connection during TLS negotiation.',
            ),
          );
        }
        // The socket is done, so nothing more can arrive to relay. Nothing
        // waits on this close: onDone cannot be async, and a reader of the
        // relay learns the stream ended from the stream itself.
        if (!relay.isClosed) unawaited(relay.close());
      },
    );

    final DVPostgresSslReply reply;
    try {
      reply = dvPostgresSslReply(await answer.future);
    } on Object {
      await waiting.cancel();
      if (!relay.isClosed) await relay.close();
      rethrow;
    }

    switch (reply) {
      case DVPostgresSslReply.proceed:
        // Cancelled before the socket is upgraded: a subscription left on the
        // raw socket would swallow the first bytes of the encrypted stream.
        // The relay goes with it — what follows arrives on the SecureSocket,
        // which is a stream of its own and can be listened to.
        await waiting.cancel();
        if (!relay.isClosed) await relay.close();
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
          await waiting.cancel();
          if (!relay.isClosed) await relay.close();
          await socket.close();
          throw DVPostgresException(
            'The server refused TLS and sslMode is '
            '${sslMode.name}. Carrying on would send the password in the '
            'clear while the connection looked encrypted.',
          );
        }
        // Carrying on in plaintext, on the socket that was just listened to.
        // A Socket is a single-subscription stream, so it cannot be handed to
        // the adapter to listen to a second time -- the negotiation spent it.
        // The subscription that read the answer stays, feeding the relay the
        // adapter reads instead.
        return _RelayedPostgresConnection(socket, relay, waiting);
      case DVPostgresSslReply.error:
        await waiting.cancel();
        if (!relay.isClosed) await relay.close();
        await socket.close();
        throw const DVPostgresException(
          'The server answered the TLS request with an error rather than a '
          'yes or a no.',
        );
    }
  }

  return _SocketPostgresConnection(socket);
}

/// A plaintext connection whose socket has already been read once.
///
/// Only the declined-TLS path produces one: the bytes arrive through the
/// subscription the negotiation opened, because the socket cannot be listened
/// to again.
class _RelayedPostgresConnection implements DVPostgresConnection {
  final Socket _socket;
  final StreamController<List<int>> _relay;
  final StreamSubscription<List<int>> _subscription;

  _RelayedPostgresConnection(this._socket, this._relay, this._subscription);

  @override
  Stream<List<int>> get input => _relay.stream;

  @override
  void write(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _subscription.cancel();
    if (!_relay.isClosed) await _relay.close();
    await _socket.close();
  }
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
