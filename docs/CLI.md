
# CLI — dartvel_cli (v0.1)

Commands:
- `dart run dartvel_cli:dartvel routes` — Generate router and config files.
- `dart run dartvel_cli:dartvel dev` — Watch, auto‑generate, start backend + `flutter run` (with stdin pass‑through).
- `dart run dartvel_cli:dartvel run` — Alias for `dev` (accepts Flutter‑like flags).
- `dart run dartvel_cli:dartvel build` — Generate artifacts and **require** `prodBackendHost`.
- `dart run dartvel_cli:dartvel doctor` — Check config, pages, deps, and common pitfalls.
- `dart run dartvel_cli:dartvel watch` — Watch pages/backend/config and regenerate on change.

Wrappers (shorthand):
- `dart run dartvel_cli:routes`
- `dart run dartvel_cli:dev`
- `dart run dartvel_cli:run`
- `dart run dartvel_cli:build`
 - `dart run dartvel_cli:watch`
 - `dart run dartvel_cli:doctor`

`dev`/`run` flags (subset): `-d/--device`, `--release`, `--profile`, `--debug`, `--dart-define`, `--dart-define-from-file`, `--web-renderer`, `-v/--verbose`.

Generated files:
- `.dart_tool/dartvel_client/dartvel_config.g.dart`
- `.dart_tool/dartvel_client/dartvel_runtime.dart`
- `.dart_tool/dartvel_client/router.g.dart` (includes global redirects + i18n scope)
- `.dart_tool/dartvel_backend.g.dart`
- `.dart_tool/dartvel_backend_routes.g.dart` (Shelf Router for `lib/backend/functions/**/*.method.dart`)

Reads from config:
- `transitions` (global default page transitions)
- `routingRedirects` (cross-platform router redirects)
- `i18n` (query-param strategy)
- `webSeoDefaults` (web-only meta defaults)
