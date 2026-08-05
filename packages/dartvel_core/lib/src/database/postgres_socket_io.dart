/// Socket-backed Postgres connection for platforms with `dart:io`.
library dartvel_core.database.postgres_socket_io;

import 'dart:async';
import 'dart:io';

import 'postgres.dart';

Future<DVPostgresConnection> dvConnectPostgres(String host, int port) async {
  // ignore: close_sinks — ownership passes to the connection, which closes it.
  final socket = await Socket.connect(host, port);
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
