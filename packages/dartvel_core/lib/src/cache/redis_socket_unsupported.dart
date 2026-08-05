/// A browser cannot open a TCP socket to Redis; talk to the cache through a
/// backend function instead.
library dartvel_core.cache.redis_socket_unsupported;

import 'redis.dart';

Future<DVRedisConnection> dvConnectRedis(String host, int port) async =>
    throw UnsupportedError(
      'Redis connections need dart:io sockets, which the web does not have. '
      'Reach the cache through a backend function instead.',
    );
