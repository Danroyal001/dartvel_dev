/// The database a process connects to, resolved from its environment.
///
/// `DATABASE_URL` -- the secret `dartvel infra` already declares -- says which
/// server and credentials, and `DARTVEL_DATABASE` names the database on that
/// server when a deployment wrote one. That split is what lets one preview
/// secret serve every branch while each branch reaches only its own database:
/// the URL can name production's database, or none, and the preview still
/// resolves its own.
library dartvel_core.database.connection;

import 'adapter.dart';
import 'adapters.dart' show SqliteDVDatabaseAdapter;
import 'mysql.dart';
import 'postgres.dart';

/// Which kind of server a connection is for.
enum DVDatabaseEngine { postgres, mysql, sqlite }

/// A resolved database connection. Printing one never prints its password.
final class DVDatabaseConnection {
  const DVDatabaseConnection({
    required this.engine,
    required this.database,
    this.host = '127.0.0.1',
    this.port = 0,
    this.user,
    this.password,
    this.sslMode = DVSslMode.prefer,
  });

  final DVDatabaseEngine engine;

  /// The database on the server, or the file for SQLite.
  final String database;
  final String host;
  final int port;
  final String? user;
  final String? password;
  final DVSslMode sslMode;

  /// Reads `postgres://`, `postgresql://`, `mysql://` and `sqlite://` URLs.
  ///
  /// A server URL that names no database is refused: connecting anyway would
  /// reach the server's default database, which on a shared server is
  /// somebody else's.
  static DVDatabaseConnection parse(String url) =>
      _parse(url, requireDatabase: true);

  /// The connection `DATABASE_URL` describes, with the database
  /// `DARTVEL_DATABASE` names when it names one. Null without `DATABASE_URL`.
  ///
  /// With `DARTVEL_DATABASE` set the URL may name no database at all -- a
  /// server and credentials shared by every preview.
  static DVDatabaseConnection? fromEnvironment(
    Map<String, String> environment,
  ) {
    final String? url = environment['DATABASE_URL']?.trim();
    if (url == null || url.isEmpty) return null;
    final String? named = environment['DARTVEL_DATABASE'];
    final bool hasName = named != null && named.isNotEmpty;
    final DVDatabaseConnection connection = _parse(
      url,
      requireDatabase: !hasName,
    );
    return hasName ? connection.withDatabase(named) : connection;
  }

  /// This connection aimed at [name] instead: the same server and
  /// credentials, or for SQLite the same directory and extension.
  DVDatabaseConnection withDatabase(String name) {
    String database = name;
    if (engine == DVDatabaseEngine.sqlite) {
      final int slash = this.database.lastIndexOf(RegExp(r'[/\\]'));
      final String directory = slash < 0
          ? ''
          : this.database.substring(0, slash + 1);
      final String file = this.database.substring(slash + 1);
      final int dot = file.lastIndexOf('.');
      database = '$directory$name${dot <= 0 ? '' : file.substring(dot)}';
    }
    return DVDatabaseConnection(
      engine: engine,
      database: database,
      host: host,
      port: port,
      user: user,
      password: password,
      sslMode: sslMode,
    );
  }

  /// An adapter for this connection. A server adapter connects on its first
  /// query, not here.
  DVDatabaseAdapter open() => switch (engine) {
    DVDatabaseEngine.postgres => DVPostgresDatabaseAdapter(
      host: host,
      port: port,
      database: database,
      user: user ?? 'postgres',
      password: password,
      sslMode: sslMode,
    ),
    DVDatabaseEngine.mysql => DVMySqlDatabaseAdapter(
      host: host,
      port: port,
      database: database,
      user: user ?? 'root',
      password: password ?? '',
      sslMode: sslMode,
    ),
    DVDatabaseEngine.sqlite => SqliteDVDatabaseAdapter.file(database),
  };

  static DVDatabaseConnection _parse(
    String url, {
    required bool requireDatabase,
  }) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException {
      // Not the URL itself: it carries a password.
      throw const FormatException('the database URL is not a URL');
    }
    final DVDatabaseEngine engine = switch (uri.scheme) {
      'postgres' || 'postgresql' => DVDatabaseEngine.postgres,
      'mysql' || 'mariadb' => DVDatabaseEngine.mysql,
      'sqlite' => DVDatabaseEngine.sqlite,
      _ => throw FormatException(
        'a database URL is postgres://, mysql:// or sqlite://, not '
        '${uri.scheme.isEmpty ? 'one with no scheme' : '${uri.scheme}://'}',
      ),
    };

    if (engine == DVDatabaseEngine.sqlite) {
      final String path = Uri.decodeComponent(uri.path);
      if (requireDatabase && path.isEmpty) {
        throw const FormatException('the sqlite URL names no file');
      }
      return DVDatabaseConnection(engine: engine, database: path);
    }

    if (uri.host.isEmpty) {
      throw FormatException('the ${uri.scheme} URL names no host');
    }
    final String database = Uri.decodeComponent(
      uri.path.startsWith('/') ? uri.path.substring(1) : uri.path,
    );
    if (requireDatabase && database.isEmpty) {
      throw FormatException(
        'the ${uri.scheme} URL names no database, and connecting anyway '
        'would reach whichever database the server defaults to',
      );
    }

    String? user;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final int colon = uri.userInfo.indexOf(':');
      user = Uri.decodeComponent(
        colon < 0 ? uri.userInfo : uri.userInfo.substring(0, colon),
      );
      if (colon >= 0) {
        password = Uri.decodeComponent(uri.userInfo.substring(colon + 1));
      }
    }

    final String? rawMode =
        uri.queryParameters['sslmode'] ?? uri.queryParameters['ssl-mode'];
    final DVSslMode sslMode = switch (rawMode?.toLowerCase()) {
      null => DVSslMode.prefer,
      'disable' || 'disabled' => DVSslMode.disable,
      'allow' || 'prefer' || 'preferred' => DVSslMode.prefer,
      'require' || 'required' => DVSslMode.require,
      'verify-ca' || 'verify_ca' => DVSslMode.verifyCa,
      'verify-full' || 'verify_identity' => DVSslMode.verifyFull,
      final String other => throw FormatException(
        'sslmode $other is not a TLS mode this reads',
      ),
    };

    return DVDatabaseConnection(
      engine: engine,
      database: database,
      host: uri.host,
      port: uri.hasPort
          ? uri.port
          : (engine == DVDatabaseEngine.postgres ? 5432 : 3306),
      user: user,
      password: password,
      sslMode: sslMode,
    );
  }

  @override
  String toString() => engine == DVDatabaseEngine.sqlite
      ? 'DVDatabaseConnection(sqlite://$database)'
      : 'DVDatabaseConnection(${engine.name}://'
            '${user == null ? '' : '$user@'}$host:$port/$database)';
}
