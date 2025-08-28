# Changelog

All notable changes to this project will be documented in this file.

## v0.1 — 2025-08-28

Initial pre-release of dartvel.

- CLI generator
  - Fixed i18n locales emission in generated router (proper Dart list literal)
  - Corrected router file write path and added missing semicolon
  - Escaped string interpolation in client runtime template
  - Replaced Pythonic string APIs with Dart equivalents (e.g., `replaceAll`)
  - Switched page discovery to `glob` + `package:file` for reliable listing
  - Spread operator fix in import list (`...pageImports`)
- Router features
  - GoRouter-based generation from `lib/pages/**/*.page.dart`
  - Global redirects via `dartvel.routingRedirects` (pattern `:id` supported)
  - Query-based i18n scope injection (`DvI18nScope`) with normalization
  - Web SEO defaults + per-page SEO via `buildWebSeo(...)`
  - Cross-platform page transitions (global defaults + per-page override)
- Docs & example
  - Updated all docs and example to v0.1
  - CLI invocation standardized: `dart run dartvel_cli:dartvel <cmd>`
  - Example README updated; generation verified
- Housekeeping
  - Consolidated duplicate `.gitignore` files

Packages at 0.1.0:
- dartvel_core
- dartvel_flutter
- dartvel_cli

Generated artifacts:
- `.dart_tool/dartvel_client/dartvel_config.g.dart`
- `.dart_tool/dartvel_client/dartvel_runtime.dart`
- `.dart_tool/dartvel_client/router.g.dart`
- `.dart_tool/dartvel_backend.g.dart`
