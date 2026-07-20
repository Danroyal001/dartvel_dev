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

## Public API Shape Rules

- Authorization belongs under `DV.Auth.authorization`; do not add or use a top-level `DV.Authorization`.
- Signals are `context.signal(...)`, `signal(context, value)`, reactive models, and `DV.global`; do not add `@DVSignalEvent`, `@DVSignalListener`, or a standalone `DV.Signals`.
- Model sync and presence belong to generated models, signals, and queues; never add or use `DV.Realtime`, `DVRealtime`, or realtime-specific annotations.
- Cache invalidation belongs on `DV.Cache` through methods such as `DV.Cache.tag(...)` and `DV.Cache.revalidateTag(...)`; do not add `DV.CacheInvalidation`.
- Notifications include email. Use `DV.Notifications.mail.send(...)`; do not add or use `DV.Mail`.
- Collection children use `DVBox.list([...])`, `DVBox.row([...])`, `DVBox.grid([...])`, etc. `DVBox(widget)` is only for a single child.
- Application code should import the generated `dartvel_client/dartvel_client.dart` barrel rather than generated sibling files directly.

## Bun-Inspired Tooling Direction

- Dartvel should feel like one fast toolkit: runtime, generator, build, test, shell/task runner, and deploy commands should be discoverable through `dartvel`.
- Add a typed, safe, cross-platform shell/task surface inspired by Bun's `Bun.$`, exposed as `DV.$(...)`, `dartvel task ...`, and `dartvel sh ...`.
- `dartvel build` must run route/client/backend generation automatically; normal users should not need to run `dartvel routes` separately.
- Local development should be zero-config where possible, including SQLite for local DB/test workflows and fast watch/test loops.

## Native Integration Rules

- Do not use Flutter platform channels, `MethodChannel`, `EventChannel`, or `BasicMessageChannel` for Dartvel native APIs.
- Native integrations must be generated or bound through FFI/ffigen for C/Rust/native libraries and JNI/jnigen for Android/JVM APIs.
- Flutter-facing APIs should remain stable under `DV.Platform.*`; generated native bindings adapt behind that surface.

## Atomic Sync Rule

- Commit and push after every coherent sub-feature, bug fix, or documentation sync so progress is preserved even if the workspace is reclaimed.
- Keep commits atomic: do not mix unrelated implementation, tests, generated artifacts, cache files, or documentation changes.
- Push each atomic commit to GitHub before starting the next unrelated step. For multi-step requests, treat each independently testable sub-feature as its own step and sync it immediately.
- Do not batch multiple unrelated changes locally. Finish one step, verify it, commit it, push it, then continue with the next step.

## Release & Tag Backup Rule

- Every release or tag must also create and push a branch that points at the same commit.
- The backup branch name must exactly match the tag or release name. For example, publishing tag `1.5.0` must also push branch `1.5.0`.
- Push the backup branch before or immediately after pushing the tag so a default-branch force push cannot erase the release state.
- Never force-update or reuse an existing release/tag name for a new release state. If the intended tag already exists locally or on GitHub, increment the SemVer patch version and create a new matching tag, GitHub release, and backup branch.
