
# CLI — dartvel_cli (v2.2)

Commands:
- `dart run dartvel_cli:dartvel routes` — Generate router and config files.
- `dart run dartvel_cli:dartvel dev` — Same as `routes`, prints hints for running dev servers.
- `dart run dartvel_cli:dartvel build` — Generate artifacts and **require** `prodBackendHost`.

Generated files:
- `.dart_tool/dartvel_client/dartvel_config.g.dart`
- `.dart_tool/dartvel_client/dartvel_runtime.dart`
- `.dart_tool/dartvel_client/router.g.dart` (includes global redirects + i18n scope)
- `.dart_tool/dartvel_backend.g.dart`

Reads from config:
- `transitions` (global default page transitions)
- `routingRedirects` (cross-platform router redirects)
- `i18n` (query-param strategy)
- `webSeoDefaults` (web-only meta defaults)
