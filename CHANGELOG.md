# Changelog

All notable changes to this project will be documented in this file.

Dartvel is pre-1.0. Minor versions may contain breaking changes; breaking
changes are called out explicitly below.

## Unreleased

Two tranches of work. The first filled in provider and adapter implementations
for subsystems that had an API surface but no way to reach a real service. The
second built the subsystems the spec named and nothing stood behind — Studio,
GraphQL, model sync and presence, MCP, the generated admin — and then went
looking for the difference between what the documentation claimed and what a
clean checkout could actually do.

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
- **`DV.Navigation`.** The spec makes it the navigation API, with `go_router` an
  implementation detail behind it, but only `context.navigateToPage(...)`
  existed. `DV.Navigation.to(target)` returns a `VoidCallback` for use in
  handlers, so the generated `createDartvelRouter()` hands the live router to
  `DVNavigation.attach`. Navigating with no router attached throws naming
  `createDartvelRouter()`.
- **`DV.Secrets`.** Only `PUBLIC_`-prefixed variables reach the generated
  `env.g.dart`, so nothing else was readable. Secrets resolve from the process
  environment through a conditional import; a web build resolves nothing and
  says to fetch the value through a backend function, because a secret compiled
  into a browser bundle ships to every visitor.
- **`DV.Tenants`.** `DV.currentTenant` is now genuinely an alias for it.
  Tenants resolve from a subdomain, header, path prefix, query parameter or a
  supplied resolver, and `CommonMiddleware.tenant(require: true)` aborts a
  request that names none rather than serving the default tenant's data. The
  `tenant` middleware name previously passed build validation while resolving
  nothing.
- **`DVImage`.** The spec declares `final DVImage? avatar` on a model; the type
  did not exist. It is a value so models can serialize it, with `DVImageView`
  as the rendering half, and `fromJson` accepts a bare URL string.
- **Platform device namespaces.** `DV.Platform.Location`, `.NFC`, `.Camera` and
  the rest now carry the names the spec uses, each with a top-level `DV.X`
  proxy. `DV.Platform.FileStorage` and `.Notifications` return the `DV.*`
  surfaces rather than a parallel platform-local copy.
- **Generated jobs.** `@DVJob` was an annotation nothing read. The generator now
  emits the public payload with `fromJson`/`toJson`, a `dispatch()` carrying the
  annotation's queue, priority, attempts and backoff, and `DVJobQueues`
  constants; codecs and handlers register from `configureDartvelRuntime()`.
  Handlers are `@DVJob.handler()`. Generation fails on a handler for a job no
  `@DVJob` declares and on two handlers for one job.
- **Semantic model pages.** `Page.sync` rendered `Model.Card` — the flat field
  dump a list row uses. Pages now compose as featured image, title, main
  content, then the remaining fields, with `@DVModel.featuredImage()`,
  `.pageTitle()`, `.mainContent()`, `.pageOrder(n)` and `.hideFromPage()` as
  overrides. Main content resolves at render time because the largest text block
  depends on the record, not the schema.
- **`dartvel cache` reaches a persistent cache.** `clear` took only in-process
  tag metadata; it now takes `--database`/`--table`, and `cache purge` drops
  expired entries. Tag output says it reflects the CLI process only.

