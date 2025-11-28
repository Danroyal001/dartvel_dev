# Dartvel Framework - Master Context & Instructions

> **Note to AI**: This file serves as the centralized source of truth for project context, coding standards, and current objectives. Read this first.

## 1. Project Overview
**Dartvel** is a framework for simplifying the creation and deployment of fullstack Flutter and Dart apps.
It aims to be the **"Next.js/Expo of Flutter"**, merging features from Serverpod, Expo, Shorebird, Codemagic, Next.js, and Nuxt.js.

**Core Goals:**
- **Structured Project Organization**
- **File-based Routing** (Next.js style)
- **Backend Functions** (WinterCG compliant)
- **OTA Updates** (Shorebird)
- **Cloud Builds** (Codemagic)
- **Multiplatform Support**: Android, iOS, Windows, macOS, Linux, Android TV, Apple TV, Tizen, WebOS, Embedded Linux.

---

## 2. Current Objective (Phase 6: Expansion & Completion)
**User Prompt:**
> "Continue, go CRAZY with the project, build out the entire framework to completion... Commit along the way so it's easy to revert, with support for android, ios, windows, macOS, linux, androdi TV, appleTV, Tizen, WebOS, embedded linux. Test end to end extensively... Test all the dartvel commands and their aliases... Let's integrate build_runner so we don't have to generate files manually. For the dartvel_shelf backend, make sure all heavy lifting happens in rust, with little to no unsafe code and minimal ffi hops. Update the documentation for each module and the top level documentation to match."

**Key Tasks:**
1.  **Build Runner Integration**: Automate file generation.
2.  **Rust Backend Optimization**: Minimize FFI hops, ensure safety.
3.  **Cross-Platform Support**: Verify all listed platforms.
4.  **Extensive Testing**: E2E tests for all commands and flows.
5.  **Documentation**: Update all modules.

---

## 3. Code Generation Guidelines (Best Practices)

### Output Contract
- **Preface**: Objective, assumptions, inputs/outputs.
- **Self-contained code**: Runs as-is.
- **Comments**: Explain *why*, not *what*.
- **Tests**: Basic unit or integration tests.

### Readability & Style
- **Naming**: `snake_case` (Python/Dart files), `camelCase` (JS/Dart vars), `PascalCase` (Types).
- **Functions**: Small, single responsibility.
- **Dependencies**: Minimal, justified.

### Security
- **Input Validation**: Sanitize all external inputs.
- **Secrets**: NEVER hardcode. Use env vars (`PUBLIC_*` for client-safe).
- **Filesystem**: Safe paths, no traversal.

### Efficiency
- **Data Structures**: Choose wisely (Big-O).
- **Async I/O**: Prefer over blocking.
- **Caching**: Use where appropriate.

### "Never Do This"
- ❌ Hardcode secrets.
- ❌ Use `eval`/`exec`.
- ❌ Swallow exceptions silently.
- ❌ **USE EMOJIS ANYWHERE IN THE CODEBASE** (Strictly forbidden, except where explicitly allowed).

---

## 4. Special Instruction: Doctor Command
**File**: `packages/dartvel_cli/lib/src/commands/doctor_command.dart`

**Requirements:**
1. ✅ Work from ANY directory (no pubspec.yaml required).
2. ✅ Check system deps: Dart, Flutter, Git, Shorebird (optional), Codemagic (optional).
3. ✅ Run `flutter doctor -v` at the end.
4. ⛔ **ABSOLUTELY NO EMOJIS**. Use `[+]`, `[-]`, `[!]`.
5. ✅ **Clear Boundaries**: Use separator lines between sections.

**Expected Output Format:**
```text
Dartvel Doctor
==================================================
[+] Dart SDK: ...
--------------------------------------------------
Optional Tools
--------------------------------------------------
[-] Shorebird: ...
...
==================================================
Flutter Doctor Output
==================================================
...
```

---

