# Shelf phase 3 progress

Branch: `feat/shelf-websocket`. Worktree: `/home/sigmadev/dv-shelf-ws`.
User restrictions: local commits only; no pushes, merges, publishing, deployment or messages.
Commit author: SigmaDev / Danroyal001 noreply (no AI trailers).

## Step 1 — Context, git status and baseline inspection
- Done: read server handbook (~/AGENTS.md), gss-context.md, task-shelf-p3.md, task-shelf-ws.md, PROGRESS-shelf-ws.md, PROGRESS-shelf-ws2.md, and doc/shelf-parity.md. Confirmed git status clean on branch `feat/shelf-websocket`, `origin/main` at `1c27eb87` (no rebase needed as origin/main has not moved).
- Baseline inspection:
  - Phase 1 & 2 completed: 190 Dart tests + 32 Rust tests.
  - Phase 3 scope:
    1. Semantics bug: `NativeWebSocketChannel.sink.add` throwing on full queue (8 messages). Must buffer in Dart without throwing, backpressure via dart:io WebSocket semantics, bounded memory on `addStream`, test with burst of 10,000 `sink.add` to slow client arriving in order.
    2. WebSocket throughput: batch frames per wakeup, avoid double copies, profile and optimize FFI and serialization to target >= Shelf msgs/s.
    3. Upload/download throughput: larger chunk coalescing (64-256 KiB), external typed data / zero-copy across FFI, fewer acks per chunk. Target >= Shelf MiB/s.
    4. 3-trial isolated AOT benchmarks via `~/heavy.sh` updating doc/shelf-parity.md honestly.
- Tests: baseline validation running (190 Dart tests, 32 Rust tests green).
- Next: Step 2 — WebSocket `sink.add` semantics bug (write failing test first, buffer in Dart, eliminate throw on full queue).
- Blockers: none.

## Step 2 — WebSocket `sink.add` semantics bug
- Done:
  - Added reproducer test in `test/websocket_test.dart` asserting 10,000 burst `sink.add` calls delivered to a slow client (simulated via subscription pause/resume intervals). Observed test failing as expected with `Expected: <10000>, Actual: <0>` due to `StateError` on message 8 and channel disposal.
  - Replaced throwing behavior in `_NativeSink` with in-memory message queue (`Queue<_QueuedMessage>`). `sink.add` now buffers in Dart without throwing on a full native queue, matching `dart:io` WebSocket semantics.
  - Maintained strictly bounded memory on `addStream` and `channel.send`: each awaits completion until the frame is accepted into the native queue, pausing the stream producer.
  - Replaced per-send `malloc`/`calloc` allocations in `NativeWebSocketChannel` with reusable 64 KiB scratch buffers for sends.
  - Updated `run_websocket` in Rust: batched frame writes using `sink.feed()` and drained `outgoing.try_recv()` before `sink.flush().await`, followed by `ws_wakeup(req_id, server_id)` to notify Dart of outgoing capacity without polling.
  - Rebuilt `libdartvel_shelf.so` and updated atomic binary.
- Tests:
  - `dart test test/websocket_test.dart -N "burst of 10,000"` passes cleanly.
  - All 8 tests in `test/websocket_test.dart` pass.
  - `native_symbols_test.dart` and `render_parity_test.dart` pass.
  - `dart analyze lib/ test/` reports 0 issues in modified files.
- Next: Step 3 — WebSocket throughput profiling and optimization (profiled via profile_ws.dart; timer removed, batch feed/flush in rust, batch draining in Dart wakeup; remaining costs: string/UTF-8 conversions, per-FFI-crossing overhead, queue locking). Target >= Shelf's msgs/s.
- Blockers: none.

## Step 3 — WebSocket throughput profiling and optimization
- Done (start): read shelf-parity.md baseline (Dartvel 3,506 vs Shelf 8,252 msgs/s, 2.4x gap). Confirmed 50ms polling timer removed from `NativeWebSocketChannel.start()`; rust `run_websocket` batches `outgoing.try_recv()` before `sink.flush().await`; Dart `onWakeup()` drains queue and pumps outgoing without polling.
- Profiled via `benchmark/profile_ws.dart`: Dartvel ~1,750 msgs/s, shelf ~2,016 msgs/s (sequential ping-pong). Confirmed overhead sources: per-message `utf8.encode` / `Uint8List.fromList` copy in Dart, `str::from_utf8` + `.to_string()` + `.into_bytes()` copy in rust `aw_ws_send`, individual FFI crossing per queued message (`_pumpOutgoing` tries one at a time), `Queue` overhead in Dart, mutex locking in rust `mpsc` channels.
- Tests: `test/websocket_test.dart` all 8 pass; `native_symbols_test.dart` passes.
- Next: Apply throughput optimizations (reduce conversion overhead, batch more aggressively where ABI allows, consider reuse buffers).
