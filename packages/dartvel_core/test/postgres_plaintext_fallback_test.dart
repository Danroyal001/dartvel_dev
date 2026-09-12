// What happens after a server declines TLS.
//
// `prefer` is the default mode, and its whole point is to ask for TLS and
// carry on without it — which is the ordinary shape of a local or containerised
// Postgres that was never given a certificate. The asking is done by listening
// to the socket for the one byte the server answers with.
//
// A `Socket` is a single-subscription stream. When the answer is `S` the
// socket is replaced by a `SecureSocket`, which is a new stream, so the
// adapter can listen to it. When the answer is `N` the code carries on with
// the *same* socket, and the adapter's own `input.listen(...)` then throws
// `Bad state: Stream has already been listened to` — so the mode whose job is
// to fall back to plaintext could not produce a usable connection at all.
//
// No Postgres here: a server socket that answers the SSLRequest with one byte
// is the whole of the protocol this exercises.
import 'dart:async';
import 'dart:io';

import 'package:dartvel_core/src/database/postgres_socket_io.dart';
import 'package:dartvel_core/src/database/postgres.dart';
import 'package:dartvel_core/src/database/postgres_tls.dart';
import 'package:test/test.dart';

/// A server that answers the SSLRequest with [reply], then sends [after].
///
/// Returns the port it bound. Closes with the returned function.
Future<(int, Future<void> Function())> _serverDeclining(
  int reply, {
  List<int> after = const <int>[],
}) async {
  final ServerSocket server =
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

  server.listen((Socket socket) {
    late StreamSubscription<List<int>> sub;
    sub = socket.listen((List<int> request) {
      // The eight-byte SSLRequest is the only thing sent before the answer.
      socket.add(<int>[reply]);
      if (after.isNotEmpty) socket.add(after);
      sub.onData((List<int> _) {});
    });
  });

  return (server.port, () async => server.close());
}

void main() {
  test('a connection survives the server declining TLS', () async {
    // 0x4E is 'N': the server declines, and `prefer` carries on in plaintext.
    final (int port, Future<void> Function() close) =
        await _serverDeclining(0x4E);
    addTearDown(close);

    final DVPostgresConnection connection = await dvConnectPostgres(
      '127.0.0.1',
      port,
      sslMode: DVSslMode.prefer,
    );
    addTearDown(connection.close);

    // The adapter does exactly this as its first act after connecting, and it
    // is what threw: the socket had already been listened to during the
    // negotiation above.
    expect(
      () => connection.input.listen((List<int> _) {}),
      returnsNormally,
      reason: 'after a declined TLS request the connection must still be '
          'readable — carrying on in plaintext is what prefer means',
    );
  });

  test('bytes sent after the refusal are not swallowed by the negotiation',
      () async {
    // The negotiation reads one byte out of a chunk. A server is free to put
    // the refusal and the first protocol bytes in one segment, and anything
    // past the first byte was being dropped on the floor.
    final (int port, Future<void> Function() close) =
        await _serverDeclining(0x4E, after: <int>[1, 2, 3]);
    addTearDown(close);

    final DVPostgresConnection connection = await dvConnectPostgres(
      '127.0.0.1',
      port,
      sslMode: DVSslMode.prefer,
    );
    addTearDown(connection.close);

    final List<int> received = <int>[];
    final Completer<void> got = Completer<void>();
    connection.input.listen((List<int> chunk) {
      received.addAll(chunk);
      if (received.length >= 3 && !got.isCompleted) got.complete();
    });

    await got.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('the bytes after the refusal never arrived: '
          'got $received'),
    );
    expect(received, <int>[1, 2, 3]);
  });
}
