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

## Step 4: generated application entry (in progress)
Tests first: three generator regression tests failed before changes: missing pure-app root/entry file, unwired boot hooks/host root, and no refusal when a host root drops its router.
Implementation in progress: preserved valid entry declarations from 4a8f0bcc, excluded its NEW_SPEC rewrite and invalid placeholder facade/run bodies. Added annotation/context types, generated DV namespace forwarding existing subsystems, default themed router root, stable boot ordering, optional host-root lowering and router diagnostic. Scaffold main becomes DV.run() alone after its barrel import.
Next: compile generator/runtime and smoke app; fix any failures, migrate examples/docs and browser-check web-server output.
Blockers: heavy-test slots currently contended; queued focused generator and Flutter dependency resolution through the required heavy wrapper. No unsupported shipping claims.
Entry verification update: generator + functional widget class/block-body suites pass 22/22 after correcting an export directive accidentally placed below declarations in the core barrel. Basic app now has only DV.run() in main and its page is named index.dart; coffee startup/root customization moved to boot.dart, preserving its existing Flutter host theme. Site docs now teach boot hooks and middleware fields. Flutter tests remain queued for dependency resolution because available memory repeatedly fell below the heavy wrapper's 3 GB threshold.
Typed backend inspection: generated-model returns currently demand a mapper, and POST typed arguments are wrapped as multipart fields (a data model can become "Instance of ..."). Added a regression fixture before changing that code; test queued through heavy wrapper. Planned fix: generated parser decoding for model/nullable/list/stream results and JSON encoding/decoding for generated-model arguments, retaining legacy custom-type mapper compatibility.

- LEAD NOTE (owner): the live site uses the default Flutter logo as favicon. Use the Dartvel Authenticator icon for favicon.png, apple-touch/manifest icons and the extension icons. Also file a framework fix (dv-conventions-framework) so `dartvel create`/build never ships Flutter's default favicon/icons: generate them from the app icon, and make `doctor --conventions` flag a default Flutter favicon.
