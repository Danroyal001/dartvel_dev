
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
