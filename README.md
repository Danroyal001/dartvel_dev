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

  If you prefer to commit client files, remove that line from your `.gitignore`.

---

# Dartvel Project Structure Guide

This document captures the current expectations for a Dartvel application layout.

## Top-Level Layout

```
<project_root>
├── lib/
│   ├── pages/                 # File-based routing surface for Flutter UI pages
│   │   ├── index.page.dart
│   │   ├── _layout.dart
│   │   └── ...
│   ├── backend/               # Backend runtime implemented as functions
│   │   └── functions/
│   │       ├── hello.get.dart
│   │       └── ...
│   ├── dartvel_client/        # Generated client runtime (router, env, dio helpers)
│   └── dartvel_config.dart    # (Optional) manual overrides
├── .dart_tool/
│   └── dartvel_backend*.g.dart  # Generated backend router/config files
├── docs/                      # Developer documentation
├── pubspec.yaml               # Flutter application manifest + dartvel section
├── analysis_options.yaml      # Linting configuration
└── README.md
```

## `pubspec.yaml` Requirements

Every Dartvel app declares a `dartvel` section. At minimum:

```yaml
name: awesome_app
flutter:
  uses-material-design: true

dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  apiBasePath: /api
  pagesDir: lib/pages
  backendDir: lib/backend
```

Additional keys (`envFiles`, `routingRedirects`, i18n, transitions) enable optional
features such as localisation and page transitions.

## Generated Assets

Running `dartvel routes`, `dartvel dev`, or `dartvel build` generates:

- `lib/dartvel_client/*`: Flutter router/configuration helpers.
- `.dart_tool/dartvel_backend*.g.dart`: backend router + config.
- `.dart_tool/dartvel_dev_server.dart`: entrypoint used by `dartvel dev`.

These files should be **ignored** from source control unless the project wants to
commit client artefacts (the CLI inserts ignore rules automatically).

## Backend Functions

Backends live under `lib/backend/functions`. File names map to HTTP routes:

- `hello.get.dart` → `GET /api/hello`
- `[id].get.dart` → `GET /api/<id>` with dynamic param.
- `group/[...slug].post.dart` → `POST /api/group/<slug>` catch-all.

Functions can export either:

- A top-level function whose name matches the file stem (sanitised).
- A `handler(...)` function returning a Dartvel `Response`.

The CLI inspects parameter names to wire request params/body/query automatically.

## Pages and Layouts

The file-based router mimics frameworks like Next.js:

- `lib/pages/index.page.dart` → `/`.
- Nested directories map to nested routes.
- `_layout.dart` files wrap descendant pages.
- Optional `.loading.dart` / `.error.dart` provide skeletons.

Guards can be defined with `_guard.dart` next to page directories.
\n\n# Guides & Reference\n

# Bootstrapping a dartvel Project (v0.1)

> This guide assumes a *standard Flutter* project.

## 1) Add dependencies (local path or pub)
```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  go_router: ^14.2.0
  dartvel_core:        # Core helpers and types for backend handlers (dartvel_shelf-based)
    path: ../dartvel/packages/dartvel_core
  dartvel_flutter:     # Page API, SEO & transitions
    path: ../dartvel/packages/dartvel_flutter

dev_dependencies:
  dartvel_cli:         # Codegen CLI
    path: ../dartvel/packages/dartvel_cli
```

## 2) Configure dartvel
Add a `dartvel:` section to your `pubspec.yaml` (see **CONFIG** for all keys):
```yaml
dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  prodBackendHost: https://api.example.com

  pagesDir: lib/pages
  backendDir: lib/backend
  apiBasePath: /api

  webSeoDefaults:
    siteName: MyApp
    defaultTitle: MyApp
    defaultDescription: A beautiful app built with dartvel.
    defaultImage: assets/og_default.png
    twitterHandle: "@myapp"

  transitions:
    default: fade
    durationMs: 220
    curve: easeInOut

  # Optional: env files. PUBLIC_* keys are exposed to Flutter via env.g.dart
  envFiles: [ .env, .env.local ]
```

## 3) Create your first page
`lib/pages/index.page.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) =>
      const SeoProps(title: 'Home • MyApp', description: 'Welcome to MyApp!');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).pushNamed('/blog/42'),
          child: const Text('Go to /blog/42'),
        ),
      ),
    );
  }
}
```

## 4) Generate router & config (+backend routes)
```bash
dartvel routes
```

This emits:
- `lib/dartvel_client/dartvel_config.g.dart`
- `lib/dartvel_client/dartvel_runtime.dart`
- `lib/dartvel_client/router.g.dart`
- `lib/dartvel_client/functions.g.dart`
- `lib/dartvel_client/env.g.dart`
- `.dart_tool/dartvel_backend.g.dart`
 - `.dart_tool/dartvel_backend_routes.g.dart`

