# Rust body resolution progress

## Step 1 — Context and worktree (2026-11-06)
- Read server rules, repository AGENTS.md/CLAUDE.md, task brief, queue Rust gate, handoff latest messages, analyzer README and stack proposal.
- Worktree initially pointed at main (no experiments). Created `rust/body-resolution` from local `feat/rust-stack-experiments`, as required by brief; no existing tracked edits.
- Scope: body resolution/inference in slices, oracle first, no compatibility or performance claim without measurements.
- Next: inspect existing element oracle and AST/type APIs; introduce resolved-body oracle for literals first and observe missing-port failure.
- Tests: not run yet. Blockers: none established.
- Delivery: local commits only per latest user instruction; no push, PR, merge, deployment or messages.

## Step 2 — Oracle first
- Added upstream resolved-unit dump: full mode emits V1 expression types and identifier elements; first slice explicitly selects context-independent literals (bool, double, Null, strings, symbols). Integer literals remain in the later downward-inference slice.
- Added differential harness and a literal fixture; Rust driver intentionally emits empty dumps to establish RED before implementation.
- External worktree setup moved the task branch back to `agent/rust-body` at the same required experiment base (reflog confirms); continuing on that task branch.
- Next: run fixture comparison, then implement literal typing only after observing the expected mismatch.
- Fixture also covers directives, part units, annotations/defaults, nested interpolation, adjacency, raw strings, collection elements and unreachable code. These expose literals which an all-nodes walk must leave unresolved.
- Shared element-oracle setup/comparison code extracted without semantic changes for reuse by the body oracle. The first build is still queued behind other server builds.
- The build obtained a heavy slot and is compiling the analyzer in release mode. Added an explicit nonempty-expression guard so an accidentally empty upstream traversal cannot falsely certify parity.
- First execution reached the new oracle but failed to compile: Dart did not promote the AST implementation parameter to the public Expression/Identifier interfaces. Added explicit casts; this is a harness setup failure, not the required semantic RED.
- Corrected oracle rerun obtained a slot at ~14:03 UTC. Oracle also accepts `--packages` explicitly so an AOT build can analyze against the identical package configuration for later measurements.

## Step 3 — Semantic RED established
- Command: from experiments/dart_sdk, `DART=/home/sigmadev/snap/flutter/common/flutter/bin/cache/dart-sdk/bin/dart ELEMENT_CORPUS=pkg/analyzer/rust/tests/body_corpus timeout 600 ~/heavy.sh ~/.cargo/bin/cargo test --release -p analyzer --test body_oracle -- --nocapture`.
- Result: FAILED for the intended reason: 37 upstream expression rows, 3 files, 3 differences against missing Rust rows. Directive URI literals are resolved as String too (not null).
- Next: implement type-provider core types and seven literal visitors, retain the same oracle/selection, rerun fixture then default and held-out roots.

## Step 4 — First literal implementation
- Added a narrow TypeProviderImpl using linked dart:core classes and existing TypeImpl interface types; TypeAnalyzer records the seven literal types beside the AST.
- Rust dump traverses the V1 view for comparison with upstream; provider links real SDK types, and repeated root labels are disambiguated like existing oracles.
- All other body visitors, flow effects, diagnostics and integer context inference remain unimplemented; full Rust dumping explicitly refuses unsupported mode.
- Next: release fixture comparison, then diagnose any default/held-out differences before claiming slice parity.

## Step 5 — Fixture GREEN
- Same literal comparison now passes: 37 expression rows across 3 files, 0 differences; release test completed in 69.58s (upstream JIT plus SDK resolution included).
- No oracle selection/assertion weakened after RED. Added no unsafe code.
- Instruction-counter prerequisite checked: `/proc/sys/kernel/perf_event_paranoid` is 4, so perf-based counts are blocked without changing server policy.
- Next: default corpus, followed by the five held-out roots; do not advance to another resolution slice yet.
- Saved oracle-first checkpoint `bc1e80f4a` and fixture-green implementation `dc2e3ff83` locally (owner identity, no attribution trailers). No push.
- Default run is rebuilding after source formatting timestamps changed during the prior compile; no semantic edits since fixture GREEN. Sources are now stable.

## Step 6 — Default corpus RED: conditional directives
- Default comparison completed in 229.07s: 589 files, 41,283 expression rows, **2 differences**.
- Both are alternate URIs inside conditional import/export Configuration nodes: upstream type `-`, Rust incorrectly String. Upstream `TypeAnalyzer.visitConfiguration` explicitly does not visit children (line 2594).
- Added fixture covering both conditional export and import, including an equality-value string. Implementing the same no-visit rule while keeping untyped literals visible in the dump; comparison/selection unchanged.

## Step 7 — Resumed verification (2026-11-06)
- Re-read binding home/project rules, brief, queue gate, proposal, analyzer README and recent lead conversation. Preserved existing edits on `agent/rust-body`; no reset or branch replacement.
- Conditional-directive fix and regression fixture are present from the preceding session. Running the unchanged real-upstream fixture oracle through `~/heavy.sh` before committing them.
- Next: default and all five held-out roots; investigate every difference before advancing. Full resolution/inference and performance gate remain incomplete.
- Delivery remains local commits only, as explicitly requested; no push, merge, publishing, deployment or messages.
- While reviewing the oracle, found a silent comparison bug: a missing Rust dump is replaced with empty bytes, so a missing empty dump is accepted. Added a focused regression test (not run yet); will observe RED before fixing. No oracle selection is narrowed.

## Step 8 — Oracle completeness regression RED
- Built standalone `tests/oracle_comparison.rs` through heavy.sh and executed it: 2 passed, missing-empty-output case FAILED for the intended reason (`differences` was 0 instead of 1).
- Fixed comparison to require the actual file to exist before comparing bytes, preserving missing expected dumps as evidence. Read failures now fail rather than silently becoming empty output.
- Analyzer release build finished in 4m47s; conditional-directive fixture comparison is now running.
- Next: rerun comparator tests, finish fixture/default/held-out validation; do not claim whole-body parity.
- Comparator regression GREEN: all 3 tests pass after the fix; `git diff --check` clean. Formatting applied to changed Rust files.

## Step 9 — Conditional directives GREEN
- Unchanged literal oracle: **43 expression rows, 4 files, 0 differences**, 70.39s after release compilation. Includes the new conditional import/export fixture; the original default-corpus RED was 2 differences.
- Comparator hardening committed locally as `6a0d2016d`; no remote action.
- Next: default corpus with hardened comparator, then held-out roots; full inference/resolution and measurements still pending.
- Conditional-directive fix committed locally as `98541525a`. Hardened default oracle started; rebuild completed in 20.85s, upstream resolution in progress. No uncommitted implementation changes.

## Step 10 — Default corpus GREEN
- Hardened body literal oracle passes: **41,283 expression rows, 589 files, 0 differences**, 265.66s (plus 20.85s release rebuild), using Dart 3.13.4 and the SDK checkout's libraries/packages.
- Command from `experiments/dart_sdk`: `DART=/home/sigmadev/snap/flutter/common/flutter/bin/cache/dart-sdk/bin/dart CARGO_BUILD_JOBS=1 timeout 1200 ~/heavy.sh ~/.cargo/bin/cargo test --release -p analyzer --test body_oracle -- --nocapture`.
- Next: all requested held-out roots in one comparison; no new resolution slice started before that gate. `perf_event_paranoid=4` still blocks instruction counts.
