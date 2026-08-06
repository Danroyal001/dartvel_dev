/// Socket-backed Memcached connection for platforms with `dart:io`.
library dartvel_core.cache.memcached_socket_io;

import 'dart:async';
import 'dart:io';

import 'memcached.dart';

Future<DVMemcachedConnection> dvConnectMemcached(String host, int port) async {
  // ignore: close_sinks — ownership passes to the connection, which closes it.
  final socket = await Socket.connect(host, port);
  return _SocketMemcachedConnection(socket);
}

class _SocketMemcachedConnection implements DVMemcachedConnection {
  final Socket _socket;

  _SocketMemcachedConnection(this._socket);

  @override
  Stream<List<int>> get input => _socket;

  @override
  void write(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