Optional sanity check:
```bash
dartvel doctor
```
Shows pages found, backend functions count, and config tips.

404 behavior (optional):
- Set `notFoundRedirect: /` under `dartvel:` to redirect unknown routes to a path of your choice.

Loading/Error states (optional):
- Add sibling files next to a page to customize data loader UI:
  - `lib/pages/index.loading.dart` → `IndexPageLoading`
  - `lib/pages/index.error.dart` → `IndexPageError`
- If you don’t add them, defaults are provided: `DvDefaultLoading` and `DvDefaultError`.

## 5) Wire up your app
`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:your_app/dartvel_client/router.g.dart';
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: createDartvelRouter(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}
```

## 6) Run (web recommended for SEO features)
```bash
flutter run -d chrome
```

> Tip: For Android emulator, set `devBackendHost: http://10.0.2.2:3000`.

Optional: start a custom server by importing the generated backend app:
```dart
import '.dart_tool/dartvel_backend_routes.g.dart' as gen;
Future<void> main() async {
  final app = gen.buildBackend();
  await app.listen(address: '0.0.0.0', port: 3000);
}
```

## Backend function quickstart
Create a handler under `lib/backend/functions/**/*.method.dart` (method in: get, post, put, patch, delete, head, options):
```dart
// lib/backend/functions/hello.get.dart
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
  return Res.json({'ok': true, 'hello': 'world'});
}
```
Run `dartvel routes` again to regenerate backend routes.

## Public env values in Flutter
1) Add an env file like `.env`:
```
PUBLIC_GREETING=Hello
SECRET_TOKEN=do_not_export
```
2) Configure `envFiles` under `dartvel:` (or rely on defaults).
3) Run `dartvel routes`.
4) Use from Flutter:
```dart
import 'package:your_app/dartvel_client/env.g.dart';
final greeting = DartvelEnv.get('PUBLIC_GREETING');
```

Only `PUBLIC_*` keys are exported to `env.g.dart`.

## Production build
Set `prodBackendHost` in `pubspec.yaml -> dartvel` and build:
```bash
flutter build web
```
You can override the backend URL at build time:
```bash
flutter build web \
  --dart-define=DARTVEL_BACKEND_URL=https://staging.example.com
```

Preview a built web folder locally (SPA fallback included):
```bash
dartvel preview --dir build/web --port 5000
```

# CLI — dartvel_cli (v0.1)

Commands:
Commands:
- `dartvel create [name]` — Create a new project (interactive). Aliases: `init`, `new`.
- `dartvel routes` — Generate client router, client helpers, backend routes.
- `dartvel dev` — Watch, auto‑generate, start backend + `flutter run` (with stdin pass‑through).
- `dartvel run` — Alias for `dev` (accepts Flutter‑like flags).
- `dartvel build` — Generate artifacts and require `prodBackendHost`.
- `dartvel doctor` — Check system deps (Dart, Flutter, Git, Shorebird) and project config.
- `dartvel watch` — Watch pages/backend/config and regenerate on change.
- `dartvel preview` — Serve a built web directory with SPA fallback (default `build/web`).

`dev`/`run` flags (subset): `-d/--device`, `--release`, `--profile`, `--debug`, `--dart-define`, `--dart-define-from-file`, `--web-renderer`, `-v/--verbose`.

Generated files:
- Client (Flutter): `lib/dartvel_client/`
  - `dartvel_config.g.dart`
  - `dartvel_runtime.dart`
  - `router.g.dart` (global redirects + i18n scope; wires .loading/.error pages)
  - `functions.g.dart` (typed/untyped API callers)
  - `env.g.dart` (PUBLIC_* values from env files)
- Backend (dartvel_shelf): `.dart_tool/`
  - `dartvel_backend.g.dart`
  - `dartvel_backend_routes.g.dart` (builds a `Router` for `lib/backend/functions/**/*.method.dart` and exposes `startBackend()` helpers)

Prerequisites for backend (native core)
- Build the Rust core once before `dartvel dev/run` so the native library is available:
  - `cd packages/dartvel_shelf && scripts/build_release.sh` (or `cargo build --release && cbindgen --config cbindgen.toml -o include/dartvel_shelf.h`)
  - Optionally export `DARTVEL_SHELF_LIB` to point to the built library (e.g., `export DARTVEL_SHELF_LIB=/abs/path/to/libdartvel_shelf.so`).
  - In monorepo dev, the CLI will attempt common relative paths automatically.

