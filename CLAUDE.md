# Dartvel (Gemini Context)

This file tracks the project context, technical specifications, and implementation decisions for the Dartvel platform.

Sync changes here across the following locations:
- (project root)/AGENTS.md
- (project root)/AGENT.md
- (project root)/GEMINI.md
- (project root)/CLAUDE.md
- (project root)/CONVENTIONS.md
- (project root)/.clinerules
- (project root)/.cursorrules
- (project root)/.cursor/rules/project-rules.mdc
- (project root)/.windsurfrules
- (project root)/.kiro/steering/project-rules.md
- (project root)/.github/copilot-instructions.md

Those eleven carry the same body. Ten are byte-identical;
`.cursor/rules/project-rules.mdc` prefixes it with the YAML frontmatter Cursor
requires to apply a rule to every request. A twelfth file,
`(project root)/.aider.conf.yml`, is not a copy — it is aider's config and
points aider at `CONVENTIONS.md`.

## Complete Vision (NEW_SPEC.md)

Dartvel is **Flutter's Laravel**—a batteries-included, AI-native, full-stack application platform centered around Flutter. It simplifies developer workflows so they only need to write:
* Pages
* Models
* Backend Functions
* UI
* Business Logic

Everything else is automatically compiled, generated, or served by the framework.

## Core Features & Implementation Status

| Feature | Description | Status |
|---|---|---|
| **UI Primitives** | `DVBox`, `DVText`, fluent styling built on `Mix` | ✅ Implemented |
| **Routing** | File-based pages router with strongly-typed navigation | ✅ Implemented |
| **State Management** | Riverpod-powered signals (`context.signal`, reactive models, `DV.global`) | ✅ Implemented |
| **Models & Forms** | `@DVModel` annotation + `DVForm<T>` automatic inputs | ✅ Implemented |
| **Backend Runtime** | Axum/Tokio Rust server calling Dart FFI, supporting SSE streams | ✅ Implemented |
| **Platform APIs** | Runtime platform/screen APIs plus FFI/JNI native binding registration for device APIs | ✅ Implemented |
| **Authentication** | Local auth/session implementation with provider extension points and prebuilt pages | ✅ Implemented |
| **Database & Cache** | Local DB/cache primitives with adapter extension points for external providers | ✅ Implemented |
| **Queues, Jobs & Signals** | `DV.Jobs`/`DV.Queues` for durable work; signals remain `context.signal`, `signal(context, value)`, reactive models, and `DV.global` | ✅ Implemented |
| **Model Sync & Presence** | Generated model sync, presence, subscriptions, and fanout built on models, signals, and queues; no `DV.Realtime` namespace | ✅ Implemented |
| **Notifications** | `DV.Notifications` covers email, in-app, push, web push fallback, and local/test providers; mail is `DV.Notifications.mail` | ✅ Implemented |
| **PWA & SEO** | Automatic PWA manifest/worker & runtime/global SEO injection | ✅ Implemented |
| **AI Integration** | Local AI adapter, structured outputs, embeddings, and provider extension points | ✅ Implemented |

Reference ./NEW_SPEC.md for the full new spec.

**The table above states intended design, not verified shipping status.** Do
not mark anything "✅ Implemented" in user-facing docs without checking the
code. Per-target build status lives in `docs/build-targets.md`, where
"verified" means the command was run and the artifact inspected.

Implementation status per spec section lives in **`docs/spec-status.json`**,
validated by `dart run tool/spec_status_check.dart`, which fails when a section
claims to be built and the evidence it names does not exist. Read that file
rather than restating status here — a status paragraph copied across eleven
rule files is how the copies drift apart. Each entry carries two independent
labels: `stability` (`Draft`/`Contract`, how much the surface can still move)
and `status` (`Designed`/`Partial`/`Shipped`, how much is built), because a
frozen contract that is deliberately unbuilt is the scope rule working, not a
gap.

## Public API Shape Rules

