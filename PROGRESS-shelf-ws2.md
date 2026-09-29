# Shelf phase 2 progress (Part 2)

Branch: `feat/shelf-websocket`. Worktree: `/home/sigmadev/dv-shelf-ws`.
User restrictions: local commits only; no pushes, merges, publishing, deployment or messages.
Commit author: SigmaDev / Danroyal001 noreply (no AI trailers).

## Step 1 — Context, git status and rebasing onto origin/main
- Done: read server handbook (~/AGENTS.md), gss-context.md, task-shelf-ws.md, task-shelf-ws-2.md, and Codex's PROGRESS-shelf-ws.md (steps 1–6). Inspected git status and remote origin/main. Rebased `feat/shelf-websocket` cleanly onto `origin/main` (incorporating commit 1c27eb87 "send a slow response body as it is produced" and its test).
- Test results: full `dart test` in `packages/dartvel_shelf` passed (189 passed, 3 skipped); `~/.cargo/bin/cargo test` in `packages/dartvel_shelf/rust` passed (32 passed); `native_symbols_test.dart` and `render_parity_test.dart` passed (3 passed).
- Next: Step 2 — Response backpressure. Address the unbounded native response bridge queue discovered by Codex.
- Blockers: none.

## Step 2 — Response body backpressure
- Done: analyzed native response bridge in `rust/src/lib.rs` and Dart stream delivery in `lib/src/server.dart`. Confirmed `mpsc::unbounded_channel` and unthrottled `(source ?? resp.body!.stream).listen(...)` allowed 200 MiB of response chunks to pile into native memory. Wrote `test/response_backpressure_test.dart` simulating a fast 200 MiB generator with a slow-reading/paused TCP client. Observed test failing with 208 MiB in-flight queue before fix. Implemented bounded channel (8 chunks) in Rust with `try_send`, backpressure ack callback (`DartStreamAckHandler` / `aw_register_stream_ack_handler`), and subscription pausing/resuming in Dart (`_StreamResponseState` with 4-chunk window). Rebuilt `libdartvel_shelf.so` and regenerated bindings.
- Test results: `test/response_backpressure_test.dart` passes cleanly; fast 200 MiB generator strictly pauses when client pauses, queued bytes bounded to socket buffer (~1.1–5.6 MiB vs 208 MiB previously), and full 200 MiB payload arrives intact. Full `dart test` (190 passed, 3 skipped), `cargo test` (32 passed), `native_symbols_test.dart` and `render_parity_test.dart` (3 passed) all green.
- Next: Step 3 — WebSocket lifecycle checks and native wakeup/notification (addressing polling loop).
- Blockers: none.



