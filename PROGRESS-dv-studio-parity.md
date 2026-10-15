# Studio parity — working log

Branch `agent/dv-studio-parity`. Goal: Studio at parity with the WordPress admin
and the Webflow dashboard, on the application's one render path, every screen
and object at its own URL, in the application's theme, generic for every
project. The verdicts live in `docs/studio/PARITY.md`; this log records what was
done, in order, and what was measured.

## 2026-10-15 — resumed and re-audited

The previous log claimed all nine slices done and verified. Re-checked against
the code and a fresh test run (Flutter 3.47.7 / Dart 3.13.5):

- `dartvel_core` Studio and admin tests: 209 passed.
- `dartvel_flutter` Studio tests: 556 passed, 41 failed, 1 skipped. The earlier
  log attributed failures to SQLite in the container; the causes were in the
  tests and the code (autosave timers left pending, a preview banner that
  overflows, a publish SnackBar with no Scaffold, the Team section replacing the
  access section the server tests drive).

Defects found that the earlier log reported as done:

- Autosave published live: the debounced save went to `PUT api/pages`, which
  replaces the served page. There were no drafts, revisions or scheduling in
  server-served Studio; `DVStudioContent` was only constructed in tests.
- Role permissions were never checked on any write.
- Media: no size or type limit, SVG served inline from the Studio origin,
  any storage key readable, bytes kept in memory only, a text box for upload.
- Per-page SEO was stored and never served.
- The public form endpoint sat behind the Studio grant, so no visitor reached it.
- Menus and settings had no effect outside Studio; every project was seeded
  with Dartvel's own social links, sample menus and sample forms.

Removed agent working notes that named private host paths, a credentials file
and a client project from the repository.

## Page drafts, revisions, schedules

Autosave writes drafts through `draftSaver`; the server keeps versions in the
content workflow (SQL databases; a document database publishes directly and
says so). Core Studio tests 328 passed; Flutter Studio tests 588 passed,
18 failed -- all 18 were in the original 41 apart from two this change caused
and fixed (older page-list shape).

## Roles enforced

`dvStudioPermissionFor` names the permission each request needs and the
server checks it against the caller's role. Core Studio tests 335 passed.

## Media, database-only stores, SEO, records, addresses, forms, settings

- Media: closed type list (no SVG/HTML), 25 MB cap, `media/` scope, `nosniff`
  and `sandbox`; files on disk beside the database, served at
  `/_dartvel/media/<name>`; uploads through the browser's file chooser.
- Menus, forms, submissions, settings: the database is the only store; a
  refused write is a 500, no database a 503; no project seeds.
- The 41 failing Flutter Studio tests fixed on the merits (code and tests),
  each change explained in the test.
- Per-page SEO served in the head, JSON-LD and sitemap (binary and `dartvel dev`).
- Record history and revert for models with `history:`; record list filter,
  debounce, bulk-delete reporting.
- Team and Settings tabs and the form inbox have their own addresses.
- Forms answered by visitors at `/_dartvel/forms/<id>`, bounded and rate
  limited per process; drawn on published pages.
- Settings applied: maintenance mode (503) and default description, image and
  site title; default SEO title, favicon, timezone, date format, social links
  still unread.
- `docs/studio/PARITY.md` now measures Studio against the WordPress admin and
  the Webflow dashboard, and stale rows are corrected.

## Verification (2026-10-15)

Compared against the seed commit `c65cc32` in a separate worktree, same machine:

- `dartvel_flutter` full suite: 2837 passed, 30 skipped, 1 failed
  (`web_bindings_test.dart`), which fails identically at the seed.
- `dartvel_core` full suite under `flutter test`: 51 failures, the same 51 at
  the seed (shell, subprocess, native library, dart2js and lock tests that need
  what this container does not have).
- `dartvel_shelf`: 12 failures, the same 12 at the seed (socket and streaming).
- `dartvel_cli`: server_binary_build, server_compile, process_roles_backend and
  server_options pass; the web-server binary test cannot complete here, as at
  the seed: its build's
  headless semantics capture reads 0 of 5 routes.

Not done: a browser check of Studio on a web-server build; the convention pass
over the example apps (`main.dart` with only `DV.run()`, real icons); the repo
version (0.12.1) is behind pub.dev (0.12.2).
