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