Reads from config:
- `transitions` (global default page transitions)
- `routingRedirects` (cross-platform router redirects)
- `i18n` (query-param strategy)
- `webSeoDefaults` (web-only meta defaults)
 - `envFiles` (list of env file paths to read, defaults: [`.env`, `.env.local`])

Loading/Error UI conventions:
- For a page `lib/pages/foo/bar.page.dart` with class `BarPage`, you can add:
  - `lib/pages/foo/bar.loading.dart` defining `BarPageLoading`
  - `lib/pages/foo/bar.error.dart` defining `BarPageError`
- The generator will import and pass them to `DvDataLoader(loading:, error:)`.
- If missing, framework defaults are used: `DvDefaultLoading`, `DvDefaultError`.

Doctor checks:
Doctor checks:
- **System Dependencies**: Checks Dart SDK, Flutter SDK, Git, Shorebird (optional), Codemagic (optional).
- **Project Checks** (if run in project root):
  - Verifies essential deps, counts pages and backend functions.
  - Reports route conflicts when multiple files map to the same route.
  - Validates env files (configured via `envFiles`) and reports PUBLIC_* keys discovered.
- **Flutter Doctor**: Runs `flutter doctor -v` for comprehensive diagnostics.

Preview server:
- `dartvel preview [--dir build/web] [--host 127.0.0.1] [--port 4321]`
- Serves static files with SPA fallback to `index.html` for unknown GET routes.

# dartvel Config Reference (v0.1)

All configuration lives under the **`dartvel:`** key in your app's `pubspec.yaml`.

| Key | Type | Default | Required | Description | Status |
|-----|------|---------|----------|-------------|--------|
| `backendHost` | string | `0.0.0.0` | no | Bind address for the dartvel_shelf backend (your server process). | ✅ Implemented |
| `backendPort` | int | `3000` | no | Bind port for the backend. | ✅ Implemented |
| `devBackendHost` | string | `http://localhost:{backendPort}` | no | Base URL the Flutter app calls during **development**. | ✅ Implemented |
| `prodBackendHost` | string | — | **yes** (for `build`) | Base URL the Flutter app uses in **release** builds. | ✅ Implemented |
| `pagesDir` | string | `lib/pages` | no | Directory for your page files `*.page.dart`. | ✅ Implemented |
| `backendDir` | string | `lib/backend` | no | Directory for backend code (e.g., `functions/`). | ✅ Implemented |
| `apiBasePath` | string | `/api` | no | API base path prefix for backend endpoints. | ✅ Implemented |
| `transitions.default` | enum | `fade` | no | Global default transition: `none`\|`fade`\|`slideLeft`\|`slideUp`\|`scale`\|`sharedAxis`. | ✅ Implemented |
| `transitions.durationMs` | int | `220` | no | Default transition duration in ms. | ✅ Implemented |
| `transitions.curve` | enum | `easeInOut` | no | Default curve: `linear`\|`easeIn`\|`easeOut`\|`easeInOut`\|`decelerate`. | ✅ Implemented |
| `routingRedirects` | list | `[]` | no | Cross-platform in-app redirects (pattern `:id` supported). | ✅ Implemented |
| `routingNormalizeTrailingSlash` | bool | `true` | no | Redirect `/path/` → `/path` (keeps query). Root `/` unaffected. | ✅ Implemented |
| `notFoundRedirect` | string | `''` | no | If set, unknown routes redirect to this path (e.g., `/`). | ✅ Implemented |
| `i18n.strategy` | string | `query` | no | Strategy. Currently only `query` is supported. | ✅ Implemented |
| `i18n.param` | string | `lang` | no | Query parameter name used for locale (e.g., `?lang=en-US`). | ✅ Implemented |
| `i18n.defaultLocale` | string | `''` | no | Default locale tag when the query is absent/invalid. | ✅ Implemented |
| `i18n.locales` | list | `[]` | no | Allowed locale tags (case-insensitive). Empty list = accept any. | ✅ Implemented |
| `webSeoDefaults.siteName` | string | `''` | no | Default OpenGraph site name (web only). | ✅ Implemented |
| `webSeoDefaults.defaultTitle` | string | `''` | no | Default `<title>` for pages without overrides (web). | ✅ Implemented |
| `webSeoDefaults.defaultDescription` | string | `''` | no | Default meta description (web). | ✅ Implemented |
| `webSeoDefaults.defaultImage` | string | `''` | no | Default OG/Twitter image URL (web). | ✅ Implemented |
| `webSeoDefaults.twitterHandle` | string | `''` | no | Default Twitter handle (e.g., `@myapp`) (web). | ✅ Implemented |

