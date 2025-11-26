# Database ORM - Drift Integration

Dartvel uses **Drift** (formerly Moor) as its ORM - a mature, type-safe database library for Dart.

## Why Drift?

✅ **Type-safe queries** - Compile-time error checking  
✅ **Multi-database** - SQLite, PostgreSQL, MySQL  
✅ **Code generation** - Less boilerplate  
✅ **Reactive queries** - Stream-based updates  
✅ **Migrations** - Built-in schema versioning  
✅ **Battle-tested** - Used in production apps  
✅ **Active development** - Regular updates

## Quick Start

### 1. Add Dependencies

```yaml
# pubspec.yaml
dependencies:
  drift: ^2.14.0
  sqlite3_flutter_libs: ^0.5.0  # For mobile
  path_provider: ^2.0.0
  path: ^1.8.0

dev_dependencies:
  drift_dev: ^2.14.0
  build_runner: ^2.4.0
```

### 2. Define Your Database

```dart
// lib/database/database.dart
import 'package:drift/drift.dart';

part 'database.g.dart';

// Define tables
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get email => text().unique()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Posts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get title => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// Define database
@DriftDatabase(tables: [Users, Posts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);
  
  @override
  int get schemaVersion => 1;
  
  // Queries
  Future<List<User>> getAllUsers() => select(users).get();
  
  Future<User?> getUserById(int id) => 
    (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();
  
  Future<int> createUser(UsersCompanion user) => 
    into(users).insert(user);
  
  Future<bool> updateUser(User user) => 
    update(users).replace(user);
  
  Future<int> deleteUser(int id) => 
    (delete(users)..where((u) => u.id.equals(id))).go();
    
  // Complex query with joins
  Future<List<PostWithUser>> getPostsWithUsers() {
    final query = select(posts).join([
      leftOuterJoin(users, users.id.equalsExp(posts.userId)),
    ]);
    
    return query.map((row) {
      return PostWithUser(
        post: row.readTable(posts),
        user: row.readTableOrNull(users),
      );
    }).get();
  }
}

class PostWithUser {
  final Post post;
  final User? user;
  
  PostWithUser({required this.post, this.user});
}
```

### 3. Generate Code

```bash
dart run build_runner build
# Or watch mode:
dart run build_runner watch
```

### 4. Use in Backend Functions

```dart
// lib/backend/functions/users/list.get.dart
import 'package:shelf/shelf.dart';
import 'package:your_app/database/database.dart';
import 'dart:convert';

Future<Response> handler(Request req) async {
  final db = req.context['database'] as AppDatabase;
  
  // Type-safe query!
  final users = await db.getAllUsers();
  
  return Response.ok(
    jsonEncode(users.map((u) => {
      'id': u.id,
      'name': u.name,
      'email': u.email,
      'isActive': u.isActive,
    }).toList()),
    headers: {'Content-Type': 'application/json'},
  );
}
```

```dart
// lib/backend/functions/users/create.post.dart
import 'package:shelf/shelf.dart';
import 'package:your_app/database/database.dart';
import 'dart:convert';

Future<Response> handler(Request req) async {
  final db = req.context['database'] as AppDatabase;
  final body = jsonDecode(await req.readAsString());
  
  // Type-safe insert!
  final userId = await db.createUser(
    UsersCompanion.insert(
      name: body['name'],
      email: body['email'],
    ),
  );
  
  final user = await db.getUserById(userId);
  
  return Response.ok(
    jsonEncode({
      'id': user!.id,
      'name': user.name,
      'email': user.email,
    }),
    headers: {'Content-Type': 'application/json'},
  );
}
```

## Database Setup

### SQLite (Default)

```dart
// lib/database/connection.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

Future<AppDatabase> createDatabase() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  final file = File(p.join(dbFolder.path, 'app.db'));
  
  return AppDatabase(NativeDatabase(file));
}
```

### PostgreSQL

```dart
// Add dependency: postgres: ^2.6.0

import 'package:drift/drift.dart';
import 'package:postgres/postgres.dart';

AppDatabase createPostgresDatabase() {
  final connection = PostgreSQLConnection(
    'localhost',
    5432,
    'dartvel',
    username: 'postgres',
    password: 'password',
  );
  
  return AppDatabase(PostgresExecutor(connection));
}
```

### MySQL

```dart
// Add dependency: mysql1: ^0.20.0

import 'package:drift/drift.dart';
import 'package:mysql1/mysql1.dart';

Future<AppDatabase> createMySQLDatabase() async {
  final connection = await MySqlConnection.connect(
    ConnectionSettings(
      host: 'localhost',
      port: 3306,
      user: 'root',
      password: 'password',
      db: 'dartvel',
    ),
  );
  
  return AppDatabase(MySQLExecutor(connection));
}
```

## Migrations

```dart
@DriftDatabase(tables: [Users, Posts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);
  
  @override
  int get schemaVersion => 2;  // Increment on schema changes
  
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          // Add new column
          await m.addColumn(users, users.isActive);
        }
      },
      beforeOpen: (details) async {
        // Enable foreign keys
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
```

## Advanced Features

### Reactive Queries (Streams)

```dart
// Watch for changes
Stream<List<User>> watchAllUsers() => 
  select(users).watch();

// In Flutter
StreamBuilder<List<User>>(
  stream: db.watchAllUsers(),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return CircularProgressIndicator();
    
    final users = snapshot.data!;
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) => ListTile(
        title: Text(users[index].name),
      ),
    );
  },
)
```

### Transactions

```dart
Future<void> transferMoney(int fromId, int toId, double amount) async {
  await db.transaction(() async {
    await db.deductBalance(fromId, amount);
    await db.addBalance(toId, amount);
  });
}
```

### Custom Queries

```dart
Future<List<User>> searchUsers(String query) {
  return (select(users)
    ..where((u) => u.name.like('%$query%') | u.email.like('%$query%')))
    .get();
}
```

## Best Practices

1. **Use Companions for inserts/updates**
   ```dart
   UsersCompanion.insert(name: 'John', email: 'john@example.com')
   ```

2. **Leverage type safety**
   ```dart
   // Compile error if column doesn't exist!
   select(users)..where((u) => u.nonExistentColumn.equals(5))
   ```

3. **Use streams for reactive UI**
   ```dart
   Stream<List<User>> watchUsers() => select(users).watch();
   ```

4. **Handle migrations properly**
   ```dart
   if (from < 2) await m.addColumn(users, users.newColumn);
   ```

5. **Close database when done**
   ```dart
   await db.close();
   ```

## Resources

- [Drift Documentation](https://drift.simonbinder.eu/)
- [Drift Examples](https://github.com/simolus3/drift/tree/develop/examples)
- [Migration Guide](https://drift.simonbinder.eu/docs/advanced-features/migrations/)

## Comparison with Custom ORM

| Feature | Custom ORM | Drift |
|---------|-----------|-------|
| Type Safety | ❌ Runtime | ✅ Compile-time |
| Database Support | ⚠️ Manual | ✅ Multi-DB |
| Code Generation | ❌ No | ✅ Yes |
| Migrations | ⚠️ Basic | ✅ Advanced |
| Reactive Queries | ❌ No | ✅ Streams |
| Production Ready | ⚠️ Needs testing | ✅ Battle-tested |
| Maintenance | ⚠️ Our responsibility | ✅ Active community |

Drift is the production-ready choice! 🚀
