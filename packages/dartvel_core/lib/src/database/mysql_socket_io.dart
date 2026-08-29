/// Socket-backed MySQL connection for platforms with `dart:io`.
library dartvel_core.database.mysql_socket_io;

import 'dart:async';
import 'dart:io';

import 'mysql.dart';
import 'postgres_tls.dart' show DVSslMode;

Future<DVMySqlConnection> dvConnectMySql(String host, int port) async {
  // ignore: close_sinks — ownership passes to the connection, which closes it.
  final socket = await Socket.connect(host, port);
  return _SocketMySqlConnection(socket);
}

class _SocketMySqlConnection implements DVMySqlConnection {
  Socket _socket;
  StreamController<List<int>>? _relay;
  StreamSubscription<List<int>>? _pump;

  _SocketMySqlConnection(this._socket);

  @override
  Future<void> upgradeToTls({
    required String host,
    required DVSslMode sslMode,
  }) async {
    // The reader is already listening to the plaintext socket, so the stream
    // it holds has to survive the swap. Everything is relayed through one
    // controller and the pump is repointed at the secure socket -- handing
    // the reader a different Stream mid-handshake would lose the first
    // encrypted packet, which is the auth result.
    final StreamController<List<int>> relay =
        _relay ??= StreamController<List<int>>();
    await _pump?.cancel();

    final Socket secure = await SecureSocket.secure(
      _socket,
      host: host,
      // verify-ca proves the certificate chains to a trusted root; it does not
      // prove you reached the host you asked for, so only verify-full checks
      // the name.
      onBadCertificate: sslMode == DVSslMode.verifyFull
          ? null
          : (X509Certificate certificate) => true,
    );
    _socket = secure;
    _pump = secure.listen(
      relay.add,
      onError: relay.addError,
      onDone: relay.close,
    );
  }

  @override
  Stream<List<int>> get input {
    // Relayed from the first read, so an upgrade later does not replace the
    // stream the reader is already subscribed to.
    final StreamController<List<int>> relay =
        _relay ??= StreamController<List<int>>();
    _pump ??= _socket.listen(
      relay.add,
      onError: relay.addError,
      onDone: relay.close,
    );
    return relay.stream;
  }

  @override
  void write(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