## Deprecated Keys
| Old | New |
|-----|-----|
| `webTransitions` | `transitions` |
| `webRedirects` | `routingRedirects` |
| `webI18n` | `i18n` |
| `seoDefaults` | `webSeoDefaults` |
| `DartvelPage.buildSeo()` | `DartvelPage.buildWebSeo()` |

# FAQ — dartvel v0.1

**Q: Does dartvel render HTML on the server (SSR)?**  
A: No. Pages are standard Flutter widgets. SEO is applied by injecting head/meta tags on web at runtime. Future versions may add SSG-like data prerender.

**Q: Can I use any state management?**  
A: Yes. dartvel is UI-agnostic beyond requiring pages to extend `DartvelPage`.

**Q: Where do I put static assets?**  
A: Use Flutter's normal `flutter.assets` section in `pubspec.yaml`.

**Q: How do I add custom meta tags?**  
A: Return them via `SeoProps(extraMeta: {'my:tag': 'value'})` in `buildWebSeo`.

**Q: How do I change transitions per route?**  
A: Override `transition` in your page; or set defaults via `webTransitions`.

**Q: Can I show custom loading/error UIs while data loads?**  
A: Yes. Add sibling files next to your page file:
`my.page.dart` → `my.loading.dart` with `MyPageLoading`, `my.error.dart` with `MyPageError`. If omitted, `DvDefaultLoading` and `DvDefaultError` are used.

**Q: How do I use env values in Flutter?**  
A: Put them in `.env` (or `.env.local`) and list those in `dartvel.envFiles`. Only `PUBLIC_*` keys are exported to `lib/dartvel_client/env.g.dart` and can be read with `DartvelEnv.get('PUBLIC_KEY')`.

**Q: How do I preview my built web app locally?**  
A: `dartvel preview --dir build/web` serves files with SPA fallback to `index.html`.
# Platform Support Guide

Dartvel supports a wide range of platforms, enabling you to build truly universal applications.

## Supported Platforms

| Platform | Support Level | Build Command |
| :--- | :--- | :--- |
| **Android** | ✅ Stable | `flutter build apk` |
| **iOS** | ✅ Stable | `flutter build ios` |
| **Windows** | ✅ Stable | `flutter build windows` |
| **macOS** | ✅ Stable | `flutter build macos` |
| **Linux** | ✅ Stable | `flutter build linux` |
| **Web** | ✅ Stable | `flutter build web` |
| **Android TV** | ⚠️ Beta | `flutter build apk --target-platform android-arm64` |
| **Apple TV** | ⚠️ Beta | `flutter build ios --config-only` |
| **Tizen OS** | ⚠️ Beta | `flutter-tizen build tpk` |
| **webOS** | ⚠️ Beta | Custom tooling required |
| **Embedded Linux** | ⚠️ Beta | `flutter build linux --target-platform linux-arm64` |

## Platform-Specific Configuration

### Android

Update `android/app/build.gradle` to set the correct SDK versions.

### iOS

Ensure you have a valid Apple Developer account and configured signing in Xcode.

### Desktop (Windows, macOS, Linux)

Desktop support requires the relevant build tools (Visual Studio, Xcode, CMake/Ninja).

### Smart TVs (Tizen, webOS)

Requires specific SDKs (Tizen Studio, webOS CLI) to be installed and configured.

# Troubleshooting — dartvel v0.1

## Router not updating
- Re-run `dartvel routes` after adding/renaming pages or changing config.
 - Check for route conflicts with `dartvel doctor` (will list files mapping to the same route).

## 404 / wrong route
- Ensure file name ends with `.page.dart` and class ends with `Page` and **extends `DartvelPage`**.
- Check dynamic segments: `[id]` becomes `:id`, `[...slug]` becomes `*slug`.

## API calls fail in dev
- Use the right dev host: Android emulator needs `http://10.0.2.2:<port>`, iOS Simulator can use `http://localhost:<port>`.
- Confirm your backend is running and listening on `backendHost:backendPort`.
 - You can set `DARTVEL_BACKEND_URL` at build time to force a specific base URL.

## CORS errors
- Add `cors()` middleware; dartvel_shelf will map this hint to native CORS when supported.

## Production build points to wrong API
- Set `prodBackendHost` and rebuild. You can override at build time:
```bash
flutter build web --dart-define=DARTVEL_BACKEND_URL=https://staging.example.com
```
 
## Env values not available in Flutter
- Ensure your `.env` is listed under `dartvel.envFiles` (defaults: `.env`, `.env.local`).
- Only keys prefixed with `PUBLIC_` are exported to `lib/dartvel_client/env.g.dart`.
