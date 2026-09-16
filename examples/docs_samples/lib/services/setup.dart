import '../dartvel_client/dartvel_client.dart';

// docs:start database-configure
void configureDatabase() {
  // A file beside the app. Tables come from dartvel db migrate.
  DV.Database.configure(SqliteDVDatabaseAdapter.file('dartvel.db'));
}
// docs:end

// docs:start database-postgres
void configurePostgres() {
  DV.Database.configure(DVPostgresDatabaseAdapter(
    host: 'db.internal',
    database: 'shop',
    user: 'shop',
    password: DV.Secrets.get('DATABASE_PASSWORD'),
  ));
}
// docs:end

// docs:start database-mysql
void configureMySql() {
  DV.Database.configure(DVMySqlDatabaseAdapter(
    host: 'db.internal',
    database: 'shop',
    user: 'shop',
    password: DV.Secrets.get('DATABASE_PASSWORD'),
  ));
}
// docs:end

void configureServices() {
  // docs:start start-configure
  DV.Auth.configure(DVLocalAuthProvider());
  DV.Database.configure(MemoryDVDatabaseAdapter());
  DV.Notifications.mail.useProvider(DVMemoryMailProvider());
  // docs:end
}

Future<void> rawQueries() async {
  // docs:start database-query
  final List<Map<String, Object?>> rows = await DV.Database.query(
    'select slug, title from posts where published = ?',
    <Object?>['true'],
  );
  final int changed = await DV.Database.execute(
    'update posts set published = ? where slug = ?',
    <Object?>['false', 'hello-world'],
  );
  // docs:end
  DV.log('${rows.length} $changed');
}