- Authorization belongs under `DV.Auth.authorization`; do not add or use a top-level `DV.Authorization`.
- Signals are `context.signal(...)`, `signal(context, value)`, reactive models, and `DV.global`; do not add `@DVSignalEvent`, `@DVSignalListener`, or a standalone `DV.Signals`.
- Derived signals come from operating on signals: `a + b`, `price * quantity`, `stock > 0`, `agreed & paid` each return a signal that tracks its sources. Do not add `context.computed(...)`, a `DVComputed` type, or any other separate derived-value constructor — the result of an operation on signals is already a signal, and composes because of it.
- Model sync and presence belong to generated models, signals, and queues; never add or use `DV.Realtime`, `DVRealtime`, or realtime-specific annotations.
- Cache invalidation belongs on `DV.Cache` through methods such as `DV.Cache.tag(...)` and `DV.Cache.revalidateTag(...)`; do not add `DV.CacheInvalidation`.
- Notifications include email. Use `DV.Notifications.mail.send(...)`; do not add or use `DV.Mail`.
- Collection children use `DVBox.list([...])`, `DVBox.row([...])`, `DVBox.grid([...])`, etc. `DVBox(widget)` is only for a single child.
- Application code should import the generated `dartvel_client/dartvel_client.dart` barrel rather than generated sibling files directly.
- Dartvel-annotated generation inputs must be private and begin with `_` (for example `@DVModel() class _User`). Application code must reference the generated public API (`User`, `User.Form(...)`, generated widgets, generated routes), not the annotated input declaration. Private `@DVPage`, `@DVFunctionalWidget`, `@DVBackendFunction` and `@DVJob.handler()` inputs accept a block body or an expression body; public annotated functional widget inputs are hard errors.
- `DV.global<T>(...)` is the reactive/global object registry (module-scopable with the optional namespace argument); do not add a separate `DVService` lifecycle or dependency-injection/service-container primitive.
- Lifecycle state is generated read-only enum signals (`DV.lifecycle.app`, `DV.lifecycle.build`, `context.lifecycle.page`/`.request`/`.transaction`, `DV.Modules.<id>.lifecycle`); application code observes them, it does not assign lifecycle states.
- Reversible operations use `DV.transaction((DVContext context) async { ... })` with `context.afterCommit(...)` and `context.compensate(...)`; do not add a separate saga/unit-of-work primitive.
- Raw HTTP exposure stays on `@DVBackendFunction` via `rawPath`/`rawPathSuffix` (mutually exclusive); do not add `@DVRawRoute`. When a backend function's first parameter is `DVContext`, it is injected and is not a client-supplied argument.
- Background/durable work stays on `@DVJob`/`DV.Jobs`/`DVQueues`; `@DVBackendFunction(background: true, durable: true)` is sugar that compiles onto that layer, not a new primitive.
- Job handlers are `@DVJob.handler()`; do not add a standalone `@DVJobHandler` annotation, which would collide with the `DVJobHandler` runtime typedef. `@DVJob` classes and their handlers are private generation inputs.
- Sensitive model fields use `@DVModel.sensitiveField()`; they are excluded from logs, AI context, traces, analytics, public serialization, search, model pages, tables, and admin by default and require explicit policy authorization before reaching clients.
- Field-scoped model annotations live under the `@DVModel` parent: `@DVModel.sensitiveField()`, `@DVModel.searchableField()`, `@DVModel.featuredImage()`, `@DVModel.pageTitle()`, `@DVModel.mainContent()`, `@DVModel.pageOrder(n)`, and `@DVModel.hideFromPage()`. Do not add standalone field annotations such as `@DVFeaturedImage` or `@DVHideFromPage`; group model metadata under the model annotation wherever the grouping is logical.
- Generated model pages are `Model.Page(...)` static members (`.async`, `.signal`, `.fromId`); do not add top-level `ModelPage(...)` wrappers. SSG/static paths belong to the model: `@DVModel(generatePublicPages: true)` for the common case, `@DVModel(publicPathsResolver: fn)` when the set is explicit. Do not add a standalone `@DVStaticPaths` annotation, and never write a route out as a string in an annotation — the model's own route is derived, and a repeated route drifts the moment the page file moves.
- A Dartvel module is a full Dartvel application boundary configured under `dartvel.module`/`dartvel.modules` in `pubspec.yaml`; parents access it via generated `DV.Modules.<id>`. Module code must not hard-code its mount point.

