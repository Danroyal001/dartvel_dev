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
| **Platform APIs** | Runtime platform and screen detection; device APIs are scaffolded pending native plugins | ⚠️ Partial |
| **Authentication** | API surface and prebuilt page placeholders; provider integrations are not complete | ⚠️ Scaffold |
| **Database & Cache** | API surface plus local primitives; external DB/Redis adapters are not complete | ⚠️ Partial |
| **PWA & SEO** | Automatic PWA manifest/worker & runtime/global SEO injection | ✅ Implemented |
| **AI Integration** | API surface and annotations; provider calls are not complete | ⚠️ Scaffold |

Reference ./NEW_SPEC.md for the full new spec.

## Native Integration Rules

- Do not use Flutter platform channels, `MethodChannel`, `EventChannel`, or `BasicMessageChannel` for Dartvel native APIs.
- Native integrations must be generated or bound through FFI/ffigen for C/Rust/native libraries and JNI/jnigen for Android/JVM APIs.
- Flutter-facing APIs should remain stable under `DV.Platform.*`; generated native bindings adapt behind that surface.

## Release & Tag Backup Rule

- Every release or tag must also create and push a branch that points at the same commit.
- Use a stable backup branch name such as `backup/<tag-name>` or `release-backups/<tag-name>`.
- Push the backup branch before or immediately after pushing the tag so a default-branch force push cannot erase the release state.
