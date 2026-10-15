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
