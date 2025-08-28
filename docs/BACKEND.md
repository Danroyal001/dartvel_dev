
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

The CLI generates a router at `.dart_tool/dartvel_backend_routes.g.dart` and a config at `.dart_tool/dartvel_backend.g.dart` (`backendHost`, `backendPort`, `apiBasePath`).

**Handlers** return `Response` (alias `ResponseType`) and can use helpers from `dartvel_core/Res`:

```dart
// lib/backend/functions/hello.get.dart
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(Request req) async {
  return Res.json({'ok': true});
}
```

> The CLI currently generates **config files and a routes file**. You are free to wire the HTTP server as you prefer, or use a small Shelf entry that imports your routes and binds to `backendHost/backendPort` (from `.dart_tool/dartvel_backend.g.dart`).
> Example server: see `example/dartvel_example/bin/server.dart`.

## API base
- The Flutter client builds request URLs using `.dart_tool/dartvel_client/dartvel_runtime.dart` with:
  - **dev:** `devBackendHost`
  - **prod:** `prodBackendHost`
- The path prefix is `apiBasePath` (default `/api`).

## CORS
Use `cors()` middleware from `dartvel_core` if your backend runs on a different origin during development.