- **Dartvel Studio.** The WordPress-style admin whose page builder sits between
  a free canvas and a page editor, manipulating real widgets rather than a
  canvas facsimile. `DVPageDocument` is the serializable widget tree;
  `DVPageDocumentEditor` is the four operations every builder gesture reduces
  to — insert, remove, move (which refuses a drop into the node's own subtree),
  update. `DVPageDocumentRenderer` instantiates the actual `DVBox`/`DVText`/
  `DVImageView` widgets identically in-editor and in-app, with bound actions
  driving `DV.Navigation`, and `DVPageStore` persists through `DV.Database` —
  saving is publishing, page content is data. The running app serves stored
  pages and reloads them on save, a stored document overrides the compiled page
  rather than the reverse, and pages ship through OTA as versioned bundles.
  Visual backend workflows follow the same shape: a runner, a store, code
  export, and a canvas where steps drag into condition branches with undo/redo.
- **GraphQL.** The spec lists it among the generated APIs and nothing existed.
  This is the executable subset a generated API needs, not a general server
  library: operations, selection sets, arguments, variables, aliases, and named
  plus inline fragments, served at `/graphql`. Error semantics follow the spec —
  a request-level failure returns only errors, while a field-level failure nulls
  that field and appends a named error, so one bad resolver does not take down
  the response. Directives and subscriptions error rather than silently
  no-oping. Models generate their own schema and resolvers, and introspection
  answers `__schema`, `__type` and `__typename`.
- **Model sync, persistence and presence.** The Model Sync and Presence section
  had nothing behind it: no change delivery, and generated models had no `save`,
  `find`, `all`, `watch` or `sync`. `DVModelSync` is the hub the spec's rules
  demand — typed per-model change streams with tenant filtering and policy
  checks applied before delivery rather than in the UI, and a transport seam so
  arriving envelopes re-enter the local streams and remote changes look exactly
  like local ones. `DVPresence` keys channel membership on authenticated
  identity rather than connection, tenant-scoped, expiring on silence because a
  crashed client never sends a departure. Deliberately not a realtime facade;
  the spec forbids one.
- **Generated admin surfaces.** `Model.Admin()` is one call rather than a
  generated screen — the model already knows how to list, save, delete and blank
  itself, so `DVModelAdmin` is the screen around those. Beyond model CRUD: a
  queue and job dashboard with retry and single-job discard, cache/tag and
  route/page explorers showing real state, and outbox, policy/sync, entitlements
  and events surfaces. The admin opens the Studio.
- **MCP, both directions.** `DVMcpServer` serves Dartvel's registered AI tools
  to an MCP client and `DVMcpClient` consumes an external server, with
  `adoptTools()` registering the peer's tools into the same registry so an agent
  run calls a remote tool exactly like a local one. Both speak JSON-RPC 2.0 over
  a transport seam, with a newline-delimited implementation for stdio. The tools
  served are exactly the ones `DV.AI.registerTool` knows about, so a client and
  Dartvel's own agent runs see one surface rather than two registries that
  drift.
- **Databases.** PostgreSQL and MySQL/MariaDB adapters speaking their wire
  protocols directly.
- **Cache and queues.** A Redis adapter with real compare-and-set locks, a
  Memcached adapter, and a Redis-backed durable queue. Cache gained locks,
  stampede protection, stale-while-revalidate, tenant-aware keys and the
  permissioned global helpers.
- **PostgreSQL full-text search.** The index lives in the database rather than a
  separate service: one datastore to operate, and results that cannot go stale
  relative to the rows they came from. Ranking uses `ts_rank` rather than table
  order, and stemming means "learn" finds "learning" — pinned by a test, since
  that is the behaviour a `LIKE` cannot reproduce.
- **Magic links and one-time passcodes.** Two of the four auth providers the
  spec listed with nothing behind them, both the same primitive: a secret issued
  to a channel the user controls, redeemable once, within a window. Only the
  hash is stored, so a dump of the token table does not let anyone sign in, and
  comparison is constant time so a timing difference cannot reveal how much of a
  code was right.
- **Web Push.** `DVNotificationChannel.webPush` was an enum value with nothing
  behind it. A browser subscription cannot be posted to like a device token —
  the push service is untrusted infrastructure, so RFC 8291 encrypts the payload
  end to end against a key only the subscribing user agent holds, and an
  unencrypted body is a protocol error rather than a degraded send. VAPID
  application-server identification ships alongside it.
- **Linux native bindings.** The first native bindings that actually do
  something. Every `DV.Platform` API had thrown "not registered" since the
  bridge existed; eight names now work on Linux desktop through direct libX11,
  libgtk-3 and GDBus calls — `dart:ffi`, not platform channels, per the spec —
  covering clipboard, screen geometry, desktop notifications and window control.
  A binding that cannot be implemented is left unregistered so it still throws
  rather than returning a plausible lie.
- **OpenAPI.** Documents generated for backend functions and served.
- **Middleware.** The `csrf`, `idempotency`, `locale`, `featureFlags` and
  `maintenance` built-ins, which previously passed build validation while doing
  nothing.
- **`context.computed`.** Computed values that stay reactive to their source
  signals, plus a fix for same-type signal collision.
- **SEO and OTA.** Structured data emission, and OTA version gates.
- **New build targets.** `chrome-extension` and `firefox-extension` produce
  loadable MV3 bundles from web output plus a generated manifest and background
  script. `fuchsia` returned as a target on a Dartvel-forked embedder that
  packages an arbitrary Flutter app. `tvos` moved onto the community
  `flutter-tvos` embedder — see *Fixed* for why that matters.
- **Platform scaffold generation.** `dartvel build` generates the platform
  directory an embedder refuses to build without (`tizen/`, `elinux/`, `webos/`,
  `tvos/`) through the vendor's own `create`, rather than failing with a manual
  step. A scaffold that fails partway is removed rather than left to satisfy the
  next run's existence check.
- **Streaming HTTP transport.** `dvStreamHttpRequest` yields a body as it
  arrives and keeps the client open until it ends; `DVHttpResponse.data`
  decodes JSON, returning text when the body is not JSON and null when empty.

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
- **Sensitive fields reached generated exports.** `@DVModel.sensitiveField()` is
  specified as excluded from generated tables, but CSV and Excel emitted a
  column per field and the JSON/NDJSON exports called `toJson()` rather than
  `toPublicJson()` — `Account.Export.csv(accounts)` produced a file containing
  every tax number. Sensitive columns now require
  `DVExportOptions(includeSensitiveFields: true)`.
- **Sensitive fields reached generated forms.** `showInForms` defaults to false,
  but the generator read only the annotated field's name and never its
  arguments, so every sensitive field got a form getter.
- **A source directory was never committed, so no clean clone could build.**
  `.gitignore`'s bare `build/` matches at every depth, and
  `packages/dartvel_cli/lib/src/build/` is a source directory that happens to be
  named build. Its only file existed solely as an untracked file on the machine
  that wrote it — `git log --all` on the path is empty. Because the import sits
  at the top of `build_command.dart`, ahead of any platform dispatch, *every*
  `dartvel build <target>` failed to compile from a fresh checkout. The ignore
  rule now carves out `lib/` trees, and the file is rebuilt against the test
  that did survive.
- **`dartvel build tvos` built an iPhone app.** The CLI mapped `tvos` onto the
  iOS toolchain and ran `flutter build ios --no-codesign`, so the platform
  matrix reported a green tvOS job for an artifact that was not a tvOS app.
  tvOS now runs through the `flutter-tvos` embedder, which carries its own
  Flutter SDK and origin-signed engine artifacts.
- **A model-less application generated a client that did not compile.** The
  generated runtime calls `registerDartvelModels()` unconditionally, but an
  application with no `@DVModel` inputs got a bare `library` stub — the function
  was discarded with the rest of the buffer. Two of the three example apps were
  broken.
- **The native-asset hook built for the host, not the target.** A macOS
  universal build invokes the hook once per architecture and `lipo`s the
  results, so answering both requests with a host-arch dylib failed the link
  with "have the same architectures". The triple now comes from the requested
  target OS and architecture.
- **The same hook could block forever.** Because a universal build runs it twice
  concurrently, both invocations contended on one `~/.rustup` lock, and the hook
  prints nothing while blocked — a build went silent for five hours and
  fifty-six minutes before CI's own cap killed it. Nothing in the hook can wait
  indefinitely now.
- **Toolchain installed, toolchain not found.** Auto-install extends the PATH
  handed to child processes, but the scaffold step did not receive that
  environment, so the availability check resolved an embedder that the very next
  line could not execute.
- **`dartvel doctor` could not answer for three buildable targets.** The
  allowlist was a hand-written literal that rejected `tvos` outright and made
  the browser-extension arms of the check unreachable. It is now derived from
  the build command's own target sets.
- **The generated client depended on a package nothing declared.** It imported
  `dio`, which meant every Dartvel application depended on a third-party HTTP
  package whether it wanted to or not — and until `dartvel_core` declared it,
  none of them compiled. Requests and SSE streams now go through Dartvel's own
  transport.
- **Entitlements were keyed by `hashCode`, so customers shared them.**
- **`DVForm` threw away every edit it collected**, and form fields drew their
  value as a placeholder.
- **Generated models could not survive a JSON round trip**, and the generated
  client did not compile for common field types.
- **Routes starting with an underscore generated private targets.**
- **The generated admin pages called a modifier that never existed.**
- **The `dartvel_shelf` native build was broken** and streaming responses did
  not work.

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

Recorded so the gaps are visible rather than assumed, and corrected as things
ship — an earlier revision of this list went stale and claimed Postgres, MySQL,
Redis, Memcached, PostgreSQL full-text search, Web Push, magic links and OTP
were missing weeks after they landed.

Still absent: MongoDB, Turso, ClickHouse and BigQuery databases; SQS, Pub/Sub,
RabbitMQ and Kafka queues; Azure Blob and Google Cloud Storage; APNS, which
needs HTTP/2; LDAP and SAML; GraphQL directives and subscriptions, which error
rather than silently no-op.

Partial: the `DV.Platform` device APIs. Eight binding names work on Linux
desktop over `dart:ffi`; the other 35 remain unregistered there, and all 43 are
unimplemented on Android, iOS, macOS, Windows and web. An unregistered binding
throws rather than returning a plausible value.

### Verified

Suites, on Linux x64 with Flutter 3.44.5 / Dart 3.12.2:

- `packages/dartvel_core`: 496 passing (6 skipped, needing memcached).
- `packages/dartvel_cli`: 236 passing.
- `packages/dartvel_flutter`: 191 passing.
- `packages/dartvel`, `packages/dartvel_generator`, `packages/dartvel_shelf`:
  4, 2 and 5 passing.
- `examples/`: 16, 1 and 1 passing across the three apps.

Builds, run and inspected rather than inferred:

- `web`, including the Wasm dry run, which is the real check — it fails on
  `dart:ffi` and `dart:io` reachability that plain JS compilation tolerates.
- `linux`, verified by **running** it: the release binary ran headless under
  Xvfb with the hook-built `libdartvel_shelf.so` bundled, and a screenshot
  showed the UI with `DV.Platform` reporting `linux`/`desktop` and signals live.
- `chrome-extension` and `firefox-extension`, with the two manifests confirmed
  to differ rather than one being a copy of the other — Firefox refuses a
  manifest declaring `service_worker`, so a shared one would silently not load.
- `ios`, on a macOS runner: `Runner.app`, 15.4 MB.

`macos` reached Xcode and failed in `lipo`; the fix is in but unverified.
`windows` and `tvos` remain unproven. `sony-elinux` and `webos` are blocked by
Dart version floors in their vendor embedders. See `docs/build-targets.md`,
which records the evidence per target and what each one actually hit.

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
