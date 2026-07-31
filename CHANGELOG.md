# Changelog

All notable changes to this project will be documented in this file.

Dartvel is pre-1.0. Minor versions may contain breaking changes; breaking
changes are called out explicitly below.

## Unreleased

Provider and adapter implementations for subsystems that previously had an API
surface but no way to reach a real service.

### Added

- **AI providers.** `DV.AI` had only the deterministic `LocalDVAIAdapter`.
  HTTP adapters now exist for Claude (`AnthropicDVAIAdapter`), OpenAI,
  OpenRouter, Gemini and Ollama, covering chat, embeddings, structured output
  and transcription. A capability a provider does not serve throws
  `UnsupportedError` naming it, and a rejected request throws
  `DVAIProviderException` carrying the status and body — neither degrades to an
  empty result.
- **Agents and tool calling.** `runAgent` drives the provider's own tool loop
  (Anthropic `tool_use`, OpenAI `tool_calls`) so the model chooses tools, rather
  than firing every requested tool up front. Tools carry a description and JSON
  Schema via `DV.AI.registerTool(..., description:, parameters:)`. A throwing
  tool is reported back to the model as an error result instead of failing the
  run; a loop that never settles throws after `maxAgentIterations`.
- **SQLite database.** `SqliteDVDatabaseAdapter.memory()` and `.file()` execute
  arbitrary SQL, with WAL and foreign keys on by default for file databases.
  `MemoryDVDatabaseAdapter` understood only four statement shapes.
- **Pluggable cache and durable queues.** `DV.Cache` and `DV.Queues` now run on
  adapters, with `DVDatabaseCacheAdapter` and `DVDatabaseQueueAdapter` able to
  share one SQLite file with the application. Durable jobs need a
  `DVJobPayloadCodec`; dispatching or draining a payload with no registered
  codec throws rather than dropping work.
- **Search backends.** `DVSqliteSearchProvider` (FTS5, word matching and BM25
  ranking), plus `MeilisearchProvider`, `AlgoliaSearchProvider` and
  `OpenSearchProvider`. Paging models differ per service and are translated, so
  callers always see the page they asked for.
- **Mail providers.** `SmtpMailProvider` speaks SMTP over a socket, with
  STARTTLS, `AUTH PLAIN`/`LOGIN` and dot-stuffing. HTTP providers cover Resend,
  SendGrid, Postmark, Mailgun and SES, the last signed with the new
  `DVAwsSigV4`.
- **Push and SMS.** `FirebasePushProvider` (FCM HTTP v1), which flags a stale
  device token as `isUnregisteredToken` so callers prune rather than retry, and
  `TwilioSmsProvider` for the `sms` channel.
- **File storage.** `DV.FileStorage` runs on an adapter, with
  `S3FileStorageAdapter` for S3, Cloudflare R2 and MinIO.
- **Authentication.** `DVPasswordHasher` (PBKDF2-HMAC-SHA256, per-password
  salt, constant-time compare) plus `DVOAuth2Client`, an authorization-code
  client with PKCE and constant-time state validation, with presets for Google,
  GitHub, GitLab, Bitbucket and Microsoft.

### Fixed

- **Local auth accepted any password.** `LocalAuthProvider.signIn` and
  `DVLocalAuthProvider.signInWithEmailAndPassword` returned a user for any
  e-mail with any password and never stored the password at sign-up. Both now
  keep salted hashes and reject an unknown account or a wrong password. They
  remain development and test adapters.
- **Shipped features were unreachable from applications.** `dartvel_flutter`
  re-exports core through a `show` list, and `DVDatabaseQueueAdapter`,
  `DVJobPayloadCodec(s)`, `LocalAuthProvider` and `AuthProvider` were missing
  from it — the durable-queue feature was unusable despite passing its own
  tests. The focused entrypoints (`package:dartvel/dartvel_ai.dart` and
  siblings) exported only their facade, so no adapter could be passed to
  `configure`. Both surfaces now have tests that import the way an application
  does and fail to compile when a symbol is missing.

### Changed — breaking

- `DV.Cache.revalidateTag` returns `Future<Set<String>>`; it now removes
  entries through the configured adapter.
- `DV.Test.fakeStorage()` returns a `DVMemoryFileStorageAdapter` rather than the
  raw `Map`, and a missing object throws `DVFileStorageException` rather than
  `StateError`.
- `LocalAuthProvider` requires an account to exist before sign-in and raises the
  minimum password length to 8; failures are `AuthException` carrying an
  `AuthFailure`.

### Not implemented

Recorded so the gaps are visible rather than assumed: Postgres, MySQL, MongoDB,
Turso, ClickHouse and BigQuery databases; Redis and Memcached cache; Redis,
SQS, Pub/Sub, RabbitMQ and Kafka queues; PostgreSQL full-text search; Azure
Blob and Google Cloud Storage; APNS, which needs HTTP/2, and Web Push, which
needs P-256 ECDH and AES128GCM payload encryption; magic links, OTP, LDAP and
SAML; and the `DV.Platform` device APIs, which need generated JNI/FFI bindings.

### Verified

- `packages/dartvel_core`: `dart analyze`, `dart test` (99 → 309 tests).
- `packages/dartvel_flutter`: `dart analyze`, `flutter test` (41 tests).
- `packages/dartvel`: `flutter test` (new entrypoint tests).
- `packages/dartvel_cli`: `dart test` (156 tests).
- `examples/dartvel_example`: `flutter build web`, including the Wasm dry run,
  confirming the conditional imports keep `dart:ffi` and `dart:io` out of web
  output.

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
