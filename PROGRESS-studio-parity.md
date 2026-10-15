# PROGRESS: Studio parity (agent/dv-studio-parity) — PAUSED, back in queue

Paused 2026-10-14 by lead (shell cap). WIP commit only; nothing pushed to main, no PR, nothing deployed.

## Done
- Measured: live https://dartvel.dev/__studio rejects the stored login in
  ~/.config/dartvel-site-studio.txt (API answers 400 invalid_credentials; password untouched).
  Live login page shows only the splash until Flutter loads (SSR text is visually clipped:
  `.dv-fallback` is 1px/clip-path on screen) — framework-wide, also on public pages.
- WordPress 7.1.3 admin (sigmadev.digital) viewed read-only via a temporary session token,
  destroyed afterwards (visiting post 1's editor refreshed its normal _edit_lock meta).
  Screens: dashboard, posts, pages, media grid, users, settings, site health, comments, site editor.
- Webflow/WP feature facts with doc URLs gathered (16 rows); paste into PARITY.md from the
  lead's transcript or redo quickly (Webflow help pages 403 on direct fetch; search snippets used).
- Key findings for PARITY.md (not yet written into it):
  - Free/Pro boundary (dartvel_enterprise/docs/business-model.md): revision history, rollback,
    approval workflow, role-based permissions, audit trail, presence are PRO. So free Studio
    should NOT get revisions/roles; owner decides.
  - DVStudioContent (drafts/review/versions) is never constructed anywhere: on a web-server build
    there are no drafts, versions or scheduling; PARITY's "Version history and restore: Done" is
    wrong for the server build.
  - Records list: search exists; no sort, filter, bulk select/delete, paging (all records loaded).
  - DVStudioListRow is not keyboard-focusable (no Focus node).
  - Sign-in maps every non-200 (incl. 400/500) to "email and password do not match".
  - Sign-in form shows each label twice (label above + floating label).
- Home dashboard slice, server side DONE and green (15/15 new + 110 existing core admin tests):
  - packages/dartvel_core/lib/src/admin/studio_overview.dart (new): activity log
    (dartvel_studio_activity, last 50, no actor), health checks, glance counts, quick actions.
  - studio_api.dart: GET api/overview; changes noted on page/component/record/model/function/grant writes.
  - studio_document.dart: 'home' is the first screen and the mount; Home document
    (At a glance, Site health, Recent changes, Quick actions; record keys/values never printed).
  - admin_server.dart computes the overview only for Home. admin_server_test "mount is Home".
  - test: packages/dartvel_core/test/studio_home_test.dart.

## In progress (client) — half done, does not yet pass
- test written first: packages/dartvel_flutter/test/studio_home_test.dart (8 tests, all failing as expected).
- studio_screen.dart: added DVStudioNavigation (InheritedWidget); `_selected` now String? defaulting
  to the first section. STILL TO DO there: rail `selected:` (lines ~488, ~531) must compare against
  the drawn section (current.id) not `_selected`; wrap body in DVStudioNavigation(open: _select);
  order sections so an attached 'home' section comes first.

## Next
1. studio_server.dart: DVStudioClient.overview() -> core.DVStudioOverview; dvStudioServerSections
   gets a 'home' section first (icon DVStudioIcons.home) + optional `open` (default dvOpenUrl) for
   "View the site".
2. New studio_home.dart: DVStudioHomeSection (key 'dv-studio-home'): glance tiles as focusable
   buttons (Actions+Focus+Semantics like DVStudioControl, tooltip = label), health rows with
   dvStudioHealthWords, recent changes with relative time ("5 minutes ago") opening
   screen/object, quick actions (DVStudioControl), error state "Home could not be read" + "Try again".
   Export from dartvel_flutter.dart.
3. Run studio_* flutter tests (drift test must pass with 'home'), then site web-server build:
   PATH=$HOME/snap/flutter/common/flutter/bin:$PATH; cd sites/dartvel_site;
   ~/heavy.sh bash -c 'flutter pub get; dart run dartvel_cli:dartvel build web-server'.
   Run with DARTVEL_PORT + DARTVEL_DATA_DIR in scratch, sign up a disposable account
   (~/.cache/studio-completion-signup.mjs pattern), `dartvel admin grant`, own headless Chrome
   (puppeteer-core from ~/browser-agent/node_modules, never port 9333): Home at 1440/390,
   light/dark, Ctrl+F, Tab, a11y snapshot, Back/forward. Screens -> docs/screens/studio-parity/.
4. Update docs/studio/PARITY.md (WP/Webflow/Studio table with evidence), README, NEW_SPEC/spec-status,
   sites/dartvel_site/lib/pages/studio.dart. PR (no AI trailers), don't merge/deploy.
5. Later slices (free only): page SEO settings + site settings, media library, forms/submissions, menus.
- Parallel slice "content lists" was forked to branch agent/dv-studio-content-lists
  (~/wt/dv-studio-content-lists); told to stop and leave its own PROGRESS file.
