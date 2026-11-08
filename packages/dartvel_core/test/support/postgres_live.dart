// Where the live Postgres tests find their server.
//
// DARTVEL_TEST_POSTGRES_HOST, _PORT, _DATABASE, _USER and _PASSWORD, as
// framework_tables_postgres_live_test.dart reads them; unset, a local
// server at 127.0.0.1:5432 with a dartvel_test database and no password.
import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';

String get postgresTestHost =>
    io.Platform.environment['DARTVEL_TEST_POSTGRES_HOST'] ?? '127.0.0.1';

int get postgresTestPort =>
    int.tryParse(io.Platform.environment['DARTVEL_TEST_POSTGRES_PORT'] ?? '') ??
    5432;

/// `host:port`, for skip messages.
String get postgresTestAddress => '$postgresTestHost:$postgresTestPort';

/// Whether anything listens where the tests will connect.
Future<bool> postgresTestServerReachable() async {
  try {
    final io.Socket socket = await io.Socket.connect(
      postgresTestHost,
      postgresTestPort,
      timeout: const Duration(seconds: 1),
    );
    await socket.close();
    return true;
  } on io.SocketException {
    return false;
  }
}

/// An adapter for the test server, in the adapter's default TLS mode.
DVPostgresDatabaseAdapter postgresTestAdapter() => DVPostgresDatabaseAdapter(
      host: postgresTestHost,
      port: postgresTestPort,
      database:
          io.Platform.environment['DARTVEL_TEST_POSTGRES_DATABASE'] ??
              'dartvel_test',
      user: io.Platform.environment['DARTVEL_TEST_POSTGRES_USER'] ?? 'postgres',
      password: io.Platform.environment['DARTVEL_TEST_POSTGRES_PASSWORD'],
    );
