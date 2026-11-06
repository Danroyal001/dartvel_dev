# dart_style Rust port progress

## Step 1 — context and base (2026-11-06)
- Read server rules, repository AGENTS.md/CLAUDE.md, task brief, queue Rust gates, proposal and latest lead handoff.
- Initial worktree was release 0.13.21 without experiments. Created `rust/dart-style` from local `feat/rust-stack-experiments` (6d52539f1).
- SDK DEPS pins dart_style to `76978d23bfb3d225c81ce3f119ab7055a2a57136`; third_party checkout is absent.
- System Dart is 3.13.4, not the required 3.13.3 oracle. Locating exact SDK before comparisons.
- No tests or measurements yet; nothing ported. Next: vendor exact pinned source, establish oracle and failing comparison, then piece/solver core.
- User's latest instruction overrides brief push rule: local commits only; no push, merge, publish, deployment or messages.
