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
