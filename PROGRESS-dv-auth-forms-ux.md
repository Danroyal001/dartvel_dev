# Auth and forms UX progress

## Step 1 — context and audit
Done: read ~/AGENTS.md, repository AGENTS.md/CLAUDE.md, brief, server STATUS and recent lead conversation. Clean branch: agent/dv-auth-forms-ux. Latest user instruction overrides brief PR/push rules: commit locally and stop; no push, PR, merge, publication, deployment or messages.
Findings: existing form scope supports next/done and password manager tests already exercise Enter. Sign-in has an internal duplicate-request guard but no visible/disabled pending button or live error region. Sign-up has no return navigation or sign-in link. DVForm callback is void and cannot await generated model.save(), so asynchronous failures escape and edits clear before save succeeds. Auth layouts use narrow columns and hard-coded button colors.
Tests: not run yet.
Next: failing behavioral tests, shared pending save handling, responsive themed auth frame and typed account links/config, shared renderer audit, docs and required sample/browser verification.
Blockers: none identified. Password reset availability still to be checked.

## Step 2 — regression tests (red)
Done: four new widget regressions fail for the intended missing behaviors: live/inline auth error, reachable sign-up, wide brand panel, and asynchronous form pending state. Log: /tmp/dv-auth-red-package.log. Initial root-level test invocation used the wrong package config; corrected to package-local invocation after pub resolution. Async form regression uses an async callback to demonstrate the existing void API dropping its future.
Implementation in progress: await model saves, retain edits until accepted, block repeated submit/reset, avoid raw backend errors.
Next: themed responsive auth frame, branding/config and typed links, then green tests.
Blockers: shared SSR semantics currently has no interactive form contract; password recovery/reset endpoint does not exist (security-page password change requires a signed-in account).

## Step 3 — runtime implementation
Done (verification pending): DVForm callback accepts FutureOr<void>, awaits save, disables repeat/reset while pending, retains edits after refusal and emits safe wording. Added DVAuthAppearance/DVAuthFrame: themed typography/colors, 720px brand-panel breakpoint, compact scrollable watch layout, optional icon/hero/custom panel builder. Sign-in/signup now have real themed pending buttons, live errors and cross-navigation; signup accepts from. Existing autofill and next/done retained.
Tests: four red regressions confirmed; green runtime suite queued in ~/heavy.sh (/tmp/dv-auth-green.log). Generator regression added for custom account routes and signup return query, awaiting run (/tmp/dv-auth-generator-red.log).
Next: generator wiring/config, green checks, docs/sample/web-server screenshots.
Blockers: no password-reset endpoint; SSR interactive forms remain unresolved. First full-file dart format caused unrelated whitespace churn; reduced changes to touched class regions before proceeding.

## Step 4 — configuration and navigation
Done: generator tests first failed on missing signup from query and missing Harvest identity. Generator now installs typed configured auth destinations and branding (pwa name/icon; auth tagline/heroImage/brandPanelColor), rejecting malformed panel colors. Runtime custom appearance wins over generated defaults. Added a deterministic auth pending/double-Enter test. Second-factor/account pages now share the responsive frame. Added docs/auth-forms-ux.md and README link.
Tests: initial green run had a const Semantics compile error, corrected; the other 43 existing form/password-manager tests passed. Corrected green rerun in progress (/tmp/dv-auth-green2.log). Generator green run queued (/tmp/dv-auth-generator-green.log).
Next: complete touched/full checks, site/spec docs, sample build and browser evidence.
Blockers: confirmed shared renderer emits a clipped fallback document and has no interactive form-action contract. No handwritten alternative auth HTML added; the brief's pre-Flutter form submission and theme parity remain unimplemented. Password reset absent.

## Step 5 — touched runtime checks pass
Done: 48/48 widget tests pass (auth_forms_ux, auth_password_manager, form_accessibility, form_edit), including pending/double Enter, announced inline auth error, signup navigation, 200px overflow, and async save failure retaining input. Log /tmp/dv-auth-green2.log. Added site auth docs and spec text, explicitly identifying the undelivered SSR contract. Password keyboard disables correction/suggestions; signup now associates errors with email/password.
Next: final full Flutter suite and package analysis (queued/started), generator checks, create/build sample, browser screenshots.
Tests queued: /tmp/dv-auth-flutter-full.log, /tmp/dv-auth-generator-green.log; analysis /tmp/dv-auth-flutter-analyze-final.log. Sample creation queued /tmp/dv-auth-create.log.
Blockers: shared renderer limitation remains. No production-ready claim.

