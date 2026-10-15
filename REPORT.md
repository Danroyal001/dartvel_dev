# agent/dv-conventions-framework — cloud session report

Base: origin/agent/dv-conventions-framework at 4eb5d7f (the five earlier
commits). This session adds four commits on top, authored by SigmaDev.
GitHub rejected the push (403: the Claude GitHub App has no write access to
the repository), so nothing here is on GitHub yet and no PR was opened.

## Finished (test-first, each new test seen failing before its fix)

1. **Make the generated DV entry compile and forward typed members** (82b0dc1)
   - The branch's `application.g.dart` imported `launch.g.dart`, which nothing
     generates, so every pure app's `void main() => DV.run();` failed to
     compile. `negotiateDartvelLaunch` lives in `dartvel_runtime.dart`.
   - The generated `DV` forwarded the runtime `DV` as untyped
     `static get X => runtime.DV.X`, which made `DV.Auth`, `DV.global<T>` and
     `DV.transaction` dynamic calls. Every member is now forwarded with its
     declared type. Core-only types are imported with a `core.` prefix.
   - `DV.container` (Riverpod's) is deliberately not forwarded: it is
     framework-internal.
   - Tests in `packages/dartvel_cli/test/application_entry_generation_test.dart`:
     - Every relative import in the entry must be a file that was generated.
     - The test reads the runtime `class DV` and fails on any public static
       the facade misses.
2. **Hide the runtime DV where generated code inlines application source** (3485ce9)
   - `widgets.g.dart` and the page files imported `dartvel_flutter` whole, as
     well as the source file's barrel. Any widget using `DV` failed with
     "'DV' is imported from both". The site's tests failed on this.
3. **Start our own apps with DV.run() and middleware fields** (df87a02)
   - `class_widgets_app` and `docs_samples` are pure: main is `DV.run()`, and
     setup is a `@DVBoot` function.
   - `sites/dartvel_site` keeps an `@DVAppRoot` in `lib/boot.dart`, because it
     needs a touch scroll behaviour; its theme moved to `lib/theme.dart`.
   - The four functions on `@DVUseMiddleware` now use `middleware:` on
     `@DVBackendFunction`. The generated chains were checked and are
     unchanged.
   - The docs samples were regenerated.
4. **Scaffold typed backend functions and a plain index page** (4bf0a42)
   - `dartvel create`: `health` returns a String; `contact` takes typed fields
     and returns a String. No Map, no `jsonEncode`, no `.jsonl` write.
   - The index page no longer calls a public helper.

## Verified

- `packages/dartvel_cli`: these test files pass:
  - `application_entry_generation_test.dart` (5 tests)
  - `project_templates_test.dart`
  - `scaffold_backend_serves_test.dart`
- `examples/basic_app`, `examples/class_widgets_app`, `examples/docs_samples`
  and `sites/dartvel_site` were generated with `dartvel routes`. Analysis:
  - no errors in any of them;
  - `class_widgets_app` reports no issues at all;
  - the other three reported only the `@DVUseMiddleware` deprecation info,
    which commit 3 removes. They were not re-analyzed after that.
- `class_widgets_app` tests pass.
- Site tests pass (36): widget, typeface, scrollbar, home_scroll,
  rendered_type, site_search_ui and header_phone.
- The full `docs_samples` suite was started after the migration, but its pass
  or fail result was not captured.
- Used Flutter 3.47.7 / Dart 3.13.5.

## Partial / not done

- The scaffold's new index page has not been compiled in a generated
  project.
- Requirement 4, `doctor --conventions`, is not finished:
  - The `missingRootPage` rule only checks `lib/pages/index.dart`. It must
    also accept `index.page.dart` and route groups such as
    `(tabs)/index.page.dart`; otherwise it flags examples/dartvel_example.
  - `toJson` is flagged anywhere in a file that has `@DVBackendFunction`,
    not only in the function's signature.
  - `DV.run(variable)` is not flagged.
  - Private host paths only catch `/home/...`, not `/Users/...` or
    `C:\Users\...`.
  - There is no check for the default Flutter favicon or icons.
- Requirement 5 is not started: the `/sitemap` server-rendered page in the
  app's theme, sharing one source with `sitemap.xsl`.
- Requirement 6 is not started: `/llms.txt` and `llms-full.txt`.
- Docs for the new entry and middleware are not updated beyond what the
  branch already had.
- The site search still returns hand-built JSON (`search.get.dart`).
  Typing it means reworking the site's search client.
- The backend generator does not expose `DV` inside an inlined backend
  function body (seen in the scaffold test). This needs its own fix.
- The full-suite baseline is unreliable: the comparison copy resolved
  against the live tree. Failing test files are being re-run on a clean
  seed worktree. The suspected pre-existing failures are mostly
  environment-bound: shelf socket tests, crash/raw_path/web_server builds
  and core diagnostics. That is unconfirmed.

## How to test

```
cd packages/dartvel_cli && dart pub get && dart test test/application_entry_generation_test.dart test/project_templates_test.dart test/scaffold_backend_serves_test.dart
cd examples/basic_app && flutter pub get && dart run dartvel_cli:dartvel routes && flutter analyze lib
cd sites/dartvel_site && flutter pub get && dart run dartvel_cli:dartvel routes && flutter test
```

Native `.so` files and `dartvel_shelf/lib/src/generated/bindings.dart` are
rewritten by build hooks during tests. Revert them before committing.

## PR

**Title:** Conventions framework: DV.run() entry, middleware fields, typed backend, doctor --conventions

**Body:**
Builds on the conventions branch:
- `DV.run()` takes no widget. A pure app's `main.dart` is just `DV.run()`.
  `@DVAppRoot` is optional. Startup hooks are `@DVBoot`.
- Middleware is a `middleware:` field on `@DVPage` and `@DVBackendFunction`.
  `@DVUseMiddleware` stays as a deprecated alias with a lint.
- Backend functions are typed.
- `dartvel doctor --conventions` checks applications against the
  conventions.

This update makes the generated entry compile and forward typed members. It
also fixes the duplicate `DV` import in generated widgets, migrates our own
apps, and types the scaffold's backend functions.

Still to do before merge:
- the remaining doctor rules;
- the framework `/sitemap` page in the app's theme;
- generated `llms.txt` / `llms-full.txt`;
- docs.

Do not merge or release from this PR yet.
