// The database a process connects to, resolved from its environment.
//
// A deployment writes DARTVEL_DATABASE and, until this, nothing read it: a
// preview's database was created, migrated and seeded, and the preview's own
// process had no way to find it. The connection comes from DATABASE_URL -- the
// secret dartvel infra already declares -- and DARTVEL_DATABASE names the
// database on that server, so one preview secret serves every branch and each
// branch still reaches only its own database.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('parse', () {
    test('a postgres URL, with its password decoded and its TLS mode', () {
      final DVDatabaseConnection c = DVDatabaseConnection.parse(
        'postgres://app:p%40ss@db.internal:6543/shop?sslmode=verify-full',
      );

      expect(c.engine, DVDatabaseEngine.postgres);
      expect(c.host, 'db.internal');
      expect(c.port, 6543);
      expect(c.user, 'app');
      expect(c.password, 'p@ss');
      expect(c.database, 'shop');
      expect(c.sslMode, DVSslMode.verifyFull);
    });

    test('postgresql and mysql take their default ports', () {
      final DVDatabaseConnection pg = DVDatabaseConnection.parse(
        'postgresql://db.internal/shop',
      );
      expect(pg.engine, DVDatabaseEngine.postgres);
      expect(pg.port, 5432);
      expect(pg.sslMode, DVSslMode.prefer);

      final DVDatabaseConnection my = DVDatabaseConnection.parse(
        'mysql://root:pw@db.internal/shop',
      );
      expect(my.engine, DVDatabaseEngine.mysql);
      expect(my.port, 3306);
      expect(my.database, 'shop');
    });

    test('a sqlite URL names a file', () {
      final DVDatabaseConnection c = DVDatabaseConnection.parse(
        'sqlite:///var/data/shop.db',
      );
      expect(c.engine, DVDatabaseEngine.sqlite);
      expect(c.database, '/var/data/shop.db');
    });

    test(
      'an unknown scheme, or a server with no database named, is refused',
      () {
        // A connection that silently defaulted the database would connect to
        // whatever the server's default is, which on a shared server is
        // somebody else's.
        expect(
          () => DVDatabaseConnection.parse('redis://cache.internal/0'),
          throwsFormatException,
        );
        expect(
          () => DVDatabaseConnection.parse('postgres://db.internal'),
          throwsFormatException,
        );
        expect(
          () => DVDatabaseConnection.parse('postgres://db.internal/'),
          throwsFormatException,
        );
      },
    );
  });

  group('fromEnvironment', () {
    test('DARTVEL_DATABASE names the database on DATABASE_URL\'s server', () {
      final DVDatabaseConnection c =
          DVDatabaseConnection.fromEnvironment(const <String, String>{
            'DATABASE_URL': 'postgres://app:pw@db.internal:5432/shop',
            'DARTVEL_DATABASE': 'shop_preview_feature_cart_c39f4dfa',
          })!;

      expect(c.database, 'shop_preview_feature_cart_c39f4dfa');
      expect(c.host, 'db.internal');
      expect(c.user, 'app');
    });

    test(
      'a server URL naming no database is enough when DARTVEL_DATABASE does',
      () {
        // The shared preview secret: one server and its credentials, for every
        // branch.
        final DVDatabaseConnection c =
            DVDatabaseConnection.fromEnvironment(const <String, String>{
              'DATABASE_URL': 'postgres://app:pw@db.internal:5432',
              'DARTVEL_DATABASE': 'shop_preview_feature_cart_c39f4dfa',
            })!;
        expect(c.database, 'shop_preview_feature_cart_c39f4dfa');
        expect(
          () => DVDatabaseConnection.fromEnvironment(const <String, String>{
            'DATABASE_URL': 'postgres://app:pw@db.internal:5432',
          }),
          throwsFormatException,
        );
      },
    );

    test('a sqlite file keeps its directory and extension', () {
      final DVDatabaseConnection c =
          DVDatabaseConnection.fromEnvironment(const <String, String>{
            'DATABASE_URL': 'sqlite:///var/data/shop.db',
            'DARTVEL_DATABASE': 'shop_preview_x_1234abcd',
          })!;
      expect(c.database, '/var/data/shop_preview_x_1234abcd.db');
    });

    test('without DATABASE_URL there is no connection to resolve', () {
      expect(
        DVDatabaseConnection.fromEnvironment(const <String, String>{
          'DARTVEL_DATABASE': 'shop_preview_x_1',
        }),
        isNull,
      );
    });

    test('without DARTVEL_DATABASE the URL is taken as written', () {
      expect(
        DVDatabaseConnection.fromEnvironment(const <String, String>{
          'DATABASE_URL': 'postgres://db.internal/shop',
        })!.database,
        'shop',
      );
    });
  });

  test('the password never appears when a connection is printed', () {
    final DVDatabaseConnection c = DVDatabaseConnection.parse(
      'postgres://app:hunter2@db.internal/shop',
    );
    expect('$c', isNot(contains('hunter2')));
    expect('$c', contains('db.internal'));
  });

  test('open hands back an adapter for the resolved database', () {
    final DVDatabaseAdapter pg = DVDatabaseConnection.parse(
      'postgres://app:pw@db.internal:6543/shop_preview_x_1',
    ).open();
    expect(pg, isA<DVPostgresDatabaseAdapter>());
    pg as DVPostgresDatabaseAdapter;
    expect(pg.database, 'shop_preview_x_1');
    expect(pg.host, 'db.internal');
    expect(pg.port, 6543);
    expect(pg.user, 'app');

    final DVDatabaseAdapter my = DVDatabaseConnection.parse(
      'mysql://root:pw@db.internal/shop',
    ).open();
    expect(my, isA<DVMySqlDatabaseAdapter>());
    expect((my as DVMySqlDatabaseAdapter).database, 'shop');
  });
}