## Step 6 — analysis/spec checks
Done: touched CLI analysis clean; full dartvel_flutter analysis has zero errors, one existing unused-variable warning in three_pane_test and 32 infos (mostly existing ordering/style notices). Spec checker passes: 115 sections, 105 labelled, evidence present. git diff --check clean. Disabled configured account pages no longer get an in-place fallback navigation link.
Next: queued generator/full suite/sample commands; verify actual screenshots. Current shared heavy queue is congested by unrelated full CLI/container jobs; no other agent processes altered.
Logs: /tmp/dv-auth-cli-analyze.log, /tmp/dv-auth-flutter-analyze-final.log, /tmp/dv-auth-spec-check.log.

## Step 7 — full-suite regression triage
Full Flutter suite is running and exposed account-page controls below the fold and legacy error-widget assumptions. Kept the scrollable layout; account-page tests now scroll controls into view before tapping, which exercises the actual action instead of an offscreen coordinate. Preserved DVText error summaries for compatibility, kept inline field errors (field-prefixed to distinguish location), and aligned the session-client assertion with the brief's plain "Wrong email or password" wording. No privacy/authentication assertions removed. Original sign-in heading retained.
Next: impacted six-file verification (/tmp/dv-auth-compat-green.log, queued), finish full suites and sample/browser evidence.

## Step 8 — compatibility expectations and account pending
Done: account request buttons now pass their existing busy state to the themed pending/disabled control. The full suite also exposed an obsolete test explicitly requiring the old hard-coded dark button and forbidding FilledButton; replaced those styling assertions with the rendered app-theme primary fill while retaining its real sign-in behavior. Added runtime signup return/query verification to complement generator wiring tests.
Tests: first full Flutter run still running; failures from pre-fix snapshots recorded in /tmp/dv-auth-flutter-full.log, plus a Studio palette-drag failure outside this change. Final impacted suite queued. Sample/generator waiting for heavy slot.
Next: finish runs; rerun updated full suite after these fixes; sample browser evidence.

## Step 9 — consolidate final verification
First full Flutter run finished: 2,577 passed, 24 skipped, 10 failed. Nine failures correspond to auth/layout expectations fixed since its compilation snapshot; one Studio palette-drag failure is outside touched code. Cancelled only my still-queued commands by PID and replaced them with one sequential heavy job (no other agent processes touched), to avoid queue starvation.
Pipeline: /tmp/dv_auth_pipeline.dart; log /tmp/dv-auth-pipeline.log; results /tmp/dv-auth-pipeline-results.json. Order: final generator tests → seven impacted Flutter files → dartvel create sample → non-default Harvest theme web-server build → 12 screenshots in docs/screens/auth → final full Flutter and CLI suites. Each stage writes /tmp/dv-auth-<stage>.log. Browser script /tmp/dv_auth_capture.dart launches its own headless Chrome, never port 9333. Account error summaries now consistently use live regions.
Next: inspect stage results and each screenshot, add real-browser pending/Enter evidence, fix any task regressions, commit only on agent/dv-auth-forms-ux.
Blockers: interactive SSR/form handoff remains unimplemented; sample pipeline has not yet acquired a heavy slot.

## Step 10 — final targeted verification passes
Done: generator/model-form tests all pass (/tmp/dv-auth-generator-green-final.log); seven affected Flutter test files all pass (/tmp/dv-auth-compat-green-final.log), including new signup return/query navigation. Pipeline acquired its heavy slot and is creating the sample.
Next: sample build/capture, real-browser Enter/pending check, final full suites. Browser test script /tmp/dv_auth_browser_check.dart prepared with controlled rejected request, disabled pending semantics, repeat Enter guard and provider-error redaction. Existing running Dart pipeline compiled before this script was added; browser check must be run separately while sample server is available or restarted locally.
