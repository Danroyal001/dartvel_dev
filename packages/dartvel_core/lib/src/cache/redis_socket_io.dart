/// Socket-backed Redis connection for platforms with `dart:io`.
library dartvel_core.cache.redis_socket_io;

import 'dart:async';
import 'dart:io';

import 'redis.dart';

Future<DVRedisConnection> dvConnectRedis(String host, int port) async {
  // ignore: close_sinks — ownership passes to the connection, which closes it.
  final socket = await Socket.connect(host, port);
  return _SocketRedisConnection(socket);
}

class _SocketRedisConnection implements DVRedisConnection {
  final Socket _socket;

  _SocketRedisConnection(this._socket);

  @override
  Stream<List<int>> get input => _socket;

  @override
  void write(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
