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

/// Whether a live server was named. When it was, a suite runs against it and
/// fails -- never skips -- if it cannot connect.
bool get postgresTestConfigured =>
    (io.Platform.environment['DARTVEL_TEST_POSTGRES_PORT'] ?? '').isNotEmpty;

/// Drops every table in the current schema whose name starts with
/// [prefix], so a suite that expects an empty database per test gets one.
Future<void> postgresDropTables(
  DVPostgresDatabaseAdapter database,
  String prefix,
) async {
  final List<Map<String, Object?>> tables = await database.query(
    'SELECT table_name FROM information_schema.tables '
    'WHERE table_schema = current_schema() AND table_name LIKE ?',
    <Object?>['$prefix%'],
  );
  for (final Map<String, Object?> row in tables) {
    await database.execute('DROP TABLE IF EXISTS "${row['table_name']}"');
  }
}
