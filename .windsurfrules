# Dartvel (Gemini Context)

This file tracks the project context, technical specifications, and implementation decisions for the Dartvel platform.

Sync changes here across the following locations:
- (project root)/AGENTS.md
- (project root)/GEMINI.md
- (project root)/CLAUDE.md
- (project root)/.kiro/steering/project-rules.md
- (project root)/.cursorrules
- (project root)/.windsurfrules
- (project root)/.github/copilot-instructions.md

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

Implemented as of this writing: `DV.lifecycle.*` and `context.lifecycle.*`
(read-only enum signals in `dartvel_core/src/lifecycle/`), `DV.Modules.<id>`
(`src/modules/`), `DV.transaction(...)` with `context.afterCommit`/
`context.compensate` (`src/transaction/`), and `@DVStaticPaths()` (discovered
by `static_paths_generator.dart` into `dartvel_client/static_paths.g.dart`).

Still **not** implemented: `Model.Page` data-mode rendering
(`.async`/`.signal`/`.fromId`) and `@DVModel(generatePublicPages: true)`. The
`DVModelPageDataMode` enum and both annotation parameters exist and are
accepted, but no generator acts on them yet — do not describe them as working.

## Public API Shape Rules

- Authorization belongs under `DV.Auth.authorization`; do not add or use a top-level `DV.Authorization`.
- Signals are `context.signal(...)`, `signal(context, value)`, reactive models, and `DV.global`; do not add `@DVSignalEvent`, `@DVSignalListener`, or a standalone `DV.Signals`.
- Model sync and presence belong to generated models, signals, and queues; never add or use `DV.Realtime`, `DVRealtime`, or realtime-specific annotations.
- Cache invalidation belongs on `DV.Cache` through methods such as `DV.Cache.tag(...)` and `DV.Cache.revalidateTag(...)`; do not add `DV.CacheInvalidation`.
- Notifications include email. Use `DV.Notifications.mail.send(...)`; do not add or use `DV.Mail`.
- Collection children use `DVBox.list([...])`, `DVBox.row([...])`, `DVBox.grid([...])`, etc. `DVBox(widget)` is only for a single child.
- Application code should import the generated `dartvel_client/dartvel_client.dart` barrel rather than generated sibling files directly.
- Dartvel-annotated generation inputs must be private and begin with `_` (for example `@DVModel() class _User`). Application code must reference the generated public API (`User`, `User.Form(...)`, generated widgets, generated routes), not the annotated input declaration.
- `DV.global<T>(...)` is the reactive/global object registry (module-scopable via `namespace:`); do not add a separate `DVService` lifecycle or dependency-injection/service-container primitive.
- Lifecycle state is generated read-only enum signals (`DV.lifecycle.app`, `DV.lifecycle.build`, `context.lifecycle.page`/`.request`/`.transaction`, `DV.Modules.<id>.lifecycle`); application code observes them, it does not assign lifecycle states.
- Reversible operations use `DV.transaction((DVContext context) async { ... })` with `context.afterCommit(...)` and `context.compensate(...)`; do not add a separate saga/unit-of-work primitive.
- Raw HTTP exposure stays on `@DVBackendFunction` via `rawPath`/`rawPathSuffix` (mutually exclusive); do not add `@DVRawRoute`. When a backend function's first parameter is `DVContext`, it is injected and is not a client-supplied argument.
- Background/durable work stays on `@DVJob`/`DV.Jobs`/`DVQueues`; `@DVBackendFunction(background: true, durable: true)` is sugar that compiles onto that layer, not a new primitive.
- Sensitive model fields use `@DVModel.sensitiveField()`; they are excluded from logs, AI context, traces, analytics, public serialization, search, model pages, tables, and admin by default and require explicit policy authorization before reaching clients.
- Generated model pages are `Model.Page(...)` static members (`.async`, `.signal`, `.fromId`); do not add top-level `ModelPage(...)` wrappers. SSG/static paths use `@DVStaticPaths()` or `@DVModel(generatePublicPages: true)`.
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

- Embedded/TV targets are driven by the platform vendor's dedicated Flutter embedder, never by plain `flutter build`. Dartvel maintains a fork of each so the embedder can be pinned, patched, and tracked against the Flutter version Dartvel ships with.

| Target | Fork | Upstream | Vendor |
|---|---|---|---|
| `dartvel build tizen` (alias `tpk`) | https://github.com/Danroyal001/flutter-tizen | `flutter-tizen/flutter-tizen` | Samsung |
| `dartvel build sony-elinux` (+ `-iso`, `-img`) | https://github.com/Danroyal001/flutter-elinux | `sony/flutter-elinux` | Sony |
| `dartvel build webos` | https://github.com/Danroyal001/flutter-webos | `lg-flutter-webos/flutter-webos` | LG |

- Each fork's README carries a Dartvel banner stating why the fork exists and the verified Flutter version the embedder pins. Keep that banner accurate when pins change; leave upstream docs and license untouched below it.
- Vendor embedders download a **prebuilt** Flutter engine per version. When Dartvel's Flutter version is ahead of the newest engine the vendor has published, a version-pin bump alone cannot work — the fix is a vendor (or from-source) engine build, not a patch in the fork. Record the verified engine/version evidence in the fork README rather than pinning to something that 404s.
- An embedder's Flutter can also be too **old**: `dartvel_shelf`'s native-asset build hook requires `code_assets` and therefore Dart >= 3.9, so any embedder pinned below that cannot build a Dartvel app at all. State which wall a target actually hits — floor or ceiling — rather than assuming it is the engine.
- `dartvel build <target>` must skip cleanly with a clear message when the embedder is absent, and `dartvel doctor --target <target>` must report whether it is on PATH.

## Build Toolchain Rule

- `dartvel build <target>` must check host support first, then required tooling, before doing any generation work. Never start a build that cannot finish.
- Dartvel may auto-install tools it can fetch unattended (the embedder forks, the webOS `ares` CLI, Linux desktop dependencies). It must never auto-install licence-gated or multi-gigabyte vendor SDKs — Xcode, Visual Studio, the Android SDK, Tizen Studio — and should print instructions for those instead.
- Prompt an interactive developer before installing; install unattended when CI is detected so a pipeline cannot hang on a prompt. `--auto-install` and `--no-auto-install` override both, and `--no-auto-install` wins even in CI.
- Tools installed during a run must be added to the PATH handed to child processes, so the build that installed a toolchain can use it without a shell restart.
- Dartvel-managed toolchains install under `~/.dartvel/toolchains/`.
- Targets whose host is unavailable locally (Windows, macOS, iOS, tvOS) are verified through the GitHub Actions matrix workflow, which stays manually triggered because this repository is private and macOS runners bill at 10x.
- Record verified build status and evidence in `docs/build-targets.md`. "Verified" means the command was run and the artifact inspected — never infer a target works because a sibling target does.

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
