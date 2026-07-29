# Changelog

All notable changes to this project will be documented in this file.

Dartvel is pre-1.0. Minor versions may contain breaking changes; breaking
changes are called out explicitly below.

## 0.2.1 — 2026-07-29

Packages at 0.2.1: `dartvel`, `dartvel_core`, `dartvel_flutter`, `dartvel_cli`.

### Fixed

- Generated private `@DVPage` expression bodies now compile when they reference
  generated client APIs and public source support symbols.
- The Dartvel example app no longer routes through public widget helper
  functions for generated page inputs.
- `dartvel --version` reports the active CLI package version instead of a stale
  fallback.
- CLI `db`, `ai`, `deploy`, plugin, and form generation commands now fail
  honestly or produce concrete artifacts instead of placeholder success output.

### Verified

- `packages/dartvel_cli`: `dart analyze .`, focused generator/version tests.
- `packages/dartvel_generator`: `dart analyze .`, `dart test`.
- `examples/dartvel_example`: `flutter analyze`, `flutter test`,
  `flutter build web`.

## 0.2.0 — 2026-07-26

Packages at 0.2.0: `dartvel`, `dartvel_core`, `dartvel_flutter`, `dartvel_cli`.

### Added

- **Lifecycle signals.** `DV.lifecycle.app` / `.build` and
  `context.lifecycle.page` / `.request` / `.transaction`, as read-only enum
  signals. The framework owns transitions; application code observes them. A
  failing observer cannot break a transition for others.
- **Modules.** `DV.Modules.<id>` registry with per-module lifecycle, immutable
  parent-supplied config, and `resolve()` so module code never hard-codes its
  mount point.
- **Reversible transactions.** `DV.transaction(...)` with
  `context.afterCommit(...)` for irreversible effects and
  `context.compensate(...)` for external effects Dartvel cannot reverse.
  Compensations run in reverse registration order; a failing compensation does
  not stop the rest, and `DVCompensationException` carries the original cause
  alongside rollback failures. Nested calls join the active transaction unless
  `isolated: true`.
- **`@DVStaticPaths()`** is now discovered during generation and emitted to
  `dartvel_client/static_paths.g.dart`, so parameterized routes can be
  statically generated.
- **Toolchain preflight for `dartvel build`.** Checks host support, then
  required tooling, before doing any generation work. Prompts interactively,
  installs unattended under CI so a pipeline cannot hang, and honours
  `--auto-install` / `--no-auto-install`. Tools installed mid-run are added to
  the `PATH` handed to child processes.
- **Embedded and television build targets:** `tizen` (alias `tpk`),
  `sony-elinux` (plus `-iso` / `-img`), and `webos`, each driven by the
  vendor's Flutter embedder through a Dartvel-maintained fork.
- **`@DVModel.sensitiveField()`** redaction: excluded from `toPublicJson()`,
  generated cards, search, logs and AI context, while `toJson()` stays complete
  for persistence.
- `DV.baseUrl` / `DV.api(...)` for application code.
- `DV.currentTenant` is now dynamic, with context scoping and `withTenant`.
- GitHub Actions matrix for the Windows/macOS/iOS/tvOS targets that cannot be
  built on a Linux development machine.

### Changed

- **Breaking:** model-scoped annotations now live under `DVModel`:
  `@DVSensitiveModelField()` → `@DVModel.sensitiveField()` and
  `@DVSearchable()` → `@DVModel.searchableField()`. The old names remain as
  `@Deprecated` aliases and both spellings still generate.
- **Breaking:** `DVBox.wrapLine` is the canonical wrap layout; `DVBox.wrap`
  remains a compatibility alias.
- `go_router` is named as the generated router's engine.
- The licence is now unambiguously proprietary. The previous file declared the
  work private above a fully commented-out MIT grant.

### Fixed

- `dartvel build <platform>` honours the positional argument. It was read only
  from `-p/--platform` (default `all`), so every documented positional form was
  silently ignored and built every platform.
- Desktop targets are no longer claimed to cross-compile. `dartvel build
  windows` reported itself available on Linux and hard-failed instead of
  skipping; Flutter has no desktop cross-compilation.
- Tizen TPKs contain the Flutter payload. Native builds produced a ~15KB
  package holding only the compiled runner — installable, but inert — because
  `tizen package -e` reports success without injecting the payload on Tizen SDK
  CLI 10.x. Fixed in the fork; verified 15KB → 9.3MB.

### Known gaps

- `Model.Page` data-mode rendering (`.async` / `.signal` / `.fromId`) and
  `@DVModel(generatePublicPages: true)` are **not** implemented. The
  `DVModelPageDataMode` enum and both annotation parameters are accepted and
  surfaced as generated metadata, but no generator acts on them.
- `sony-elinux` cannot build a Dartvel app: the embedder's newest Flutter ships
  Dart 3.7.2, below the ≥3.9 floor required by `dartvel_shelf`'s native-asset
  build hook.
- `webos` builds are not yet demonstrated.
- `windows`, `macos`, `ios` and `tvos` are unverified pending a CI run.

See [docs/build-targets.md](docs/build-targets.md) for per-target evidence and
the *Alpha status* section of [README.md](README.md) for what is implemented.

## v0.1 — 2025-08-28

Initial pre-release of dartvel.

Packages at 0.1.0:
- dartvel_core
- dartvel_flutter
- dartvel_cli
- dartvel_shelf
