/// A browser cannot open a TCP socket to Memcached; reach the cache through a
/// backend function instead.
library dartvel_core.cache.memcached_socket_unsupported;

import 'memcached.dart';

Future<DVMemcachedConnection> dvConnectMemcached(String host, int port) async =>
    throw UnsupportedError(
      'Memcached connections need dart:io sockets, which the web does not '
      'have. Reach the cache through a backend function instead.',
    );