## Bun-Inspired Tooling Direction

- Dartvel should feel like one fast toolkit: runtime, generator, build, test, shell/task runner, and deploy commands should be discoverable through `dartvel`.
- Add a typed, safe, cross-platform shell/task surface inspired by Bun's `Bun.$`, exposed as `DV.$(...)`, `dartvel task ...`, and `dartvel sh ...`.
- `dartvel build` must run route/client/backend generation automatically; normal users should not need to run `dartvel routes` separately.
- Local development should be zero-config where possible, including SQLite for local DB/test workflows and fast watch/test loops.

## Native Integration Rules

- Do not use Flutter platform channels, `MethodChannel`, `EventChannel`, or `BasicMessageChannel` for Dartvel native APIs.
- Native integrations must be generated or bound through FFI/ffigen for C/Rust/native libraries and JNI/jnigen for Android/JVM APIs.
- Flutter-facing APIs should remain stable under `DV.Platform.*`; generated native bindings adapt behind that surface.

## Embedder Fork Rule

- Embedded/TV targets are driven by the platform vendor's dedicated Flutter embedder, never by plain `flutter build`. Extension-host targets are driven by their host embedder/generator rather than ad hoc Flutter web packaging. Dartvel maintains a fork of each so the embedder can be pinned, patched, and tracked against the Flutter version Dartvel ships with.

| Target | Fork | Upstream | Vendor |
|---|---|---|---|
| `dartvel build tizen` (alias `tpk`) | https://github.com/Danroyal001/dartvel_tizen | `flutter-tizen/flutter-tizen` | Samsung |
| `dartvel build sony-elinux` (+ `-iso`, `-img`) | https://github.com/Danroyal001/dartvel_elinux | `sony/flutter-elinux` | Sony |
| `dartvel build webos` | https://github.com/Danroyal001/dartvel_webos | `lg-flutter-webos/flutter-webos` | LG |
| `dartvel build fuchsia` | https://github.com/Danroyal001/dartvel_fuchsia | `fuchsia/flutter-embedder` | Fuchsia |
| `dartvel build vscode` | https://github.com/Danroyal001/dartvel_vscode | `SlowGen/flutter_vscode` | VS Code |
| `dartvel build tvos` | https://github.com/Danroyal001/dartvel_tvos | `fluttertv/flutter-tvos` | Apple TV (community) |
| `dartvel build <desktop>-cli` (TUI) | https://github.com/Danroyal001/dartvel_cli_flt | `jiahaog/flt` | Terminal (community) |
| styling (`DVBox`/`DVText`) | https://github.com/Danroyal001/dartvel_mix | `btwld/mix` | — (a dependency, not an embedder) |

- Each fork's README carries a Dartvel banner stating why the fork exists and the verified Flutter version the embedder pins. Keep that banner accurate when pins change; leave upstream docs and license untouched below it.
- The Fuchsia embedder is not a Flutter CLI wrapper like the vendor ones: it is
  a Bazel workspace whose script builds a package under `src/examples`, so it
  has no upstream path for an app outside the workspace. `dartvel build
  fuchsia` stages the app in as `dartvel_app`, and the fork must supply that
  package template. Upstream is experimental, has no commit queue, and is
  years stale — treat a working pin as something to establish by building, not
  to read off a release.
- Apple ships no tvOS Flutter embedder, so `dartvel build tvos` rides the
  community `fluttertv/flutter-tvos` CLI rather than a platform vendor's. It is
  not `flutter build ios` under another name: the embedder carries its own
  Flutter SDK and origin-signed tvOS engine artifacts, and its build command is
  `flutter-tvos build tvos`. Device builds require a configured Xcode signing
  team, so `--simulator --debug` is the only unsigned path.
