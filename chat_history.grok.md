# plan.md

## Overview
This plan outlines the evolution of the dartvel framework (based on the v0.1 snapshot in repomix-output.xml) into a v0.3 version that embodies the "Next.js/Expo of Flutter." The focus is on file-based routing, managed workflow, cross-platform features (web SSG, mobile OTA), and DX improvements. All changes preserve existing conventions (_layout.dart, _guard.dart, backend functions with normal params, buildWebSeo for SEO). Incorporate only approved suggestions from the chat history: .loading.dart and .error.dart for UI states, enhanced loadData for SSG, env handling (.env, PUBLIC_*), plugins, Shorebird OTA, CLI commands (preview, plugin add, updates), route conflict detection, and backend defaults for filename.dart as POST with form data.

The plan is designed for implementation using tools like Warp CLI or Claude Code Interpreter. Start with the repomix-output.xml as the base repo, extract it to a working directory, and apply changes sequentially. Test at each phase.

## Goals
- **Next.js-like**: File-system routing with conflict detection, SSG/ISR, SEO, redirects.
- **Expo-like**: Zero-config init, plugins for auth/analytics, OTA updates, unified CLI for dev/build/publish.
- **Flutter Integration**: Cross-platform (web, mobile, desktop), with platform-specific optimizations.
- **Non-Breaking**: No @pageMeta (use buildWebSeo), no middleware/ (use _guard.dart), no .layout.dart (use _layout.dart), no onRequest (keep normal params).

## Phases
Implement in phases for iterative testing.

### Phase 0: Setup and Config Migration
- Extract repomix-output.xml to a repo directory (e.g., dartvel_old).
- Remove dartvel_config.g.dart; all config now in pubspec.yaml -> dartvel:.
- Update CLI to parse pubspec.yaml directly for all values (backendHost, i18n, etc.).
- Add env handling: Load .env/.env.local, expose PUBLIC_* in dartvel_runtime.dart (use envied package).
- Add route conflict detection in CLI (_generate, doctor): Duplicates (e.g., /blog from two files), rogue segments (unclosed [param], malformed [...param]).
- Add backend default: filename.dart → POST with form data parsing (use mime package in dartvel_runtime.dart).

**To Do**:
- Add dependencies: envied, mime, shorebird_code_push.
- Update pubspec.yaml in example/dartvel_example with new dartvel: keys (envFiles, plugins, webPrerender, ota).
- Test: Run dart run dartvel_cli:doctor to check conflicts; add conflicting routes to trigger errors.

### Phase 1: Routing and UI Enhancements
- Add .loading.dart and .error.dart detection in CLI: Import and wrap in DartvelDataLoader.
- Enhance loadData in DartvelPage for SSG.
- Update router.g.dart to use parsed config from pubspec.yaml (embed values directly).
- Add SSG in _generateStaticData: Iterate pages, simulate loadData, output JSON in build/web/_ssg/.

**To Do**:
- Update dartvel_flutter.dart with DartvelLoading and DartvelError abstracts.
- Update DartvelDataLoader to use .loading.dart and .error.dart.
- Update example app: Add index.loading.dart, index.error.dart, blog/[id].loading.dart, blog/[id].error.dart.
- Test: Run dart run dartvel_cli:build; verify _ssg/ JSON files.

### Phase 2: CLI Improvements
- Add init: Scaffold pubspec.yaml with dartvel:, .env, sample pages/loading/error, backend/contact.dart (POST form).
- Add preview: Serve build/web with shelf_static.
- Add plugin add: For 'auth', generate login.page.dart and auth.dart (POST form).
- Add updates push: Wrap shorebird patch for android/ios.
- Add watch: File watcher for routes/env changes.
- Update dev: Unified logs, QR for device.

**To Do**:
- Update dartvel.dart with new commands.
- Add mime parsing in dartvel_runtime.dart for formData in POST handlers.
- Test: Run dart run dartvel_cli:init; dart run dartvel_cli:plugin add auth; dart run dartvel_cli:updates push (after shorebird init).

### Phase 3: OTA and Plugins
- Enable ota: shorebird in dartvel:; CLI checks during build/doctor.
- Plugins: Scaffold code in lib/pages and lib/backend/functions for each plugin.
- Env: Load in Env.load(); expose in runtime.

**To Do**:
- Update doctor to check envFiles, plugins, Shorebird setup.
- Update example with dartvel_auth plugin.
- Test: Run shorebird init; dart run dartvel_cli:updates push.

### Phase 4: Documentation and Testing
- Update CONFIG.md, BOOTSTRAP.md, README.md, ROUTING.md (add conflict detection, backend defaults).
- Add DEPLOYMENT.md: Vercel (SSG), EAS/Codemagic (OTA).
- Test full workflow: init → add plugin → routes (check conflicts) → dev → build (SSG) → preview → updates.

**To Do**:
- Update docs as per artifacts in conversation.
- Run flutter test in example; add conflict test cases.

### Dependencies
- Add to pubspec.yaml: envied (^0.5.0) for env, mime (^1.0.0) for form, shorebird_code_push (^1.0.0) for OTA.
- CLI handles adding these in init.

### Potential Risks
- Route conflicts: CLI exits on build if detected.
- Form data: Ensure mime parses multipart correctly; test with files.
- SSG: Headless loadData may need mock backend.
- OTA: Shorebird requires setup; document compliance.

### Tools for Implementation
- Warp CLI/Claude Code Interpreter: Feed this plan.md, repomix-output.xml, and conversation artifacts.
- Test: flutter pub get, dart run dartvel_cli:doctor, flutter test.

