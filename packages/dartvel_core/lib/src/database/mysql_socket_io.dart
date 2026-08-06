/// Socket-backed MySQL connection for platforms with `dart:io`.
library dartvel_core.database.mysql_socket_io;

import 'dart:async';
import 'dart:io';

import 'mysql.dart';

Future<DVMySqlConnection> dvConnectMySql(String host, int port) async {
  // ignore: close_sinks — ownership passes to the connection, which closes it.
  final socket = await Socket.connect(host, port);
  return _SocketMySqlConnection(socket);
}

class _SocketMySqlConnection implements DVMySqlConnection {
  final Socket _socket;

  _SocketMySqlConnection(this._socket);

  @override
  Stream<List<int>> get input => _socket;

  @override
  void write(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