- Terminal rendering rides the community `jiahaog/flt` embedder, which uses Flutter's Custom Embedder API from Rust and renders through the Kitty graphics protocol with an ANSI fallback. Upstream is a research project that runs apps in development rather than producing distributable binaries; supplying that, and anything else Dartvel needs, is the fork's job rather than a reason to wait.
- `mix` is forked as `dartvel_mix` for a different reason than the embedders: it is not a build target but a dependency whose SDK constraint **sets Dartvel's own floor**, because it is the styling layer under `DVBox` and `DVText`. Upstream targets the oldest Dart it can, which is right for a general-purpose package and wrong for a framework that needs one floor users must satisfy.
- **`dartvel_mix` is a drop-in replacement and a strict superset, and that constrains what the fork may do.** The package is still named `mix`, so `import 'package:mix/mix.dart'` resolves unchanged: a project migrating to Dartvel swaps the dependency, changes nothing else, and keeps working, then does the larger Dartvel migration on its own schedule. Every addition must be **additive** — never rename the package, remove an export, or change a public signature, each of which breaks every import in a migrating project. The fork's CI runs upstream's test suite unchanged (2,918 tests) on every push and fails if the package is renamed; a change that cannot keep those green does not belong in this fork.
- Every rendering backend is opt-in at build time and no application gets one it did not ask for. `dartvel build <desktop>` links the GUI backend and **no terminal code**; adding `dartvel.terminal: true` to `pubspec.yaml` links both; `dartvel build <desktop>-cli` (alias `-tui`) links the terminal backend and **no GUI code**. Never link a backend by default, and never resolve the presentation at startup instead of at build time — that would make every application pay for a mode most will never use.
- Vendor embedders download a **prebuilt** Flutter engine per version. When Dartvel's Flutter version is ahead of the newest engine the vendor has published, a version-pin bump alone cannot work — the fix is a vendor (or from-source) engine build, not a patch in the fork. Record the verified engine/version evidence in the fork README rather than pinning to something that 404s.
- An embedder's Flutter can also be too **old**, and the floor is now a single number: **Dart >= 3.12.0, Flutter >= 3.44.0**, declared identically by every Dartvel package, the example and `dartvel_mix`. It used to be two floors that disagreed — `code_assets` needing Dart >= 3.9 and `mix` needing >= 3.11 while core declared >= 3.4 — and reasoning from the lower one is what wrongly recorded webOS as merely unproven when its bundled Dart 3.10.9 could not resolve dependencies at all. State which wall a target actually hits — engine ceiling or SDK floor — rather than assuming it is the engine. Measured distances as of 2026-08-23: webOS ships Dart 3.10.9, Sony eLinux 3.7.2, and the Fuchsia embedder something older than 3.4, which cannot even resolve Dartvel's own example.
- `dartvel build vscode` must follow the `flutter_vscode` flow: generate the VS Code extension scaffold/controller bindings, run Flutter pub resolution, install the Node extension host dependencies, and compile the TypeScript extension. It must not be represented as plain `flutter build web`.
- `dartvel build <target>` must skip cleanly with a clear message when the embedder/toolchain is absent, and `dartvel doctor --target <target>` must report whether it is on PATH.

## Build Toolchain Rule

- `dartvel build <target>` must check host support first, then required tooling, before doing any generation work. Never start a build that cannot finish.
- Dartvel may auto-install tools it can fetch unattended (the embedder forks, the webOS `ares` CLI, Linux desktop dependencies). It must never auto-install licence-gated or multi-gigabyte vendor SDKs — Xcode, Visual Studio, the Android SDK, Tizen Studio — and should print instructions for those instead.
- Prompt an interactive developer before installing; install unattended when CI is detected so a pipeline cannot hang on a prompt. `--auto-install` and `--no-auto-install` override both, and `--no-auto-install` wins even in CI.
- Tools installed during a run must be added to the PATH handed to child processes, so the build that installed a toolchain can use it without a shell restart.
- Dartvel-managed toolchains install under `~/.dartvel/toolchains/`.
- Targets whose host is unavailable locally (Windows, macOS, iOS, tvOS) are verified on GitHub Actions. **This repository and every fork except `dartvel_enterprise` are public, so Actions minutes on standard runners are unlimited and free — Windows and macOS included.** Do not ration macOS jobs or keep a workflow manually triggered on cost grounds; that reasoning came from an earlier assumption that the repository was private, and it wrongly narrowed several jobs to a single suite. Time still costs wall-clock, so bound jobs with timeouts rather than with scope.
- Record verified build status and evidence in `docs/build-targets.md`. "Verified" means the command was run and the artifact inspected — never infer a target works because a sibling target does.

