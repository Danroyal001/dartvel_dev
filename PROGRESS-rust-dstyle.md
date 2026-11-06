# dart_style Rust port progress

## Step 1 — context and base (2026-11-06)
- Read server rules, repository AGENTS.md/CLAUDE.md, task brief, queue Rust gates, proposal and latest lead handoff.
- Initial worktree was release 0.13.21 without experiments. Created `rust/dart-style` from local `feat/rust-stack-experiments` (6d52539f1).
- SDK DEPS pins dart_style to `76978d23bfb3d225c81ce3f119ab7055a2a57136`; third_party checkout is absent.
- System Dart is 3.13.4, not the required 3.13.3 oracle. Locating exact SDK before comparisons.
- No tests or measurements yet; nothing ported. Next: vendor exact pinned source, establish oracle and failing comparison, then piece/solver core.
- User's latest instruction overrides brief push rule: local commits only; no push, merge, publish, deployment or messages.

## Step 2 — pinned source and first backend oracle
- Downloaded upstream archive at the exact SDK DEPS revision, preserving upstream files/license.
- Branch was externally returned to `agent/rust-dstyle` at the same Rust base; continuing there with local commits.
- Added a dependency-free upstream Code tree oracle covering nested groups, empty-group newlines, blank lines, indentation, UTF-16 selection offsets, CRLF, and nested/unclosed format-off regions over 256 cases.
- Rust Code tree API is intentionally a stub for the first RED run; implementation follows only after observing the comparison failure.
- Exact Dart 3.13.3 archive download in progress. No compatibility or performance claim.
- Exact Dart 3.13.3 downloaded and version verified at `~/.cache/rust-dstyle/dart-sdk/bin/dart` (642 MiB extracted, outside repository).
- First RED cargo run queued through `~/heavy.sh`; both shared build slots occupied by other tasks. Waiting without bypassing the limiter.
- Source vendoring committed locally as `153a3d63e` (1,190 original upstream files plus provenance/ignore changes). No push.
- First oracle run failed because its generated selection markers were out of order (upstream rejected negative selectionLength). Fixed the fixture to put the final end marker after all text; no Rust implementation changed. Correct RED rerun queued.
- Added crate README documenting the limited scope and every remaining acceptance gate. Heavy slots remain occupied by other builds; tests have not been bypassed.

## Step 3 — backend output tree implementation
- Correct RED observed: `/tmp/rust-dstyle-red2.log` fails the upstream/Rust output equality assertion (real Dart 3.13.3; 260 rows). Stub produced empty text; upstream produced formatted text and relocated selections.
- Ported GroupCode output traversal, shared immutable subgroups, pending indentation/newlines, selection relocation, nested/unclosed format-off handling and compilation-unit trailing newline.
- Internally stores UTF-16 code units, with a raw UTF-16 build API so unpaired surrogates can be retained. `forbid(unsafe_code)`, no dependencies.
- Registered crate in the SDK's single Cargo workspace. Next: GREEN oracle, additional edge cases/debug traversal, then the remaining piece/solver core.
- Added seven focused native/Miri cases for raw unpaired surrogates, disabled slices inside a surrogate pair, UTF-16 offsets, EOF selections, cached group reuse, redundant enable markers and unclosed disabled regions. These address edge cases not fully represented by valid-Unicode formatter input.
- GREEN test still queued behind other tasks in `heavy.sh`; no pass claimed yet.
- GREEN: 260/260 upstream Code tree rows match (0 differences), `/tmp/rust-dstyle-green.log`.
- Full crate suite: 1 differential test + 7 focused tests passed, `/tmp/rust-dstyle-suite.log`.
- Nightly Miri: all 7 focused tests passed, `/tmp/rust-dstyle-miri.log`.
- `git diff --check` passed. No formatter corpus comparisons or benchmarks yet. Debug rendering and signed marker offsets remain to complete the Code layer.

## Step 4 — complete Code debug/signed-offset behavior
- Backend output-tree slice committed locally as `51ea1af4c`; no push.
- Added differential cases for negative relative selection markers and 128 debug/tree traversals, including raw unpaired surrogates and disabled regions (which debug rendering must still display).
- Debug methods intentionally empty and signed marker offsets intentionally clamped for the RED run. Next: observe real comparison failures, then port these behaviors.
- Debug oracle RED confirmed in `/tmp/rust-dstyle-debug-red.log` (empty Rust traversals vs real upstream trees). Implemented both debug traversals without filtering disabled text or losing raw UTF-16.
- Signed output-offset RED run queued separately (`/tmp/rust-dstyle-offset-red.log`); the output builder still deliberately mishandles negative offsets until this failure is observed. Added a disabled-region case where the intermediate relative offset is negative but the final absolute position is valid.
- Updated server STATUS.md with scoped active-task status and the canonical handoff path.
- Signed-offset RED observed: `/tmp/rust-dstyle-offset-red.log`, native tests 8 pass / 2 fail, plus output differential failure. Backward marker was clamped and disabled-region subtraction incorrectly rejected a valid negative intermediate value.
- Replaced selection arithmetic with signed wide intermediates, converting only the final position to an index. Same oracle/test expectations retained.
- Full crate GREEN + Miri rerun queued/running via heavy.sh; results pending.
- Resumed task: reread server/project rules, brief, lead handoff, queue gates, proposal and crate READMEs. Preserved inherited uncommitted work on `agent/rust-dstyle`.
- Confirmed completed logs: `/tmp/rust-dstyle-debug-green.log` has both differential tests and 10 native tests passing; `/tmp/rust-dstyle-debug-miri.log` has all 10 focused tests passing under Miri. Debug comparison covers 128 trees; output comparison retains 260 rows. Zero differences in these scoped comparisons.
- `git diff --check` passes. Next: piece state/shape primitives, followed by the rest of the piece/solver implementation. Full formatter and performance gates remain incomplete.

