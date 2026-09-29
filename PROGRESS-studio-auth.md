# Studio authentication test task

## Step 1 — context read
- Read server handbook/status, repository AGENTS.md and CLAUDE.md, task brief, and latest lead conversation.
- Working on existing `feat/studio-pages-models`; baseline c1d21641. Existing untracked site database files are unrelated and will remain untouched.
- Scope: establish intended login/shell versus protected data behavior, reproduce regressions, strengthen endpoint coverage, commit locally only.
- Tests: not yet run. Blockers: none.
- Next: inspect sign-in history and server authorization, then reproduce the two failures through heavy.sh.

## Step 2 — behavior and history established
- adf5b230 introduced the old hidden-dashboard expectations on September 16.
- 52430270 intentionally changed page requests to 302 -> Studio login; 616fdd0b made login the public Flutter shell and exposed only auth/access and app assets. Project graph and API remain behind Studio.access.
- Both binary HTTP helpers follow redirects by default, disguising the 302 as the login shell's 200. No production change indicated.
- Baseline focused tests running (logs /tmp/studio-auth-baseline-{server,web}.log).
- Next: disable automatic redirects in helpers, assert Location/no-store/empty redirect bodies, preserve protected-data 404 checks and add complete API route/method coverage.
- Blockers: none.

## Step 3 — assertions updated, coverage added
- Reproduced original server-binary failure (34 seconds): automatic redirect ended at public shell, as suspected.
- Helpers now retain initial response and Location/cache headers. Tests require 302, exact login return path, no-store, empty body for ungranted pages; explicitly verify public login assets.
- Added binary test covering every current Studio data route family and supported read/write methods, signed out and forged session, with valid CSRF headers on writes. All require 404 and no redirect. Existing granted-session positive checks retained.
- Tests in progress: original full web-server baseline; revised server dashboard group.
- No production changes. Next: run revised web-server suite and inspect assertions for false positives. Blockers: none.

## Step 4 — review and verification underway
- Endpoint matrix checked against DVStudioApi's dispatch and nested handlers: 16 paths, including all mutation endpoints. HEAD is also denied without a grant.
- Added unknown-route response comparisons (body, type, cache) so a 404 containing project data cannot pass. Granted model/record/graph reads remain positive controls in the existing integration test.
- These are test corrections for the intentional 0.9.1 contract, not a relaxation of data authorization. No project content is present in the fixture shell title.
- `git diff --check` passes. Avoided unrelated whole-file formatting churn.
- Two commands initially used root-relative test paths incorrectly; corrected package-directory runs queued through heavy.sh. No code issue involved.
- Next: await full binary build/test results and targeted analysis, then commit locally. Blockers: none; heavy.sh shares two build slots with other work.

## Step 5 — backend fixture distinction confirmed
- Revised server group: open dashboard passed; guarded graph returned 200, failing the newly added unconditional 404 assertion.
- This fixture builds a backend with a static site shell, not the web-server renderer: its unknown routes also return that public site shell (the original test explicitly compared against unknown routes). Corrected this assertion to retain that contract and forbid Studio content. The actual web-server endpoint matrix still strictly requires 404.
- Targeted Dart analysis passes with no issues. Web-server baseline/revised runs still building.
- Next: rerun server group and await web-server results. No production changes or blockers.

## Step 6 — both baselines reproduced
- Original full web-server test failed exactly as brief: expected 404, got 200 (4m41s). This confirms both original failures on the untouched loaded test snapshots.
- Targeted analysis: `dart analyze test/server_binary_build_test.dart test/web_server_binary_test.dart` from packages/dartvel_cli: no issues.
- Revised backend dashboard group rerunning; revised full web-server file building (includes persistence test, full protected endpoint matrix, and granted-access positive controls).
- Next: record final results and commit. Blockers: none.

## Step 7 — backend verification passed
- Final server-binary dashboard group: 2/2 passed in 52 seconds (/tmp/studio-auth-final-server.log).
- Confirms open development mount, release redirects, forged-session denial, graph response indistinguishable from unknown path, and public login shell.
- `git diff --check`: clean.
- Next: finish full web-server verification, update shared status and final report, commit task files only. Blockers: none.

## Step 8 — final verification passed
- Full `web_server_binary_test.dart`: 3/3 passed in 4m47s (/tmp/studio-auth-fixed-web.log). Tests include persistence/restart, protected endpoint matrix, and denied/granted Studio access.
- Data matrix covers 16 paths, signed out and forged token, read/HEAD/write methods with valid CSRF headers; requires 404, no redirect, and the same body/type/cache as an unknown route. Granted model, record and graph reads succeed as positive controls, so blanket denial cannot satisfy the suite.
- Backend dashboard group: 2/2 passed; targeted analysis: no issues; diff whitespace check: clean.
- Next: local commit, then stop for lead review. Blockers: none.

## Final report
The two failures were stale tests of pre-0.9.1 behavior. HTTP clients followed the intended 302 to the public Flutter login shell and reported its 200. History (adf5b230, 52430270, 616fdd0b) and current DVAdminServer agree: ungranted page requests redirect to Studio login; app shell/assets and the minimal auth/access endpoints are public; project graph and data require Studio.access.

Updated the tests to observe the initial redirect, exact return path, no-store and empty body; retained granted-access checks and strengthened protected-data coverage. No production changes. The backend-only fixture retains its documented public SPA fallback for unknown routes, whereas the real web-server integration strictly verifies 404 for protected data.

Verification: both original failures reproduced; revised backend group 2/2 and full web-server suite 3/3 pass; targeted analysis and diff check pass. Work is committed locally on feat/studio-pages-models. No push, merge, release, deployment or messages. Existing untracked site database files are untouched. Lead review/landing is the only remaining step.
