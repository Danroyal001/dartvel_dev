# Dartvel conventions framework progress

## Plan (14 October 2026)
- Read server/repository rules, brief, owner handoff, STATUS and QUEUE: done. No previous task progress file exists.
- Work on `agent/dv-conventions-framework`; current explicit task assignment is the scope. Do not merge, publish, deploy or message anyone. Latest user says commit on the branch and stop, so no push/PR.
- Inspect and reuse partial `dv-run-entry` code, excluding its speculative NEW_SPEC changes. Integrate conventions-check branch, then add failing regression tests for the brief's missing rules.
- Implement optional generated application root and boot hooks, middleware annotation fields and deprecated alias, and verify typed functional-widget/backend generation.
- Update scaffold, README/spec/site documentation and conventions CI guidance; run focused tests/build/browser checks where applicable.
- After each coherent step record changes, test evidence, next work and blockers; commit atomically. Finish with an honest final report and server STATUS entry.

## Step 1: inspection
Done: read all required context; clean worktree at e3bb1940. Existing partial commits: run entry 4a8f0bcc; conventions check fb3de77a. Proposal allows optional command-line arguments; owner requires optional @DVAppRoot and a generated pure-app default root.
Tests: not run yet.
Next: inspect existing branch tests and runtime/generator integration before writing missing regression tests.
Blockers: none established. QUEUE's older two-task cap lists other work; explicit current assignment authorizes this task. Release remains lead-only.

## Step 2: conventions checker
Done: reused fb3de77a as 31758549 (doctor --conventions, build warnings/--strict, original tests/docs). Added five regression tests for the brief and implemented missing Flutter builder/class, widget-entry, middleware alias, backend serialization, root page, script and private-documentation checks. Dart source is masked to ignore comments/literals; generated barrel directory excluded.
Tests: all five new tests failed before implementation for the expected omissions/false positives. Focused inherited + new suite running.
Next: finish checker verification and commit, then middleware annotation-field generation tests.
Blockers: none. Scanner is lexical, so backend serialization diagnosis covers annotated source files, and the root check checks file presence, not whether an arbitrary guard actually redirects.
Verification: inherited + brief conventions suite passes 20/20. No build or browser claims yet.

## Step 3: middleware annotation fields
Done: DVPage and DVBackendFunction now take ordered typed `middleware:` lists. Generator discovery, route generation and validation read them; @DVUseMiddleware remains with @Deprecated and a conventions diagnostic. Literal lists validate every element rather than silently dropping invalid expressions.
Tests: converted existing behavior fixtures to exercise fields while retaining alias suites; pre-change run failed 20 behavior tests (guards, ordering, limits, tracing/CSP, invalid keys). First implementation run passed 51/52; one copied fixture incorrectly put a backend field on a page and was corrected to the page annotation, preserving its policy-refusal assertion.
Next: rerun all field+alias suites, update docs and commit; application entry next.
Blockers: none. No status claims copied from the invalid run-entry skeleton.
Verification: middleware field + deprecated-alias suites pass 52/52. Spec/getting-started/changelog updated. Committing this coherent step locally (no push per latest user instruction).
