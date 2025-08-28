
# Backend (in-app) — dartvel v2.1

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

**Handlers** return `Response` (type alias `ResponseType`) and can use helpers from `dartvel_core/Res`:

```dart
// lib/backend/functions/hello.get.dart
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(Request req) async {
  return Res.json({'ok': true});
}
```

> The CLI currently generates **config files** only. You are free to wire the HTTP server as you prefer, or use a small Shelf entry that imports your routes and binds to `backendHost/backendPort` (from `.dart_tool/dartvel_backend.g.dart`).

## API base
- The Flutter client builds request URLs using `.dart_tool/dartvel_client/dartvel_runtime.dart` with:
  - **dev:** `devBackendHost`
  - **prod:** `prodBackendHost`
- The path prefix is `apiBasePath` (default `/api`).

## CORS
Use `cors()` middleware from `dartvel_core` if your backend runs on a different origin during development.
