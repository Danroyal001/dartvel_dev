/// A browser cannot open a TCP socket to Postgres; query through a backend
/// function instead.
library dartvel_core.database.postgres_socket_unsupported;

import 'postgres.dart';

Future<DVPostgresConnection> dvConnectPostgres(
  String host,
  int port, {
  DVSslMode sslMode = DVSslMode.prefer,
}) async =>
    throw UnsupportedError(
      'Postgres connections need dart:io sockets, which the web does not '
      'have. Query through a backend function instead.',
    );