## 5. Development Context & Roadmap (History)

### Completed Phases (v0.1 -> v0.3)
- **Phase 0**: Setup, Config Migration, Env Handling (`.env`).
- **Phase 1**: Routing, UI Enhancements (`.loading.dart`, `.error.dart`), SSG basics.
- **Phase 2**: CLI Improvements (`create`, `preview`, `plugin add`, `updates push`).
- **Phase 3**: OTA (Shorebird) and Plugins.
- **Phase 4**: Documentation and Testing.
- **Phase 5**: Rust Backend Integration (FFI), CLI Refactor.

### Feature Checklist (Remaining/Ongoing)
- [ ] Advanced Routing (Deeplinking, URL scheme, Bundle splitting)
- [ ] Database Integration / ORM
- [ ] Authentication / Middleware
- [ ] Caching & Queued Tasks
- [ ] Multiplatform Support (TVs, Embedded)
- [ ] Analytics & Monitoring
- [ ] Admin/CMS Dashboard
- [ ] Drag-and-Drop / AI Code Assist

---

## 6. Project Structure (Reference)
- `packages/dartvel_core`: Core helpers, types.
- `packages/dartvel_flutter`: Flutter widgets, SEO, transitions.
- `packages/dartvel_cli`: CLI tool (`dartvel`).
- `packages/dartvel_shelf`: Rust-powered backend server.
- `packages/dartvel_generator`: Code generation logic.
- `example/dartvel_example`: Reference implementation.

---

## 7. Feature Checklist (Comprehensive)

### Core Features
1. [ ] Structured Project Organization
2. [ ] Dartvel CLI, Scaffolding generators
3. [ ] Platform API access
4. [ ] Advanced Routing (File-based, Config based, Deeplinking, URL scheme, Route bundle splitting)
5. [ ] Backend functions and API Management + Streaming + WebSockets (WinterCG/WinterTC Compliant)
6. [ ] Over-the-Air (OTA) Updates and patches (Like Expo Updates, powered by Codemagic and ShoreBird)
7. [ ] Templating
8. [ ] Database integration / Migrations / ORM
9. [ ] Authentication, Authorization, Middleware
10. [ ] Caching
11. [ ] Push and Email (requires server) Notifications
12. [ ] Queued Tasks / Background tasks / Scheduled Tasks
13. [ ] Permissions management
14. [ ] Config management
15. [ ] UI Scaffolding (Forms, Tables, Premium Starter Kits, etc)
16. [ ] Multiplatform support (Android, iOS/iPadOS, Web, Windows, Linux, macOS, Android TV, WearOS, tvOS, watchOS, WebOS, Tizen)
17. [ ] Internationalization and Localization
18. [ ] Quick Previews in the preview app (Like Expo Go)
19. [ ] Cloud builds via DartvelCloud (Like EAS, powered by CodeMagic)
20. [ ] Store Signing and publishing via DartvelCloud
21. [ ] Environment variables management
22. [ ] Image/Asset optimization
23. [ ] Analytics, Monitoring, Crashlytics and Logging
24. [ ] Event system, Pub/Sub
25. [ ] Web SEO
26. [ ] Custom CLI Commands
27. [ ] Dartvel Cloud (Edge Deployment)
28. [ ] In-build opt-in Admin/CMS dashboard
29. [ ] Server hydration / initial server data
30. [ ] Utils for strings, arrays, hashmaps, dates, cross-platform concurrency
31. [ ] Remote config / Feature flags
32. [ ] Drag-and-Drop / AI-Driven Development with Code Assist
33. [ ] Compliance features (audit logs, GDPR tools, HIPAA-ready)

\n\n# Detailed Documentation\n
# API Reference

## Core Modules

### Authentication (`dartvel_core/auth`)

```dart
// Initialize auth
Auth.initialize(MyAuthProvider());

// Sign in
final user = await Auth.instance.signIn('email@example.com', 'password');
```

