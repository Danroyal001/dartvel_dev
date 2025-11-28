# dartvel (v0.1)

A framework for simplifying the creation and deployment of fullstack flutter and dart apps

- 📚 **Docs:** see [`/docs/`](./docs)
- 🧪 **Example app:** [`/example/dartvel_example`](./example/dartvel_example)
- 🧩 Packages:
  - `packages/dartvel_core`
  - `packages/dartvel_flutter`
  - `packages/dartvel_cli`

## CLI Commands

Dartvel comes with a powerful CLI to manage your project.

### Core Commands
- `dartvel create [name]`: Create a new Dartvel project (interactive).
- `dartvel dev`: Start the development server and Flutter app (with hot reload).
- `dartvel build`: Build the project for production (includes SSG).
- `dartvel preview`: Serve the production build locally.
- `dartvel doctor`: Check system environment and project health.

### Generators
- `dartvel routes`: Generate routes, client API, and environment variables.
- `dartvel watch`: Watch for file changes and regenerate routes automatically.

### Plugins & Updates
- `dartvel plugin add <name>`: Add a plugin (e.g., `auth`).
- `dartvel updates push`: Push an OTA update via Shorebird.

## Getting Started
## Getting Started
1) Create a new project: `dartvel create` (or `dartvel create my_app`)
2) Enter dev mode: `cd my_app && dartvel dev`
3) Open `lib/pages/index.page.dart` and start editing!

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
- Generate routes/configs:
  - `dartvel routes`
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

