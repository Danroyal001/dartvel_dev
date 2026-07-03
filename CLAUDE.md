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
| **UI Primitives** | `DVBox`, `DVText`, fluent styling built on `Mix` | 🛠️ Implemented |
| **Routing** | File-based pages router with strongly-typed navigation | 🛠️ Implemented |
| **State Management** | Riverpod-powered signals (`context.signal`, reactive models, `DV.global`) | 🛠️ Implemented |
| **Models & Forms** | `@DVModel` annotation + `DVForm<T>` automatic inputs | 🛠️ Implemented |
| **Backend Runtime** | Axum/Tokio Rust server calling Dart FFI, supporting SSE streams | ✅ Implemented |
| **Platform APIs** | `DV.Platform` device APIs, camera, location, orientation | 🛠️ Implemented |
| **Authentication** | `DV.Auth` with multiple provider wrappers | 🛠️ Implemented |
| **Database & Cache** | Unified DB (Postgres, SQLite, Turso) & Cache (Memory, Redis) | 🛠️ Implemented |
| **PWA & SEO** | Automatic PWA manifest/worker & runtime/global SEO injection | 🛠️ Implemented |
| **AI Integration** | `DV.AI` Gemini/Claude chat and structured outputs | 🛠️ Implemented |


Reference ./NEW_SPEC.md for the full new spec.