### Database (`dartvel_core/database`)

```dart
// Access database
final db = DatabaseManager.instance.db;

// Run transaction
await db.transaction(() async {
  // ...
});
```

### Caching (`dartvel_core/cache`)

```dart
final cache = InMemoryCache();
await cache.set('key', 'value', ttl: Duration(minutes: 5));
```

### Background Tasks (`dartvel_core/tasks`)

```dart
TaskManager.instance.register(MyTask());
await TaskManager.instance.schedule('my_task', {'data': 123});
```

## Flutter Widgets

### SEO (`dartvel_flutter/seo`)

```dart
SeoHead(
  metadata: SeoMetadata(
    title: 'My Page',
    description: 'Description',
  ),
  child: Scaffold(...),
)
```

### i18n (`dartvel_flutter/i18n`)

```dart
Text('hello_world'.tr())
```
# Dartvel Architecture

Dartvel is a full-stack framework designed for building high-performance, multi-platform applications with Flutter and Dart.

## System Overview

Dartvel consists of four main components:

1.  **Dartvel CLI (`dartvel_cli`)**: The command-line interface for project management, code generation, and development tools.
2.  **Dartvel Core (`dartvel_core`)**: The core library providing essential utilities, types, and abstractions for the framework.
3.  **Dartvel Flutter (`dartvel_flutter`)**: The Flutter package containing widgets, state management, and platform integrations.
4.  **Dartvel Shelf (`dartvel_shelf`)**: The backend server implementation powered by Rust and Actix Web via FFI.

## Component Interactions

### Client-Side (Flutter)

The Flutter client interacts with the backend via generated API clients. The `dartvel_flutter` package provides:

-   **Routing**: File-based routing with `go_router` integration.
-   **State Management**: Built-in state management for data fetching and caching.
-   **Platform Integration**: Abstractions for platform-specific features like SEO and i18n.

### Server-Side (Rust + Dart)

The backend is a hybrid system:

-   **Rust Core**: Handles low-level HTTP parsing, connection management, and heavy lifting (compression, static files).
-   **Dart Logic**: Business logic and API handlers are written in Dart.
-   **FFI Bridge**: Communication between Rust and Dart happens via a high-performance FFI layer.

## FFI Design

The FFI boundary is designed to minimize overhead:

-   **Shared Memory**: Where possible, memory is shared to avoid copying.
-   **Batching**: Operations are batched to reduce the number of FFI calls.
-   **Asynchronous Handling**: Requests are handled asynchronously to prevent blocking the main thread.

## Security

-   **Environment Variables**: Secrets are obfuscated in the client build.
-   **Authentication**: Built-in JWT and session management.
-   **CORS**: Configurable CORS support at the Rust level.

# Migration to dartvel v0.1

- Replace `host` → `backendHost`, `port` → `backendPort` in `pubspec.yaml`.
- Rename `seoDefaults` → `webSeoDefaults`.
- Update your pages to use `buildWebSeo(...)` (instead of `buildSeo(...)`).
- Ensure `prodBackendHost` is set before running `dartvel build` (if you use that command).

# Routing (File-System) — dartvel v0.1

- Pages live under **`lib/pages`** (configurable via `pagesDir`).
- Each file must be named **`*.page.dart`** and define a **class ending with `Page`** that **extends `DartvelPage`**.
- File path → URL path mapping:

| File | Route |
|------|-------|
| `lib/pages/index.page.dart` | `/` |
| `lib/pages/about.page.dart` | `/about` |
| `lib/pages/blog/[id].page.dart` | `/blog/:id` |
| `lib/pages/(auth)/login.page.dart` | `/login` (group folders are stripped) |
| `lib/pages/docs/[...slug].page.dart` | `/docs/*slug` (catch-all) |

> **Route Groups**: A folder wrapped with parentheses (e.g., `(auth)`) is **not** part of the URL.

