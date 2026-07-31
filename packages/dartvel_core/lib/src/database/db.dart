// Database integration using Drift ORM
// Drift: https://drift.simonbinder.eu/
//
// Drift is a mature, type-safe Dart ORM with:
// - SQLite, PostgreSQL, MySQL support
// - Type-safe queries
// - Migrations
// - Code generation
// - Reactive queries

export 'package:drift/drift.dart';

/// Database configuration for Dartvel
class DartvelDatabase {
  static const String sqliteInMemory = ':memory:';

  /// Create a database from environment variables
  static String connectionStringFromEnv() {
    final dbType =
        const String.fromEnvironment('DB_TYPE', defaultValue: 'sqlite');

    switch (dbType.toLowerCase()) {
      case 'postgres':
      case 'postgresql':
        final host = const String.fromEnvironment('DATABASE_HOST',
            defaultValue: 'localhost');
        final port =
            const int.fromEnvironment('DATABASE_PORT', defaultValue: 5432);
        final name = const String.fromEnvironment('DATABASE_NAME',
            defaultValue: 'dartvel');
        final user = const String.fromEnvironment('DATABASE_USER',
            defaultValue: 'postgres');
        final password =
            const String.fromEnvironment('DATABASE_PASSWORD', defaultValue: '');
        return 'postgresql://$user:$password@$host:$port/$name';

      case 'mysql':
        final host = const String.fromEnvironment('DATABASE_HOST',
            defaultValue: 'localhost');
        final port =
            const int.fromEnvironment('DATABASE_PORT', defaultValue: 3306);
        final name = const String.fromEnvironment('DATABASE_NAME',
            defaultValue: 'dartvel');
        final user =
            const String.fromEnvironment('DATABASE_USER', defaultValue: 'root');
        final password =
            const String.fromEnvironment('DATABASE_PASSWORD', defaultValue: '');
        return 'mysql://$user:$password@$host:$port/$name';

      case 'sqlite':
      default:
        final path = const String.fromEnvironment('DATABASE_PATH',
            defaultValue: 'dartvel.db');
        return path;
    }
  }
}

/// Example: How to define a table with Drift
///
/// ```dart
/// // Define your table
/// class Users extends Table {
///   IntColumn get id => integer().autoIncrement()();
///   TextColumn get name => text()();
///   TextColumn get email => text().unique()();
///   BoolColumn get isActive => boolean().withDefault(const Constant(true))();
///   DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
/// }
///
/// // Define your database
/// @DriftDatabase(tables: [Users])
/// class AppDatabase extends _$AppDatabase {
///   AppDatabase(QueryExecutor e) : super(e);
///
///   @override
///   int get schemaVersion => 1;
///
///   // Queries
///   Future<List<User>> getAllUsers() => select(users).get();
///   Future<User?> getUserById(int id) => (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();
///   Future<int> createUser(UsersCompanion user) => into(users).insert(user);
///   Future<bool> updateUser(User user) => update(users).replace(user);
///   Future<int> deleteUser(int id) => (delete(users)..where((u) => u.id.equals(id))).go();
/// }
///
/// // Usage in your backend functions:
/// final db = AppDatabase(/* executor */);
/// final users = await db.getAllUsers();
/// await db.createUser(UsersCompanion.insert(name: 'John', email: 'john@example.com'));
/// ```

/// Quick Start Guide
///
/// 1. Add dependencies to pubspec.yaml:
/// ```yaml
/// dependencies:
///   drift: ^2.14.0
///   sqlite3_flutter_libs: ^0.5.0  # For mobile
///   path_provider: ^2.0.0
///   path: ^1.8.0
///
/// dev_dependencies:
///   drift_dev: ^2.14.0
///   build_runner: ^2.4.0
/// ```
///
/// 2. Create your database file (e.g., lib/database/database.dart):
/// ```dart
/// import 'package:drift/drift.dart';
///
/// part 'database.g.dart';
///
/// class Users extends Table {
///   IntColumn get id => integer().autoIncrement()();
///   TextColumn get name => text()();
///   TextColumn get email => text().unique()();
/// }
///
/// @DriftDatabase(tables: [Users])
/// class AppDatabase extends _$AppDatabase {
///   AppDatabase(QueryExecutor e) : super(e);
///
///   @override
///   int get schemaVersion => 1;
/// }
/// ```
///
/// 3. Run code generation:
/// ```bash
/// dart run build_runner build
/// ```
///
/// 4. Use in your backend functions:
/// ```dart
/// // lib/backend/functions/users/list.get.dart
/// import 'package:shelf/shelf.dart';
/// import 'package:your_app/database/database.dart';
/// import 'dart:convert';
///
/// Future<Response> handler(Request req) async {
///   final db = req.context['database'] as AppDatabase;
///
///   final users = await db.select(db.users).get();
///
///   return Response.ok(
///     jsonEncode(users.map((u) => {
///       'id': u.id,
///       'name': u.name,
///       'email': u.email,
///     }).toList()),
///     headers: {'Content-Type': 'application/json'},
///   );
/// }
/// ```

/// Migration Guide
///
/// Drift has excellent migration support:
///
/// ```dart
/// @DriftDatabase(tables: [Users, Posts])
/// class AppDatabase extends _$AppDatabase {
///   AppDatabase(QueryExecutor e) : super(e);
///
///   @override
///   int get schemaVersion => 2;  // Increment when schema changes
///
///   @override
///   MigrationStrategy get migration {
///     return MigrationStrategy(
///       onCreate: (Migrator m) async {
///         await m.createAll();
///       },
///       onUpgrade: (Migrator m, int from, int to) async {
///         if (from == 1) {
///           // Migration from v1 to v2
///           await m.createTable(posts);
///         }
///       },
///       beforeOpen: (details) async {
///         // Enable foreign keys for SQLite
///         if (executor.dialect == SqlDialect.sqlite) {
///           await customStatement('PRAGMA foreign_keys = ON');
///         }
///       },
///     );
///   }
/// }
/// ```

/// Benefits of Drift vs Custom ORM:
///
/// ✅ Type-safe queries (compile-time errors)
/// ✅ Auto-generated code (less boilerplate)
/// ✅ Multiple database support (SQLite, PostgreSQL, MySQL)
/// ✅ Stream-based reactive queries
/// ✅ Transaction support
/// ✅ Migration management
/// ✅ Battle-tested in production
/// ✅ Active maintenance
/// ✅ Excellent documentation
///
/// See DATABASE_ORM.md for complete setup guide.