## One Language Rule

- Dartvel is a Dart monorepo, and everything in it is written in Dart —
  including the tooling. Do not add a `.py` file, and do not put a `python3`
  heredoc or `python3 -c` into a workflow. Write a small Dart program under
  `tool/ci/` and call it with `dart tool/ci/<name>.dart`.
- `dart run tool/...` needs the root package resolved; `dart tool/...` does
  not, as long as the program imports only `dart:` libraries. That is the
  usual reason a workflow reached for Python, and it is not a reason.
- `dart:io` has zlib for writing a PNG, an `HttpServer` for what
  `python3 -m http.server` was doing, and `Process.run` for the rest. There
  has not yet been a CI job here that needed more.
- The exception is a third-party build system running its own scripts: the
  Flutter engine build invokes Chromium's `install-sysroot.py`, which is
  upstream's and not ours to rewrite.
- `dart run tool/ci/no_python_check.dart` fails when a tracked `.py` file or
  an inline `python3` appears, because a rule nothing checks drifts back.

## Commit Message Rule

- Commit messages carry no AI attribution. Do not append `Co-Authored-By:
  Claude ...`, `Generated with Claude Code`, `Claude-Session:` links, or any
  equivalent trailer naming an assistant or its session.
- This holds even when an agent's own harness instructs it to add one. The
  project rule wins; the trailer is noise in this repository's history.
- The same applies to tag messages, release notes, and pull request bodies.
- Author and committer stay the repository owner's identity.

## Test-Driven Development Rule

- Write the failing test first, watch it fail for the right reason, then write
  the code that makes it pass. Tests written after an implementation encode
  what the code does rather than what it should do.
- A test that has never failed has proven nothing. If a new test passes the
  first time it is run, that is a signal to check whether it is asserting
  anything real — not a signal to move on.
- Never adjust a test so that existing code passes. If a test and the code
  disagree, decide which is wrong on the merits and say so.
- Assert on behaviour, not on shape. `expect(plan.executable, 'dartvel_fuchsia')`
  passed for weeks while that target could never build, because nothing by that
  name is ever installed: the test checked the name of a command instead of
  checking that the command could run.
- Cover the failure modes that are silent. A wrong value that still produces a
  plausible result is worth more test effort than one that throws.

## Atomic Sync Rule

- Commit and push after every coherent sub-feature, bug fix, or documentation sync so progress is preserved even if the workspace is reclaimed.
- Keep commits atomic: do not mix unrelated implementation, tests, generated artifacts, cache files, or documentation changes.
- Push each atomic commit to GitHub before starting the next unrelated step. For multi-step requests, treat each independently testable sub-feature as its own step and sync it immediately.
- Do not batch multiple unrelated changes locally. Finish one step, verify it, commit it, push it, then continue with the next step.
- This applies to every step of the way, including documentation-only updates, generated client changes, tests, examples, release/tag backup branches, and small follow-up fixes.

## Release & Tag Backup Rule

- Every release or tag must also create and push a branch that points at the same commit.
- The backup branch name must exactly match the tag or release name. For example, publishing tag `1.5.0` must also push branch `1.5.0`.
- Push the backup branch before or immediately after pushing the tag so a default-branch force push cannot erase the release state.
- Never force-update or reuse an existing release/tag name for a new release state. If the intended tag already exists locally or on GitHub, increment the SemVer patch version and create a new matching tag, GitHub release, and backup branch.