## Accessing Params & Query
```dart
import 'package:dartvel_flutter/dartvel_flutter.dart';

@override
Widget build(BuildContext context) {
  final id = context.dvParams['id'];       // from /blog/:id
  final q  = context.dvQuery['q'];         // from ?q=...
  ...
}
```

## 404 Handling
- To redirect unknown routes, set `notFoundRedirect` in your `dartvel:` config (e.g., `/`).
- Trailing slash normalization is enabled by default (`/path/` → `/path`); disable via `routingNormalizeTrailingSlash: false`.

## Layouts
- Root: add `lib/pages/_layout.dart` with a class extending `DartvelLayout` (constructor: `{ required Widget child }`).
- Per-segment: add `_layout.dart` inside any folder (including group folders like `(admin)`).
- The router wraps pages with the ancestor chain (root → segment) in that order.

## Guards (per-segment)
- Add `_guard.dart` inside any folder under `lib/pages/**` to run before pages in that folder.
- Export a top-level function:
```dart
// lib/pages/blog/_guard.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

FutureOr<String?> guard(BuildContext context, GoRouterState state) async {
  // return a path to redirect, or null to allow
  return null;
}
```
- Guards run in ancestor order (root → segment). First non-null redirect wins.

# Page API — `DartvelPage` (v0.1)

Pages are **Flutter widgets** extending `DartvelPage`.

```dart
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) =>
      const SeoProps(title: 'Home', description: 'Welcome');

  @override
  PageTransitionSpec get transition =>
      const PageTransitionSpec(type: DvTransition.fade, duration: Duration(milliseconds: 180));

  @override
  Widget build(BuildContext context) {
    final params = context.dvParams;
    final query  = context.dvQuery;
    final lang   = DvI18nScope.of(context).localeTag; // current locale tag from query
    return Scaffold(...);
  }
}
```

## i18n (query-param strategy; cross-platform)
- Configure in `pubspec.yaml -> dartvel.i18n`.
- Router wraps each page into a `DvI18nScope(localeTag: ...)` with the normalized query param value.
- Change language in-app (preserving path & query):
```dart
ElevatedButton(
  onPressed: () => DvI18n.updateLang(context, 'lang', 'fr-FR'),
  child: const Text('Français'),
);
```

## SEO (web-only)
- Implement `buildWebSeo(params, query)` to set title/description/canonical/OG/Twitter tags on web at runtime.
- Project defaults are taken from `pubspec.yaml -> dartvel.webSeoDefaults` and merged with your page’s override.

## Transitions (cross-platform)
- Override `transition` per page.
- Global defaults in `pubspec.yaml -> dartvel.transitions`.
- Available types: `none`, `fade`, `slideLeft`, `slideUp`, `scale`, `sharedAxis`.

## Layouts (root and per-segment)
- Root: create `lib/pages/_layout.dart` exporting a class that extends `DartvelLayout` and takes a required `child`:
```dart
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class Layout extends DartvelLayout {
  const Layout({super.key, required super.child});
  @override
  Widget build(BuildContext context) => Scaffold(body: child);
}
```
- The generator wraps every page with the root layout.
- Per-segment: add `_layout.dart` inside any folder under `lib/pages/**` (including group folders like `(admin)`); pages under that folder are wrapped by that layout in addition to the root.
- Data Loading (per page)
- Override `loadData(params, query)` in your `DartvelPage` to fetch data before rendering. The router wraps your page in a `DvDataLoader` and exposes the result via `DvDataScope`:
```dart
class BlogIdPage extends DartvelPage {
  const BlogIdPage({super.key});

  @override
  Future<Object?> loadData(Map<String, String> params, Map<String, String> query) async {
    final id = params['id'];
    // fetch from your backend, e.g., using Dio
    // return await api.getPost(id);
    return {'id': id, 'title': 'Hello $id'};
  }

  @override
  Widget build(BuildContext context) {
    final data = DvDataScope.of(context).data as Map?;
    return Scaffold(body: Center(child: Text('Post: \\${data?['title']}')));
  }
}
```

