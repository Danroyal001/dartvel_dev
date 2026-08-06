/// A browser cannot open a TCP socket to MySQL; query through a backend
/// function instead.
library dartvel_core.database.mysql_socket_unsupported;

import 'mysql.dart';

Future<DVMySqlConnection> dvConnectMySql(String host, int port) async =>
    throw UnsupportedError(
      'MySQL connections need dart:io sockets, which the web does not have. '
      'Query through a backend function instead.',
    );
