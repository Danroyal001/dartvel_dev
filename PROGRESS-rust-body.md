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

## Step 11 — Held-out corpus in progress
- Default evidence/documentation saved locally in `b5bc7011e`.
- Running `ELEMENT_CORPUS=tests/language:sdk/lib:pkg/front_end/lib:pkg/linter/lib:pkg/kernel/lib` with the same Dart/heavy.sh/release oracle command and a 2400s outer limit; no selections removed. Upstream has produced 4.7 MiB of dumps after about 3 minutes; no comparison result yet.
- Next: diagnose any differences, then record slice measurements and safety evidence. All non-literal expression types, identifier elements, local/generic inference, invocations and flow remain unported.

## Step 12 — All requested held-out roots GREEN
- **146,712 expression rows, 5,730 files, 0 differences**, 548.06s with the hardened comparator. Roots: `tests/language`, `sdk/lib`, `pkg/front_end/lib`, `pkg/linter/lib`, `pkg/kernel/lib` together.
- Literal slice compatibility gate now passes fixture (43 rows/4 files), default (41,283/589) and held-out (146,712/5,730). This is only seven literal kinds, not full body-resolution parity.
- Next: Miri on oracle completeness tests and AOT-vs-Rust fixture-output measurements using the existing interleaved harness. Instruction counts blocked by perf policy. No invocation/generic/flow slice started yet.

## Step 13 — Comparator Miri GREEN
- `MIRIFLAGS=-Zmiri-disable-isolation CARGO_BUILD_JOBS=1 timeout 900 ~/heavy.sh ~/.cargo/bin/cargo +nightly miri test -p analyzer --test oracle_comparison -- --nocapture`: all **3 tests pass**, no undefined behavior reported (49.13s compile, 4.12s tests).
- This Miri run covers comparator completeness only, not all body-resolution paths. The analyzer library and body dump both forbid unsafe code; no new unsafe introduced.
- Next: compile the real upstream body dump to AOT and measure fixture-output pipelines with the existing interleaved harness; full resolver performance and inference are not certified by that measurement.
- Upstream AOT compilation printed the SDK workspace's `^3.15.0-0` auto-pub diagnostic under installed Dart 3.13.4, but continued into `gen_kernel_aot` using the explicit oracle package config. Waiting for its actual exit status; no SDK constraint or source changed.

## Step 14 — AOT measurement started
- Upstream AOT compilation succeeded despite the earlier auto-pub diagnostic: **78.73s**, compile peak RSS **574,136 KiB**; executable **17,931,560 bytes**. Rust release body dump **3,510,552 bytes** before further stripping.
- Running existing `pkg/_fe_analyzer_shared/rust/tool/measure.sh`, 11 interleaved processes per side, fixture corpus (43 output rows), through heavy.sh. Raw log: `experiments/dart_sdk/target/measure/body-literals/body-literals.runs`.
- Measurement scope is the complete selected-output pipelines, including SDK setup/parsing/output. Upstream resolves bodies beyond the selected literals; Rust does not. This favors Rust and cannot establish full resolver speed, memory, compile-time or cold-start parity.
- Next: inspect benchmark exit/output equivalence, save raw data and table, finalize review handoff. Broader brief remains incomplete.

## Step 15 — Literal output-pipeline measurements
- Existing interleaved harness completed 11 processes per side on a shared AMD EPYC host, Dart 3.13.4 AOT / rustc 1.99.0 release. Raw data retained at `experiments/dart_sdk/pkg/analyzer/rust/measurements/body-literals-2026-11-06.runs`.
- Both measured output directories match byte for byte (`diff -qr`, no differences). A separately stripped Rust executable also runs successfully and matches the upstream output.

| Fixture dump pipeline (43 rows / 4 files) | Dart AOT | Rust |
|---|---:|---:|
| Fastest process wall time | 822.97 ms | 170.86 ms |
| Median process wall time | 964.09 ms | 197.01 ms |
| Median peak RSS | 102,452 KiB | 33,656 KiB |
| Maximum peak RSS | 103,744 KiB | 33,716 KiB |
| Executable bytes before further stripping | 17,931,560 | 3,510,552 |
| Stripped Rust executable bytes | — | 2,936,992 |
| User-space instruction counts | blocked | blocked |
| Comparable clean compilation | not measured | not measured |

- Wall-time CV: Dart 46.1%, Rust 17.4%; shared-host noise is substantial. No in-process visitor timings or full-resolver cold-start result inferred. The upstream pipeline resolves more than the selected literals, so these numbers favor Rust and are not proof of the owner's full component performance bar.
- AOT compile observed separately: 78.73s / 574,136 KiB; earlier Rust 4m47s was an incremental multi-binary rebuild, so those compile times are not comparable. Stripped AOT size was not measured.
- Next: run comparator tests under normal Cargo, finish README and review handoff, commit all remaining task changes. Full body resolution/inference remains incomplete.

## Step 16 — Final checks and review handoff
- Standard Cargo release comparator tests: **3 passed**, 14.91s rebuild; Miri: **3 passed**. Targeted `rustfmt --check` and `git diff --check` pass.
- README records corpus counts, measurement scope, raw data, reproduction commands and safety/performance limitations. Raw AOT compile metadata is saved alongside the run log.
- Removed this worktree's generated `experiments/dart_sdk/target` (341 MiB) and temporary standalone executable. Forced cleanup was rejected by the tool; ordinary non-forced deletion succeeded. The oracle recreates package configuration/SDK layout and executables on the next run. Tracked measurement evidence remains.
- No push, PR, merge, publish, deploy or messages. Owner identity used for commits. No Python, production dependency or unsafe code added.

## Final report — PARTIAL, broader brief remains open
- Delivered: real upstream resolved-AST oracle (all expression types and identifier elements in upstream full mode), explicit literal subset on both sides, seven literal types backed by linked SDK classes, conditional-directive no-visit behavior, and a hardened missing-output comparator.
- Compatibility: fixture **43 rows / 4 files**, default **41,283 / 589**, held-out **146,712 / 5,730**; **0 differences in every comparison**. Held-out roots are exactly the five in the brief.
- Safety: library and dump forbid unsafe code; comparator native and Miri tests pass. Body-resolution Miri/coverage is not established.
- Measured fixture pipeline: Dart/Rust fastest **822.97/170.86 ms**, median **964.09/197.01 ms**, median peak RSS **102,452/33,656 KiB**. Upstream resolves more than literals; this does not establish the complete component performance bar. Instructions blocked by `perf_event_paranoid=4`; comparable clean compilation, full-resolver cold start and stripped AOT size remain unmeasured.
- Local branch: `agent/rust-body`, based on `6d52539f1`. Oracle/implementation commits: `bc1e80f4a`, `dc2e3ff83`, `6a0d2016d`, `98541525a`; corpus evidence: `b5bc7011e`, `db0b97c1d`; final evidence/report in the last commit. Lead reviews and lands; do not merge or push from this task.
- **Still required to finish the brief:** simple expressions beyond literals, identifier binding and Rust resolved-element output, invocations, contextual integers, local/generic inference, flow analysis, their failing-first oracle slices and all-root comparisons, and complete safety/performance measurements. Rust deliberately refuses full dump mode while these are absent. Do not mark the queue item done or advertise body-resolution parity.
- **Next action:** add the next simple-expression oracle selection/fixture, observe semantic RED, then port the corresponding upstream visitors before invocation/inference machinery. Keep existing literal selection and all-root comparisons intact.