# Backend (in-app) — dartvel v0.1

Your backend code lives under **`lib/backend`** (configurable via `backendDir`). Typical layout:
```
lib/backend/
  functions/
    hello.get.dart      # GET /api/hello
    upload.post.dart    # POST /api/upload
  dbCollections/
    users.collection.dart
  authentication.dart
  web_push.dart
  remoteFileStorageConfig.dart
```

**Functions → Routes**
- Place handlers under `lib/backend/functions/**/*.method.dart` where `.method` is one of `get|post|put|patch|delete|head|options`.
- File path maps to URL path, with support for groups and dynamic segments:
  - `lib/backend/functions/hello.get.dart` → `GET /api/hello`
  - `lib/backend/functions/blog/[id].get.dart` → `GET /api/blog/<id>`
  - `lib/backend/functions/docs/[...slug].get.dart` → `GET /api/docs/<slug|.*>`
- Group folders `(admin)/users.get.dart` are stripped from the URL.
 - If a filename has no explicit method (e.g., `hello.dart` or `blog/[id].dart`), the CLI defaults the method to `POST`.

The CLI generates a backend router builder at `.dart_tool/dartvel_backend_routes.g.dart` (returns a `Router`) and a config at `.dart_tool/dartvel_backend.g.dart` (`backendHost`, `backendPort`, `apiBasePath`). Call `buildBackendRouter()` and pass the result to `serve()` (or use `startBackend()` for a ready-to-run helper).

**Typed Functions (v0.1)**
- Define a plain Dart function whose name matches the file base name. The generator adapts request info to your parameters.
- Param sources (in order): path params → query → JSON body.
- Return values: `Response` (as-is), `Stream<String|List<int>>` (streamed), `String` (text), anything else (JSON).

Examples:
```dart
// lib/backend/functions/hello.get.dart
Map<String, dynamic> hello(String name) => {'hello': name};

// lib/backend/functions/blog/[id].get.dart
Future<Map<String, dynamic>> id(String id) async => {'id': id};

// Streaming (SSE-like)
Stream<String> progress() async* {
  for (var i = 0; i < 3; i++) { yield 'step:' + i.toString(); }
}
```

**Handlers** return `Response` (alias `ResponseType`) and can use helpers from `dartvel_core/Res`:

```dart
// lib/backend/functions/hello.get.dart
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(Request req) async {
  return Res.json({'ok': true});
}
```

> The CLI generates **routes** and **configs**. A development server is launched by `dartvel dev`. For custom servers, import the generated `buildBackend()` and call `listen()` on it.

## API base
- The Flutter client builds request URLs using `lib/dartvel_client/dartvel_runtime.dart` (imported as a package) with:
  - **dev:** `devBackendHost`
  - **prod:** `prodBackendHost`
- The path prefix is `apiBasePath` (default `/api`).

## CORS
Use `cors()` middleware from `dartvel_core` if your backend runs on a different origin during development.

---

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

# Web & Cross-Platform Features — dartvel v0.1

**Implemented (v0.1):**
- Cross-platform transitions via `dartvel.transitions` (page override via `DartvelPage.transition`)
- Cross-platform router redirects via `dartvel.routingRedirects`
- Cross-platform i18n via `dartvel.i18n` (query strategy: `?lang=en-US`)
- Web SEO defaults via `dartvel.webSeoDefaults` and per-page `buildWebSeo(...)`

**Planned (reserved keys; not yet in generator):**
- `webHead` (meta/link/script injection at build-time)
- `webPrerender` (SSG/ISR-like JSON alongside Flutter web)
- `webPwa` (manifest & service worker generator)
- `webImage` (image proxy & helpers)
- `webAnalytics` / `webVitals`
- `webRobots` / `webSitemap`
