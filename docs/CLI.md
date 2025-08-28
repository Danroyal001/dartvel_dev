
# CLI — dartvel_cli (v0.1)

Commands:
- `dart run dartvel_cli:dartvel routes` — Generate router and config files.
- `dart run dartvel_cli:dartvel dev` — Same as `routes`, prints hints for running dev servers.
- `dart run dartvel_cli:dartvel build` — Generate artifacts and **require** `prodBackendHost`.
 - `dart run dartvel_cli:dartvel doctor` — Check config, pages, deps, and common pitfalls.

Wrappers (shorthand):
- `dart run dartvel_cli:routes`
- `dart run dartvel_cli:dev`
- `dart run dartvel_cli:build`
 - `dart run dartvel_cli:doctor`

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