## Step 5 — piece State/Shape primitives
- Committed debug/signed-offset slice locally as `097122b8d`.
- Added real-upstream oracle for all 16 shape merges, allowed-shape sets and 20 states/400 pair comparisons. Includes equal-valued states with distinct identity, const canonicalization, negative values/costs and duplicate values with different costs.
- Rust ordering, canonicalization and shape merging are intentional stubs for RED. Resolving the pinned upstream package dependencies before running its Piece import. Next: observe differential failure, implement the exact behavior, then native/Miri checks.
- Test execution remains queued: shared heavy slots are held by analyzer body-oracle and a Next.js production build. No limiter bypass and no pass/fail result claimed for Step 5 yet.

### Acceptance measurements (current)
| Measure | Dart 3.13.3 | Rust | Result |
|---|---|---|---|
| Full formatter corpus differences | Baseline CLI available | Formatter executable absent | Not run |
| Fastest / median formatting time | Not measured | Not measured | Open |
| Peak RSS | Not measured | Not measured | Open |
| Stripped / unstripped formatter binary size | Not measured | No formatter binary | Open |
| Compile / cold-start time | Not measured | Not measured | Open |
| Instructions / coverage | Not measured | Not measured | Open |
- Native RED confirmed: `/tmp/rust-dstyle-piece-native-red.log`, 0/4 pass. Failures identify numeric ordering, canonical identity and both shape merge rules. Initial wrong-directory Cargo invocation was corrected and is not counted as RED.
- Upstream dependencies resolved (analyzer 14.7.0, _fe_analyzer_shared 111.0.0); package config/cache remain untracked/ignored. Real upstream differential RED running next.
- First upstream Piece run reached the harness's 60-second process deadline during Dart compilation (`/tmp/rust-dstyle-piece-red.log`), not a comparison failure. Increased the subprocess deadline to 300 seconds because this import pulls in the complete formatter/analyzer; version enforcement and exact comparison are unchanged. No compatibility result inferred from the timeout.
- Real upstream RED confirmed after 70 seconds: `/tmp/rust-dstyle-piece-red2.log` reaches the exact comparison and fails. Upstream confirms the expected canonical/noncanonical identity and numeric ordering behavior.
- Implemented State ordering/identity and Shape merge. Canonical identity is represented by the immutable value/cost pair, avoiding a global interning table; non-const instances use shared allocation identity. No unsafe. Next: GREEN differential/native suite and Miri.
- GREEN: `/tmp/rust-dstyle-piece-green.log`, all 3 differential tests and 14 focused tests pass. New Piece primitive oracle: 442/442 rows, zero differences against real Dart 3.13.3/upstream source. Existing output 260 rows and debug 128 trees remain green.
- Miri GREEN: `/tmp/rust-dstyle-piece-miri.log`, all 4 piece tests pass. Combined focused Miri coverage now includes 10 Code cases and 4 piece primitive cases (14 tests); differential subprocess tests run natively, not under Miri.
- Running instrumented full crate tests for line coverage in `/tmp/rust-dstyle-coverage` (outside repository), using the installed Rust LLVM tools. Next: record coverage, commit the primitive slice, continue with abstract Piece/CodeWriter/Solution/Solver.
- Instrumented full crate suite GREEN: `/tmp/rust-dstyle-coverage.log`. LLVM report `/tmp/rust-dstyle-coverage-report.txt`: Code 215/215 lines, 302/302 regions; Piece primitives 50/50 lines, 54/54 regions. Total 265/265 lines and 356/356 regions (100%). Branch coverage not collected. This is coverage of the two existing ported files only.
- Coverage generation: `RUSTFLAGS='-C instrument-coverage' CARGO_TARGET_DIR=/tmp/rust-dstyle-coverage LLVM_PROFILE_FILE='/tmp/rust-dstyle-coverage/profiles/%p-%m.profraw' DART=~/.cache/rust-dstyle/dart-sdk/bin/dart ~/heavy.sh ~/.cargo/bin/cargo test --manifest-path experiments/dart_sdk/Cargo.toml -p dart_style`; merge profiles with installed stable `llvm-profdata`, report all test executables with `llvm-cov report`, excluding `/tests/|/rustc/`.

## Final report — partial implementation, 2026-11-06
- Preserved and verified inherited backend work, committed debug traversal/signed offsets as `097122b8d`, and added State/Shape primitives with real upstream RED→GREEN evidence.
- All 3 differential tests pass (260 output rows, 128 debug trees, 442 primitive rows; zero differences). All 14 focused tests pass natively and under Miri. Instrumented suite passes; current ported source line/region coverage is 100%; branch coverage is unmeasured. `forbid(unsafe_code)` remains in force.
- The requested full formatter port is **not finished**. Abstract Piece, CodeWriter, Solution/cache/Solver, concrete pieces, AST visitor, declarations/statements/expressions/comments, formatter executable, corpus differential tests and all performance acceptance gates remain. No formatter parity or speed/memory/size claim is made. These are implementation work, not an external blocker.
- Next: port abstract Piece and the CodeWriter/Solution/Solver cycle with a real-upstream piece-tree formatting oracle before implementation; then concrete pieces and AST integration. Keep upstream corpus/options/language-version/selection semantics intact and use the real Dart 3.13.3 CLI for the final corpus gate.
- Branch: `agent/rust-dstyle`; local commits only. No push, PR, merge, publish, deploy or messages. No own test processes remain running at this checkpoint. Raw logs are in `/tmp/rust-dstyle-*`; the README records durable results and reproduction instructions.
