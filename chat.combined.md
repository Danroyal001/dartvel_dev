# Dartvel Framework - Master Context & Instructions

> **Note to AI**: This file serves as the centralized source of truth for project context, coding standards, and current objectives. Read this first.

## 1. Project Overview
**Dartvel** is a framework for simplifying the creation and deployment of fullstack Flutter and Dart apps.
It aims to be the **"Next.js/Expo of Flutter"**, merging features from Serverpod, Expo, Shorebird, Codemagic, Next.js, and Nuxt.js.

**Core Goals:**
- **Structured Project Organization**
- **File-based Routing** (Next.js style)
- **Backend Functions** (WinterCG compliant)
- **OTA Updates** (Shorebird)
- **Cloud Builds** (Codemagic)
- **Multiplatform Support**: Android, iOS, Windows, macOS, Linux, Android TV, Apple TV, Tizen, WebOS, Embedded Linux.

---

## 2. Current Objective (Phase 6: Expansion & Completion)
**User Prompt:**
> "Continue, go CRAZY with the project, build out the entire framework to completion... Commit along the way so it's easy to revert, with support for android, ios, windows, macOS, linux, androdi TV, appleTV, Tizen, WebOS, embedded linux. Test end to end extensively... Test all the dartvel commands and their aliases... Let's integrate build_runner so we don't have to generate files manually. For the dartvel_shelf backend, make sure all heavy lifting happens in rust, with little to no unsafe code and minimal ffi hops. Update the documentation for each module and the top level documentation to match."

**Key Tasks:**
1.  **Build Runner Integration**: Automate file generation.
2.  **Rust Backend Optimization**: Minimize FFI hops, ensure safety.
3.  **Cross-Platform Support**: Verify all listed platforms.
4.  **Extensive Testing**: E2E tests for all commands and flows.
5.  **Documentation**: Update all modules.

---

## 3. Code Generation Guidelines (Best Practices)

### Output Contract
- **Preface**: Objective, assumptions, inputs/outputs.
- **Self-contained code**: Runs as-is.
- **Comments**: Explain *why*, not *what*.
- **Tests**: Basic unit or integration tests.

### Readability & Style
- **Naming**: `snake_case` (Python/Dart files), `camelCase` (JS/Dart vars), `PascalCase` (Types).
- **Functions**: Small, single responsibility.
- **Dependencies**: Minimal, justified.

### Security
- **Input Validation**: Sanitize all external inputs.
- **Secrets**: NEVER hardcode. Use env vars (`PUBLIC_*` for client-safe).
- **Filesystem**: Safe paths, no traversal.

### Efficiency
- **Data Structures**: Choose wisely (Big-O).
- **Async I/O**: Prefer over blocking.
- **Caching**: Use where appropriate.

### "Never Do This"
- ❌ Hardcode secrets.
- ❌ Use `eval`/`exec`.
- ❌ Swallow exceptions silently.
- ❌ **USE EMOJIS ANYWHERE IN THE CODEBASE** (Strictly forbidden, except where explicitly allowed).

---

## 4. Special Instruction: Doctor Command
**File**: `packages/dartvel_cli/lib/src/commands/doctor_command.dart`

**Requirements:**
1. ✅ Work from ANY directory (no pubspec.yaml required).
2. ✅ Check system deps: Dart, Flutter, Git, Shorebird (optional), Codemagic (optional).
3. ✅ Run `flutter doctor -v` at the end.
4. ⛔ **ABSOLUTELY NO EMOJIS**. Use `[+]`, `[-]`, `[!]`.
5. ✅ **Clear Boundaries**: Use separator lines between sections.

**Expected Output Format:**
```text
Dartvel Doctor
==================================================
[+] Dart SDK: ...
--------------------------------------------------
Optional Tools
--------------------------------------------------
[-] Shorebird: ...
...
==================================================
Flutter Doctor Output
==================================================
...
```

---

## 5. Development Context & Roadmap (History)

### Completed Phases (v0.1 -> v0.3)
- **Phase 0**: Setup, Config Migration, Env Handling (`.env`).
- **Phase 1**: Routing, UI Enhancements (`.loading.dart`, `.error.dart`), SSG basics.
- **Phase 2**: CLI Improvements (`create`, `preview`, `plugin add`, `updates push`).
- **Phase 3**: OTA (Shorebird) and Plugins.
- **Phase 4**: Documentation and Testing.
- **Phase 5**: Rust Backend Integration (FFI), CLI Refactor.

### Feature Checklist (Remaining/Ongoing)
- [ ] Advanced Routing (Deeplinking, URL scheme, Bundle splitting)
- [ ] Database Integration / ORM
- [ ] Authentication / Middleware
- [ ] Caching & Queued Tasks
- [ ] Multiplatform Support (TVs, Embedded)
- [ ] Analytics & Monitoring
- [ ] Admin/CMS Dashboard
- [ ] Drag-and-Drop / AI Code Assist

---

## 6. Project Structure (Reference)
- `packages/dartvel_core`: Core helpers, types.
- `packages/dartvel_flutter`: Flutter widgets, SEO, transitions.
- `packages/dartvel_cli`: CLI tool (`dartvel`).
- `packages/dartvel_shelf`: Rust-powered backend server.
- `packages/dartvel_generator`: Code generation logic.
- `example/dartvel_example`: Reference implementation.

---

## 7. Feature Checklist (Comprehensive)

### Core Features
1. [ ] Structured Project Organization
2. [ ] Dartvel CLI, Scaffolding generators
3. [ ] Platform API access
4. [ ] Advanced Routing (File-based, Config based, Deeplinking, URL scheme, Route bundle splitting)
5. [ ] Backend functions and API Management + Streaming + WebSockets (WinterCG/WinterTC Compliant)
6. [ ] Over-the-Air (OTA) Updates and patches (Like Expo Updates, powered by Codemagic and ShoreBird)
7. [ ] Templating
8. [ ] Database integration / Migrations / ORM
9. [ ] Authentication, Authorization, Middleware
10. [ ] Caching
11. [ ] Push and Email (requires server) Notifications
12. [ ] Queued Tasks / Background tasks / Scheduled Tasks
13. [ ] Permissions management
14. [ ] Config management
15. [ ] UI Scaffolding (Forms, Tables, Premium Starter Kits, etc)
16. [ ] Multiplatform support (Android, iOS/iPadOS, Web, Windows, Linux, macOS, Android TV, WearOS, tvOS, watchOS, WebOS, Tizen)
17. [ ] Internationalization and Localization
18. [ ] Quick Previews in the preview app (Like Expo Go)
19. [ ] Cloud builds via DartvelCloud (Like EAS, powered by CodeMagic)
20. [ ] Store Signing and publishing via DartvelCloud
21. [ ] Environment variables management
22. [ ] Image/Asset optimization
23. [ ] Analytics, Monitoring, Crashlytics and Logging
24. [ ] Event system, Pub/Sub
25. [ ] Web SEO
26. [ ] Custom CLI Commands
27. [ ] Dartvel Cloud (Edge Deployment)
28. [ ] In-build opt-in Admin/CMS dashboard
29. [ ] Server hydration / initial server data
30. [ ] Utils for strings, arrays, hashmaps, dates, cross-platform concurrency
31. [ ] Remote config / Feature flags
32. [ ] Drag-and-Drop / AI-Driven Development with Code Assist
33. [ ] Compliance features (audit logs, GDPR tools, HIPAA-ready)

