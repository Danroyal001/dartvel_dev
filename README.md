# dartvel (v0.1)

A framework for simplifying the creation and deployment of fullstack flutter and dart apps

- 📚 **Docs:** see [`/docs/`](./docs)
- 🧪 **Example app:** [`/example/dartvel_example`](./example/dartvel_example)
- 🧩 Packages:
  - `packages/dartvel_core`
  - `packages/dartvel_flutter`
  - `packages/dartvel_cli`

## TL;DR
1) Add `dartvel:` to your app's `pubspec.yaml`.
2) Create pages in `lib/pages/**/*.page.dart` (extend `DartvelPage`).
3) Generate router/configs either with dartvel or build_runner:
   - Option A (CLI): `dart run dartvel_cli:routes`
   - Option B (build_runner): add `dev_dependencies: { build_runner: ^2, dartvel_cli: ^0.1 }` and run `dart run build_runner build`
   - Also generates backend routes from `lib/backend/functions/**/*.method.dart`.
4) Use `MaterialApp.router(routerConfig: createDartvelRouter())`.

### Dev mode (auto-start backend + Flutter)
- `dart run dartvel_cli:dev` (or `dart run dartvel_cli:run`)
  - Starts file watching/regeneration
  - Runs the dev backend server from generated routes
  - Launches Flutter (pass `-d <device>` or omit to select interactively)

### Sample `dartvel:` config
```yaml
dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  prodBackendHost: https://api.example.com

  pagesDir: lib/pages
  backendDir: lib/backend
  apiBasePath: /api

  transitions:
    default: fade
    durationMs: 220
    curve: easeInOut

  # Optional: env files. PUBLIC_* keys are exposed to Flutter via env.g.dart
  envFiles: [ .env, .env.local ]

  routingRedirects:
    - { from: "/old", to: "/" }

  routingNormalizeTrailingSlash: true  # '/path/' -> '/path'
  notFoundRedirect: /                 # unknown routes -> '/'

  i18n:
    strategy: query
    param: lang
    defaultLocale: en-US
    locales: [en-US, fr-FR]

  webSeoDefaults:
    siteName: MyApp
    defaultTitle: MyApp
    defaultDescription: A beautiful app built with dartvel.
    defaultImage: assets/og_default.png
    twitterHandle: "@myapp"
```

### Loading/Error UI
- For any `*.page.dart` with class `XxxPage`, you may add:
  - `*.loading.dart` with `XxxPageLoading`
  - `*.error.dart` with `XxxPageError`
- If missing, framework defaults are used: `DvDefaultLoading`, `DvDefaultError`.

### PUBLIC_* env in Flutter
- Env files configured via `dartvel.envFiles` are read and only `PUBLIC_*` keys are exported to `lib/dartvel_client/env.g.dart`.
- Use them in Flutter:
  ```dart
  import 'package:your_app/dartvel_client/env.g.dart';
  final base = DartvelEnv.get('PUBLIC_API_BASE');
  ```

## Backend Quickstart
- Write handlers under `lib/backend/functions/**/*.method.dart` (method in: get, post, put, patch, delete, head, options).
  - If the filename has no explicit method suffix (e.g., `foo/bar/[id].dart`), dartvel defaults to `POST`.

### Example backend features (in example app)
- Streaming (SSE): `GET /api/stream/ticks` emits 10 ticks (1s apart)
- Polling: `GET /api/poll/now` returns `{ now, changed }` vs `?last=...`
- In-memory collections: CRUD for `/api/db/todos` (GET/POST/PUT/DELETE)
- Remote file storage (local demo):
  - `POST /api/storage/upload?name=foo.bin` with raw body
  - `GET /api/storage/file/foo.bin` returns file bytes

See `example/dartvel_example/lib/backend/functions/` for implementations.
- Example: `lib/backend/functions/hello.get.dart`
  ```dart
  import 'package:dartvel_core/dartvel.dart';
  Future<ResponseType> handler(RequestType req) async => Res.json({'ok': true});
  ```
- Generate routes/configs:
  - `dart run dartvel_cli:routes`
- Development backend is launched by the CLI (`dartvel dev`). For custom servers, import the generated `.dart_tool/dartvel_backend_routes.g.dart`, call `buildBackendRouter()`, and pass the result to `serve()` from `dartvel_shelf` (or call `startBackend()` for a ready-to-serve helper).

## Generated files and Git ignore
- Client (Flutter) generated files live under `lib/dartvel_client/` and are safe to commit or ignore.
  - `router.g.dart`, `functions.g.dart`, `dartvel_config.g.dart`, `dartvel_runtime.dart`
  - `env.g.dart`
- Backend (dartvel_shelf) generated files live under `.dart_tool/` and are ephemeral.
  - `.dart_tool/dartvel_backend.g.dart`, `.dart_tool/dartvel_backend_routes.g.dart`
- Running `dartvel` will ensure `.gitignore` contains entries for these (idempotent):
  - `/lib/dartvel_client/`
  - `/.dart_tool/dartvel_backend.g.dart`
  - `/.dart_tool/dartvel_backend_routes.g.dart`
  If you prefer to commit client files, remove that line from your `.gitignore`.

